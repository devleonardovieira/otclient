/*
 * Copyright (c) 2010-2025 OTClient <https://github.com/edubart/otclient>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#include "fontmanager.h"

#include "framework/core/resourcemanager.h"
#include "framework/otml/otmldocument.h"

FontManager g_fonts;

void FontManager::terminate() { clearFonts(); }

void FontManager::clearFonts() {
    m_fonts.clear();
    m_defaultFont = nullptr;
    m_defaultWidgetFont = nullptr;
}

bool FontManager::importFont(const std::string& file)
{
    const auto& path = g_resources.guessFilePath(file, "otfont");
    try {
        const auto& doc = OTMLDocument::parse(path);
        const auto& fontNode = doc->at("Font");
        const auto& name = fontNode->valueAt("name");

        // remove any font with the same name
        for (auto it = m_fonts.begin(); it != m_fonts.end(); ++it) {
            if ((*it)->getName() == name) {
                m_fonts.erase(it);
                break;
            }
        }

        const auto& font(std::make_shared<BitmapFont>(name));
        font->load(fontNode);
        m_fonts.emplace_back(font);

        // set as default if needed
        if (!m_defaultFont || fontNode->valueAt<bool>("default", false))
            m_defaultFont = font;
        else if (!m_defaultWidgetFont || fontNode->valueAt<bool>("widget-default", false))
            m_defaultWidgetFont = font;

        return true;
    } catch (const stdext::exception& e) {
        g_logger.error("Unable to load font from file '{}': {}", path, e.what());
        return false;
    }
}

bool FontManager::fontExists(const std::string_view fontName)
{
    for (const auto& font : m_fonts) {
        if (font->getName() == fontName)
            return true;
    }
    return false;
}

BitmapFontPtr FontManager::getFont(const std::string_view fontName)
{
    // find font by name
    for (const auto& font : m_fonts) {
        if (font->getName() == fontName)
            return font;
    }

    // Lazy import: try to resolve "family style size" or "family size" using
    // a per-family config file under /fonts/<Family>/ (otfont or otml)
    auto split = [](const std::string& s) {
        std::vector<std::string> parts; std::istringstream iss(s);
        for (std::string p; iss >> p;) parts.push_back(p);
        return parts;
    };
    auto toLower = [](std::string s) {
        std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c){ return static_cast<char>(std::tolower(c)); });
        return s;
    };

    const std::string name(fontName);
    const auto parts = split(name);
    if (parts.size() >= 2) {
        // last must be a size
        int size = -1;
        try { size = std::stoi(parts.back()); } catch (...) { size = -1; }
        if (size > 0) {
            const std::string family = parts.front();
            // default style when not provided
            std::string style = (parts.size() >= 3) ? parts[1] : "";

            // search for a family config file
            const std::string familyDir = "/fonts/" + family;
            std::list<std::string> candidates;
            // Prefer files inside the family directory
            for (const auto& f : g_resources.listDirectoryFiles(familyDir, true, false, false)) {
                if (g_resources.isFileType(f, "otfont") || g_resources.isFileType(f, "otml"))
                    candidates.push_back(f);
            }
            // Fallback to recursive search under /fonts
            if (candidates.empty()) {
                for (const auto& f : g_resources.listDirectoryFiles("/fonts", true, false, true)) {
                    if (g_resources.isFileType(f, "otfont") || g_resources.isFileType(f, "otml"))
                        candidates.push_back(f);
                }
            }

            auto tryImportFromConfig = [&](const std::string& cfgPath) -> bool {
                try {
                    const auto& doc = OTMLDocument::parse(cfgPath);
                    if (!doc)
                        return false;

                    // Config root may be a child tagged 'Font' or 'FontFamily'
                    auto root = doc->get("Font");
                    if (!root) root = doc->get("FontFamily");
                    if (!root)
                        return false;

                    std::string cfgFamily;
                    if (root->hasChildAt("family")) cfgFamily = root->valueAt<std::string>("family");
                    if (cfgFamily.empty()) return false;
                    if (toLower(cfgFamily) != toLower(family)) return false;

                    const std::string ftype = root->valueAt<std::string>("type", std::string("ttf"));
                    // resolve default style if not provided
                    if (style.empty()) style = root->valueAt<std::string>("default-style", std::string("regular"));

                    const auto stylesNode = root->get("styles");
                    if (!stylesNode) return false;
                    // Try exact style match first
                    auto styleNode = stylesNode->get(style);
                    // Fallback: case-insensitive match across children (handles camelCase/case differences)
                    if (!styleNode) {
                        for (const auto& child : stylesNode->children()) {
                            if (toLower(child->tag()) == toLower(style)) {
                                styleNode = child;
                                break;
                            }
                        }
                    }
                    if (!styleNode) return false;

                    const std::string fileBase = styleNode->valueAt<std::string>("file", std::string(""));
                    if (fileBase.empty()) return false;

                    // Optional spacing config; accept either 'extra-spacing: x y' or split keys
                    int spacingX = 0;
                    int spacingY = 0;
                    if (const auto& node = styleNode->get("extra-spacing")) {
                        // try parse as Size "x y"
                        try {
                            const auto pair = node->value<Size>();
                            spacingX = pair.width();
                            spacingY = pair.height();
                        } catch (...) {
                            // fallback single int
                            spacingX = node->value<int>();
                        }
                    } else {
                        spacingX = styleNode->valueAt<int>("extraSpacing", 0);
                        spacingY = styleNode->valueAt<int>("extra-spacing-y", styleNode->valueAt<int>("extraSpacingY", 0));
                    }
                    const int yOffset  = styleNode->valueAt<int>("y-offset", styleNode->valueAt<int>("yOffset", 0));

                    // compute base dir from cfgPath
                    std::string baseDir = cfgPath;
                    const auto pos = baseDir.find_last_of('/');
                    if (pos != std::string::npos) baseDir = baseDir.substr(0, pos);
                    else baseDir = "/fonts"; // fallback

                    const std::string fontRegName = name; // register with the requested composite name
                    if (ftype == "ttf") {
                        if (importTTFFont(fontRegName, baseDir + "/" + fileBase, size, spacingX, spacingY, yOffset))
                            return true;
                        return false;
                    }
                    // For bitmap .otfont, just import the file (size ignored, embedded)
                    std::string otfontPath = baseDir + "/" + fileBase;
                    if (!g_resources.isFileType(otfontPath, "otfont")) otfontPath += ".otfont";
                    return importFont(otfontPath);
                } catch (const stdext::exception& e) {
                    g_logger.warning("Unable to parse font family config '{}': {}", cfgPath, e.what());
                    return false;
                }
            };

            for (const auto& cfg : candidates) {
                if (tryImportFromConfig(cfg)) {
                    // after importing, return the newly registered font
                    for (const auto& font : m_fonts) {
                        if (font->getName() == fontName)
                            return font;
                    }
                }
            }
        }
    }

    // when not found, fallback to default font
    g_logger.error("font '{}' not found", fontName);
    return m_defaultFont;
}

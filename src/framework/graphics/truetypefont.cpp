/*
 * TrueType (.ttf) font import and atlas generation using stb_truetype
 */

#include "fontmanager.h"
#include "bitmapfont.h"
#include "image.h"

#include <framework/core/resourcemanager.h>
#include <framework/otml/otml.h>

#include <algorithm>
#include <sstream>
#include <vector>
#include <cmath>

// stb_truetype single-header
#define STB_TRUETYPE_IMPLEMENTATION
#define STBTT_STATIC
#include "thirdparty/stb_truetype.h"

static inline int clampi(int v, int lo, int hi) {
    if (v < lo) return lo;
    if (v > hi) return hi;
    return v;
}

bool FontManager::importTTFFont(const std::string& fontName,
                                const std::string& ttfFile,
                                const int pixelHeight,
                                const int spacingX,
                                const int spacingY,
                                const int yOffset)
{
    // Ler arquivo TTF/OTF
    std::string ttfPath = ttfFile;
    if (!(g_resources.isFileType(ttfPath, "ttf") || g_resources.isFileType(ttfPath, "otf"))) {
        // tentar adivinhar extensão quando não fornecida
        ttfPath = g_resources.guessFilePath(ttfFile, "ttf");
        if (!g_resources.fileExists(ttfPath))
            ttfPath = g_resources.guessFilePath(ttfFile, "otf");
    }
    std::string ttfData;
    try {
        ttfData = g_resources.readFileContents(ttfPath);
    } catch (const stdext::exception& e) {
        g_logger.error("Unable to read TTF '{}': {}", ttfPath, e.what());
        return false;
    }

    stbtt_fontinfo info{};
    // Use o offset correto do font index (0) para suportar TTF/TTC/OTF
    const int fontOffset = stbtt_GetFontOffsetForIndex(reinterpret_cast<const unsigned char*>(ttfData.data()), 0);
    if (!stbtt_InitFont(&info, reinterpret_cast<const unsigned char*>(ttfData.data()), fontOffset)) {
        g_logger.error("Failed to init TTF font '{}': invalid format", ttfPath);
        return false;
    }

    // Métricas base
    int ascent = 0, descent = 0, lineGap = 0;
    stbtt_GetFontVMetrics(&info, &ascent, &descent, &lineGap);
    const float scale = stbtt_ScaleForPixelHeight(&info, static_cast<float>(pixelHeight));
    const int baseline = static_cast<int>(std::round(ascent * scale));

    // Descobrir largura máxima do bitmap dos glyphs para definir grid
    const int firstGlyph = 32;
    const int lastGlyph = 255;
    int maxGlyphW = 0;
    for (int cp = firstGlyph; cp <= lastGlyph; ++cp) {
        int x0, y0, x1, y1;
        stbtt_GetCodepointBitmapBox(&info, cp, scale, scale, &x0, &y0, &x1, &y1);
        {
            const int w = x1 - x0;
            maxGlyphW = (maxGlyphW > w ? maxGlyphW : w);
        }
    }

    const int cellW = (maxGlyphW > pixelHeight) ? maxGlyphW : pixelHeight;
    const int cols = 16;
    const int totalGlyphs = (lastGlyph - firstGlyph + 1);
    const int rows = (totalGlyphs + cols - 1) / cols;

    // Criar atlas RGBA com transparência
    const Size atlasSize(cols * cellW, rows * pixelHeight);
    auto atlas = std::make_shared<Image>(atlasSize, 4, nullptr);

    // Renderizar cada glyph e colar no atlas
    for (int cp = firstGlyph; cp <= lastGlyph; ++cp) {
        int w = 0, h = 0, xoff = 0, yoff = 0;
        // Use the same scale for X and Y; passing 0 for scale_x
        // results in zero-width bitmaps and invisible glyphs.
        unsigned char* bitmap = stbtt_GetCodepointBitmap(&info, scale, scale, cp, &w, &h, &xoff, &yoff);
        if (!bitmap || w <= 0 || h <= 0) {
            if (bitmap) stbtt_FreeBitmap(bitmap, nullptr);
            continue;
        }

        // Converter para RGBA branco com alpha do bitmap
        std::vector<uint8_t> rgba(static_cast<size_t>(w) * static_cast<size_t>(h) * 4);
        for (int i = 0; i < w * h; ++i) {
            const uint8_t a = bitmap[i];
            rgba[i * 4 + 0] = 255;
            rgba[i * 4 + 1] = 255;
            rgba[i * 4 + 2] = 255;
            rgba[i * 4 + 3] = a;
        }
        auto glyphImg = std::make_shared<Image>(Size(w, h), 4, rgba.data());

        const int index = cp - firstGlyph;
        const int col = index % cols;
        const int row = index / cols;

        const int destX = col * cellW + (xoff > 0 ? xoff : 0);
        int destY = row * pixelHeight + baseline + yoff; // alinhar baseline
        destY = clampi(destY, row * pixelHeight, row * pixelHeight + pixelHeight - h);

        atlas->blit(Point(destX, destY), glyphImg);

        stbtt_FreeBitmap(bitmap, nullptr);
    }

    // Largura do espaço
    int advanceWidth = 0, leftBearing = 0;
    stbtt_GetCodepointHMetrics(&info, ' ', &advanceWidth, &leftBearing);
    int spaceWidth = static_cast<int>(std::round(advanceWidth * scale));
    if (spaceWidth <= 0) spaceWidth = ((pixelHeight / 3) > 1 ? (pixelHeight / 3) : 1);

    // Salvar atlas em arquivo no diretório de escrita
    const std::string outPngBase = "generated/fonts/" + fontName + "_" + std::to_string(pixelHeight);
    const std::string outPngPath = outPngBase + ".png";
    // Garantir diretórios
    g_resources.makeDir("generated");
    g_resources.makeDir("generated/fonts");
    try {
        atlas->savePNG(outPngPath);
    } catch (const stdext::exception& e) {
        g_logger.error("Unable to save TTF atlas '{}': {}", outPngPath, e.what());
        return false;
    }

    // Construir OTML node equivalente ao .otfont
    const auto fontNode = OTMLNode::create("Font");
    fontNode->addChild(OTMLNode::create("name", fontName));
    // O caminho da textura deve ser absoluto (prefixo '/') para evitar
    // resolução relativa ao script atual e garantir leitura pelo ResourceManager
    fontNode->addChild(OTMLNode::create("texture", "/" + outPngBase)); // sem extensão, será resolvido como .png
    fontNode->addChild(OTMLNode::create("height", std::to_string(pixelHeight)));
    fontNode->addChild(OTMLNode::create("glyph-size", std::to_string(cellW) + " " + std::to_string(pixelHeight)));
    fontNode->addChild(OTMLNode::create("space-width", std::to_string(spaceWidth)));
    if (spacingX != 0 || spacingY != 0)
        fontNode->addChild(OTMLNode::create("spacing", std::to_string(spacingX) + " " + std::to_string(spacingY)));
    if (yOffset != 0)
        fontNode->addChild(OTMLNode::create("y-offset", std::to_string(yOffset)));

    // Remover fonte existente com mesmo nome
    for (auto it = m_fonts.begin(); it != m_fonts.end(); ++it) {
        if ((*it)->getName() == fontName) {
            m_fonts.erase(it);
            break;
        }
    }

    // Criar BitmapFont e carregar a partir do node
    const auto font = std::make_shared<BitmapFont>(fontName);
    font->load(fontNode);
    m_fonts.emplace_back(font);

    // Definir como padrão caso não exista
    if (!m_defaultFont)
        m_defaultFont = font;

    return true;
}
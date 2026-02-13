/*
 * Copyright (c) 2010-2022 OTClient <https://github.com/edubart/otclient>
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

#include "minimap.h"
#include "tile.h"
#include "game.h"
#include "localplayer.h"

#include <zlib.h>
#include <framework/core/filestream.h>
#include <framework/core/resourcemanager.h>
#include <framework/core/eventdispatcher.h>
#include <framework/graphics/drawpoolmanager.h>
#include <framework/graphics/image.h>
#include <framework/graphics/texture.h>

Minimap g_minimap;
static MinimapTile nulltile;
static CacheBlock nullCachedBlock;

const auto& MINIMAP_PATH = std::string("/minimap/");

void MinimapBlock::clean()
{
    m_texture = nullptr;
    m_mustUpdate = false;
}

void MinimapBlock::update()
{
    if (!m_mustUpdate)
        return;

    ImagePtr image = std::make_shared<Image>(Size(MMBLOCK_SIZE, MMBLOCK_SIZE));

    bool shouldDraw = false;
    for (int x = 0; x < MMBLOCK_SIZE; ++x) {
        for (int y = 0; y < MMBLOCK_SIZE; ++y) {
            uint8_t c = getTile(x, y).color;
            Color col = Color::alpha;
            if (c != UINT8_MAX) {
                col = Color::from8bit(c);
                shouldDraw = true;
            }
            image->setPixel(x, y, col);
        }
    }

    if (shouldDraw)
        m_texture = std::make_shared<Texture>(image);
    else
        m_texture.reset();

    m_mustUpdate = false;
}

void MinimapBlock::updateHD(const Position& pos)
{
    static Timer m_timerToLoader;

    if (!m_mustUpdate)
        return;

    if (m_timerToLoader.ticksElapsed() < DrawPool::FPS60) {
        m_lastUpdate.restart();
        return;
    }

    bool shouldDraw = false;
    for (int_fast8_t y = -1; ++y < MMBLOCK_SIZE;) {
        for (int_fast8_t x = -1; ++x < MMBLOCK_SIZE;) {
            const auto& tile = getTile(x, y);
            if (tile.hasItems()) {
                shouldDraw = true;
                break;
            }
        }

        if (shouldDraw)
            break;
    }

    m_mustUpdate = false;

    if (!shouldDraw) {
        m_texture = nullptr;
        return;
    }

    m_lastUpdate.restart();
    m_timerToLoader.restart();

    g_drawPool.addAction([] {
        const auto& fbo = g_minimap.getFrameBuffer();
        fbo->resize(MMTEXTURE_SIZE);
        fbo->bind();
    });

    const auto& getTile = [&](int x, int y) {
        if (x == MMBLOCK_SIZE || y == MMBLOCK_SIZE) {
            const auto& position = pos.translated(x, y);
            g_minimap.load(pos.z, g_minimap.getBlockIndex(position), true);
            return g_minimap.hasBlock(position) ? g_minimap.getTile(position) : nulltile;
        }

        return m_tiles[getTileIndex(x, y)];
    };

    const auto oldScale = g_drawPool.getScaleFactor();
    const float scaleFactor = MMTILE_SIZE / static_cast<float>(g_gameConfig.getSpriteSize());
    g_drawPool.setScaleFactor(scaleFactor);

    const int numTiles = MMBLOCK_SIZE + 1;
    const int numDiagonals = 2 * numTiles - 1;
    for (int diagonal = 0; diagonal < numDiagonals; ++diagonal) {
        int advance = std::max<int>(diagonal - numTiles, 0);
        for (int y = diagonal - advance, x = advance; y >= 0 && x < numTiles; --y, ++x) {
            const auto& tile = getTile(x, y);
            if (tile.hasItems()) {
                int elevation = 0;
                for (const auto& item : tile.items) {
                    if (item.id == 0)
                        break;

                    const auto& thingType = g_things.getThingType(item.id, ThingCategoryItem);
                    thingType->draw(Point(x * MMTILE_SIZE, y * MMTILE_SIZE) - elevation, 0, item.xPattern, item.yPattern, item.zPattern, 0, Color::white);
                    if (thingType->hasElevation())
                        elevation = std::min<uint8_t>(elevation + thingType->getElevation(), g_gameConfig.getTileMaxElevation());
                }
            }
        }
    }

    g_drawPool.addAction([self = shared_from_this()] {
        const auto& fbo = g_minimap.getFrameBuffer();
        fbo->release();
        self->m_texture = fbo->extractTexture();
    });
    g_drawPool.flush();

    g_drawPool.setScaleFactor(oldScale);
}

bool MinimapBlock::updateTile(int x, int y, const MinimapTile& newTile)
{
    auto& tile = m_tiles[getTileIndex(x, y)];
    if (tile.equalsItems(newTile)) {
        tile.flags = newTile.flags;
        tile.color = newTile.color;
        tile.speed = newTile.speed;
        return false;
    }

    tile = newTile;
    m_mustUpdate = true;
    return true;
}

void Minimap::init() {
    g_dispatcher.addEvent([this] {
        g_resources.makeDir(MINIMAP_PATH);
        cacheBlockFileName();
    });

    m_tileBlocks.resize(g_gameConfig.getMapMaxZ() + 1);
    m_cachedBlock.resize(g_gameConfig.getMapMaxZ() + 1);
    m_blockSaved.resize(g_gameConfig.getMapMaxZ() + 1);
    updatedTiles.resize(g_gameConfig.getMapMaxZ() + 1);

    m_fbo = std::make_shared<FrameBuffer>();

    // Garbage Collection
    {
        static constexpr uint16_t
            WAITING_TIME = 10 * 1000, // waiting time for next check, default 1 min.
            IDLE_TIME = 10 * 1000,     // Maximum time it can be idle, default 1 min.
            CACHED_IDLE_TIME = 60 * 1000,
            MAX_UNLOADS_PER_CYCLE = 24,
            MAX_CACHED_PRUNE_PER_CYCLE = 64;

        m_gcEvent = g_dispatcher.cycleEvent([&] {
            std::scoped_lock lock(m_lock);

            const auto& playerPos = g_game.getLocalPlayer() ? g_game.getLocalPlayer()->getPosition() : Position();
            uint16_t unloadedBlocks = 0;
            uint16_t prunedCachedBlocks = 0;

            for (uint_fast8_t z = 0; z <= g_gameConfig.getMapMaxZ(); ++z) {
                if (unloadedBlocks >= MAX_UNLOADS_PER_CYCLE && prunedCachedBlocks >= MAX_CACHED_PRUNE_PER_CYCLE)
                    break;

                auto& tileBlocks = m_tileBlocks[z];
                for (auto it = tileBlocks.begin(); it != tileBlocks.end();) {
                    if (unloadedBlocks >= MAX_UNLOADS_PER_CYCLE)
                        break;

                    const auto index = (*it).first;
                    auto& block = (*it).second;

                    if (playerPos.z == z && index == getBlockIndex(playerPos)) {
                        ++it;
                        continue; // do not clear the player block
                    }

                    if (block->lastUpdate() > IDLE_TIME) {
                        saveBlock(z, index);

                        auto& cachedBlock = getCachedBlock(z, index);
                        cachedBlock.loaded = EnumCachedBlockLoad::UNLOADED;
                        if (!m_hdMode && block->getTexture())
                            cachedBlock.texture = block->getTexture();
                        else
                            cachedBlock.texture = nullptr;

                        it = tileBlocks.erase(it);
                        if (++unloadedBlocks >= MAX_UNLOADS_PER_CYCLE)
                            break;
                    } else ++it;
                }

                auto& cachedBlocks = m_cachedBlock[z];
                for (auto it = cachedBlocks.begin(); it != cachedBlocks.end();) {
                    if (prunedCachedBlocks >= MAX_CACHED_PRUNE_PER_CYCLE)
                        break;

                    const auto index = (*it).first;
                    auto& block = (*it).second;

                    if (playerPos.z == z && index == getBlockIndex(playerPos)) {
                        ++it;
                        continue; // do not clear the player block
                    }

                    if (block.lastUpdate() > CACHED_IDLE_TIME) {
                        it = cachedBlocks.erase(it);
                        if (++prunedCachedBlocks >= MAX_CACHED_PRUNE_PER_CYCLE)
                            break;
                    } else ++it;
                }
            }
        }, WAITING_TIME);
    }
}

void Minimap::cacheBlockFileName() {
    for (uint_fast8_t i = 0; i <= g_gameConfig.getMapMaxZ(); ++i)
        m_blockSaved[i].clear();

    const std::string& minimapNameStart = "minimap_";
    for (auto file : g_resources.listDirectoryFiles(MINIMAP_PATH)) {
        if (file.size() <= minimapNameStart.length())
            continue;

        file = file.substr(minimapNameStart.length(), file.find(".") - minimapNameStart.length());

        if (std::count(file.begin(), file.end(), '_') != 1)
            continue;

        const auto strSplited = stdext::split(file, "_");
        auto z = std::stoi(strSplited[0]);
        auto block = std::stoi(strSplited[1]);

        if (z < 0 || z > g_gameConfig.getMapMaxZ())
            continue;

        m_blockSaved[z].insert(block);
    }
}

void Minimap::terminate() {
    if (m_gcEvent) {
        m_gcEvent->cancel();
        m_gcEvent = nullptr;
    }

    clean();

    m_fbo = nullptr;
}

void Minimap::clean()
{
    std::scoped_lock lock(m_lock);
    for (uint_fast8_t i = 0; i <= g_gameConfig.getMapMaxZ(); ++i) {
        m_tileBlocks[i].clear();
        m_cachedBlock[i].clear();
    }
    cacheBlockFileName();
}

void Minimap::draw(const Rect& screenRect, const Position& mapCenter, float scale, const Color& color)
{
    if (screenRect.isEmpty())
        return;

    std::scoped_lock lock(m_lock);

    struct Data
    {
        Rect dest;
        TexturePtr txt;
        float opacity = 1.f;
    };

    static std::vector<Data> textures;
    static std::vector<std::pair<Point, Position>> positionsToDraw;

    checkUpdatedTiles();

    const auto& preDraw = [&](const Position& camera) {
        const auto& mapRect = calcMapRect(screenRect, camera, scale);
        const auto& blockOff = getBlockOffset(mapRect.topLeft());
        auto off = (Point((mapRect.size() * scale).toPoint() - screenRect.size().toPoint()) / 2);

        const auto& start = screenRect.topLeft() - (mapRect.topLeft() - blockOff) * scale - off;

        bool _break = false;

        for (int_fast32_t y = blockOff.y, ys = start.y; ys < screenRect.bottom(); y += MMBLOCK_SIZE, ys += MMBLOCK_SIZE * scale) {
            if (y < 0 || y >= 65536)
                continue;

            for (int_fast32_t x = blockOff.x, xs = start.x; xs < screenRect.right(); x += MMBLOCK_SIZE, xs += MMBLOCK_SIZE * scale) {
                if (x < 0 || x >= 65536)
                    continue;

                const auto& pos = Position(x, y, camera.z);

                load(pos.z, getBlockIndex(pos), false); // Load first time

                if (hasBlock(pos) || hasCachedBlock(pos) && getCachedBlock(pos).texture)
                    positionsToDraw.emplace_back(Point(xs, ys), pos);
            }
        }
    };

    g_drawPool.resetClipRect();

    const auto& oldClipRect = g_drawPool.getClipRect();
    const auto startFloor = mapCenter.z <= g_gameConfig.getMapSeaFloor() ? g_gameConfig.getMapSeaFloor() : std::min<int>(mapCenter.z + 2, g_gameConfig.getMapMaxZ());
    if (m_hdMode) {
        for (int_fast8_t i = startFloor; i >= mapCenter.z; --i) {
            const int offset = mapCenter.z - i;
            const auto& pos = mapCenter.translated(offset, offset, -offset);

            if (MMBLOCK_SIZE * scale > 1 && pos.isMapPosition())
                preDraw(pos);
        }
    } else preDraw(mapCenter);

    if (!positionsToDraw.empty()) {
        const auto firstZ = positionsToDraw[0].second.z;

        bool darkFloorAdded = false;

        for (const auto& [p, pos] : positionsToDraw) {
            if (m_hdMode && !darkFloorAdded && firstZ != mapCenter.z && pos.z == mapCenter.z) {
                Data info = { Rect{}, nullptr, .15f };
                textures.emplace_back(std::move(info));
                darkFloorAdded = true;
            }

            TexturePtr tex;

            if (hasBlock(pos)) {
                const auto& block = getBlock(pos);
                if (m_hdMode)
                    block->updateHD(pos);
                else
                    block->update();

                tex = block->getTexture();
            }

            if (!tex && hasCachedBlock(pos)) {
                auto& block = getCachedBlock(pos);
                block.m_lastUpdate.restart();
                tex = block.texture;
            }

            if (tex) {
                static const Rect src(0, 0, MMBLOCK_SIZE, MMBLOCK_SIZE);
                const Rect dest(p, src.size() * scale);
                Data info = { dest, tex };
                textures.emplace_back(std::move(info));
            }
        }
        positionsToDraw.clear();
    }

    g_drawPool.setClipRect(screenRect); {
        auto backColor = color;
        g_drawPool.addFilledRect(screenRect, backColor);
        for (const auto& data : textures) {
            if (data.txt)
                g_drawPool.addTexturedRect(data.dest, data.txt);
            else {
                backColor.setAlpha(data.opacity);
                g_drawPool.addFilledRect(screenRect, backColor);
            }
        }
    } textures.clear();
    g_drawPool.setClipRect(oldClipRect);
}

bool Minimap::hasBlock(const Position& pos) {
    return m_tileBlocks[pos.z].contains(getBlockIndex(pos));
}

Point Minimap::getTilePoint(const Position& pos, const Rect& screenRect, const Position& mapCenter, float scale)
{
    if (screenRect.isEmpty() || pos.z != mapCenter.z)
        return { -1 };

    const auto& mapRect = calcMapRect(screenRect, mapCenter, scale);
    const auto& off = Point((mapRect.size() * scale).toPoint() - screenRect.size().toPoint()) / 2;
    const auto& posoff = (Point(pos.x, pos.y) - mapRect.topLeft()) * scale;
    return posoff + screenRect.topLeft() - off + (Point(1) * scale) / 2;
}

Position Minimap::getTilePosition(const Point& point, const Rect& screenRect, const Position& mapCenter, float scale)
{
    if (screenRect.isEmpty())
        return {};

    const auto& mapRect = calcMapRect(screenRect, mapCenter, scale);
    const auto& off = Point((mapRect.size() * scale).toPoint() - screenRect.size().toPoint()) / 2;
    const auto& pos2d = (point - screenRect.topLeft() + off) / scale + mapRect.topLeft();
    return { pos2d.x, pos2d.y, mapCenter.z };
}

Rect Minimap::getTileRect(const Position& pos, const Rect& screenRect, const Position& mapCenter, float scale)
{
    if (screenRect.isEmpty() || pos.z != mapCenter.z)
        return {};

    const int tileSize = g_gameConfig.getSpriteSize() * scale;

    Rect tileRect(0, 0, tileSize, tileSize);
    tileRect.moveCenter(getTilePoint(pos, screenRect, mapCenter, scale));
    return tileRect;
}

Rect Minimap::calcMapRect(const Rect& screenRect, const Position& mapCenter, float scale) const
{
    int w = std::ceil(screenRect.width() / scale), h = std::ceil(screenRect.height() / scale);
    if (w % 2 != 0)
        w--;
    if (h % 2 != 0)
        h--;

    Rect mapRect(0, 0, w, h);
    mapRect.moveCenter(Point(mapCenter.x, mapCenter.y));
    return mapRect;
}

void Minimap::updateTile(const Position& pos, const TilePtr& tile)
{
    MinimapTile minimapTile;
    if (tile) {
        int8_t i = -1;
        const auto& addItem = [&](const ThingPtr& thing) {
            // if (thing->isItem() && !thing->isSplash() && thing->getExactSize() <= 64) {
            if (thing->isItem() && !thing->isSplash()) {
                minimapTile.items[std::min<int>(++i, minimapTile.items.size() - 1)] = {
                    thing->getClientId(),
                    thing->getPatternX(),
                    thing->getPatternY(),
                    thing->getPatternZ()
                };
            }
        };

        for (const auto& thing : tile->getThings()) {
            if (!thing->isGround() && !thing->isGroundBorder() && !thing->isOnBottom())
                continue;

            addItem(thing);
        }

        if (tile->hasCommonItem()) {
            for (auto it = tile->getThings().rbegin(); it != tile->getThings().rend(); ++it) {
                const auto& thing = *it;
                if (!thing->isCommon()) continue;
                addItem(thing);
            }
        }

        if (tile->hasTopItem()) {
            for (const auto& thing : tile->getThings()) {
                if (!thing->isOnTop()) continue;
                addItem(thing);
            }
        }

        minimapTile.color = tile->getMinimapColorByte();
        minimapTile.flags |= MinimapTileWasSeen;
        if (!tile->isWalkable(true))
            minimapTile.flags |= MinimapTileNotWalkable;
        if (!tile->isPathable())
            minimapTile.flags |= MinimapTileNotPathable;
        minimapTile.speed = std::min<int>(static_cast<int>(std::ceil(tile->getGroundSpeed() / 10.f)), UINT8_MAX);
    } else {
        minimapTile.flags |= MinimapTileNotWalkable | MinimapTileNotPathable;
    }

    if (minimapTile != nulltile) {
        std::scoped_lock lock(m_lock);
        updatedTiles[pos.z][pos] = std::move(minimapTile);
    }
}

bool Minimap::checkUpdatedTiles() {
    for (auto& tiles : updatedTiles) {
        std::unordered_map<uint32_t, MinimapBlock_ptr> loadedBlocks;
        loadedBlocks.reserve(std::min<size_t>(tiles.size(), 256));

        for (const auto& [pos, minimapTile] : tiles) {
            const uint32_t blockIndex = getBlockIndex(pos);
            auto it = loadedBlocks.find(blockIndex);
            if (it == loadedBlocks.end()) {
                load(pos.z, blockIndex, true); // forced loading if discarded by GC
                it = loadedBlocks.emplace(blockIndex, getBlock(pos)).first;
            }

            const auto& offsetPos = getBlockOffset(Point(pos.x, pos.y));
            if (it->second->updateTile(pos.x - offsetPos.x, pos.y - offsetPos.y, minimapTile))
                it->second->justSaw();
        }

        tiles.clear();
    }

    return true;
}

const MinimapTile& Minimap::getTile(const Position& pos)
{
    if (pos.z <= g_gameConfig.getMapMaxZ() && hasBlock(pos)) {
        const auto& block = getBlock(pos);
        const auto& offsetPos = getBlockOffset(Point(pos.x, pos.y));
        return block->getTile(pos.x - offsetPos.x, pos.y - offsetPos.y);
    }
    return nulltile;
}

std::pair<MinimapBlock_ptr, MinimapTile> Minimap::threadGetTile(const Position& pos)
{
    std::scoped_lock lock(m_lock);

    if (pos.z <= g_gameConfig.getMapMaxZ() && hasBlock(pos)) {
        const auto& block = m_tileBlocks[pos.z][getBlockIndex(pos)];
        if (block) {
            const auto& offsetPos = getBlockOffset(Point(pos.x, pos.y));
            return std::make_pair(block, block->getTile(pos.x - offsetPos.x, pos.y - offsetPos.y));
        }
    }
    return std::make_pair(nullptr, nulltile);
}

bool Minimap::loadImage(const std::string& fileName, const Position& topLeft, float colorFactor)
{
    // non pathable colors
    static Color nonPathableColors[] = {
       "#ffff00"sv, // yellow
    };

    // non walkable colors
    static Color nonWalkableColors[] = {
       "#000000"sv, // oil, black
       "#006600"sv, // trees, dark green
       "#ff3300"sv, // walls, red
       "#666666"sv, // mountain, grey
       "#ff6600"sv, // lava, orange
       "#00ff00"sv, // positon
       "#ccffff"sv, // ice, very light blue
    };

    if (colorFactor <= .01f)
        colorFactor = 1.f;

    try {
        const ImagePtr image = Image::load(fileName);

        const uint8_t waterc = Color::to8bit("#3300cc"sv);

        for (int_fast32_t y = -1; ++y < image->getHeight();) {
            for (int_fast32_t x = -1; ++x < image->getWidth();) {
                Color color = *(uint32_t*)image->getPixel(x, y);
                uint8_t c = Color::to8bit(color * colorFactor);
                int flags = 0;

                if (c == waterc || color.a() == 0) {
                    flags |= MinimapTileNotWalkable;
                    c = UINT8_MAX; // alpha
                }

                if (flags != 0) {
                    for (const Color& col : nonWalkableColors) {
                        if (col == color) {
                            flags |= MinimapTileNotWalkable;
                            break;
                        }
                    }
                }

                if (flags != 0) {
                    for (const Color& col : nonPathableColors) {
                        if (col == color) {
                            flags |= MinimapTileNotPathable;
                            break;
                        }
                    }
                }

                if (c == UINT8_MAX)
                    continue;

                Position pos(topLeft.x + x, topLeft.y + y, topLeft.z);
                const auto& block = getBlock(pos);
                const auto& offsetPos = getBlockOffset(Point(pos.x, pos.y));
                MinimapTile& tile = block->getTile(pos.x - offsetPos.x, pos.y - offsetPos.y);
                if (!(tile.flags & MinimapTileWasSeen)) {
                    tile.color = c;
                    tile.flags = flags;
                    block->mustUpdate();
                }
            }
        }
        return true;
    } catch (const stdext::exception& e) {
        g_logger.error("failed to load OTMM minimap: {}", e.what());
        return false;
    }
}

void Minimap::saveImage(const std::string&, const Rect&)
{
    //TODO
}

std::string getFileName(const uint8_t z, const uint32_t block) {
    return MINIMAP_PATH + "minimap_" + std::to_string(z) + "_" + std::to_string(block) + ".mmz";
}

EnumCachedBlockLoad Minimap::load(const uint8_t z, const uint32_t block, bool forceLoad) {
    static Timer m_timerLoader;

    if (!m_blockSaved[z].contains(block))
        return EnumCachedBlockLoad::FILE_NOT_FOUND;

    auto& cachedBlock = getCachedBlock(z, block);

    if (cachedBlock.loaded == EnumCachedBlockLoad::LOADED)
        return cachedBlock.loaded;

    if (cachedBlock.loaded == EnumCachedBlockLoad::UNLOADED && !forceLoad && cachedBlock.texture)
        return EnumCachedBlockLoad::UNLOADED;

    // is very slow
    //if (!g_resources.fileExists(getFileName(z, block)))
    //     cachedBlock.loaded = EnumCachedBlockLoad::FILE_NOT_FOUND;

    try {
        const auto& fin = g_resources.openFile(getFileName(z, block));

        static constexpr uint32_t blockSize = MMBLOCK_SIZE * MMBLOCK_SIZE * sizeof(MinimapTile);
        std::vector<uint8_t> compressBuffer(compressBound(blockSize));
        std::vector<uint8_t> decompressBuffer(blockSize);

        while (true) {
            Position pos;
            pos.x = fin->getU16();
            pos.y = fin->getU16();
            pos.z = fin->getU8();

            // end of file or file is corrupted
            if (!pos.isValid() || pos.z >= g_gameConfig.getMapMaxZ() + 1)
                break;

            const auto& block = getBlock(pos);
            const uint16_t len = fin->getU16();
            fin->read(compressBuffer.data(), len);

            unsigned long destLen = blockSize;
            const int ret = uncompress(decompressBuffer.data(), &destLen, compressBuffer.data(), len);

            if (ret != Z_OK || destLen != blockSize)
                break;

            memcpy(reinterpret_cast<uint8_t*>(&block->getTiles()), decompressBuffer.data(), blockSize);

            if (!cachedBlock.texture) {
                block->mustUpdate();
            }
        }

        fin->close();

        cachedBlock.loaded = EnumCachedBlockLoad::LOADED;

        m_timerLoader.restart();
    } catch (const stdext::exception& e) {
        cachedBlock.loaded = EnumCachedBlockLoad::NOT_LOADED;
        g_logger.error("failed to load minimap({}): {}", getFileName(z, block), e.what());
    }

    return cachedBlock.loaded;
}

bool Minimap::saveBlock(const uint8_t z, const uint32_t index) {
    static constexpr uint32_t blockSize = MMBLOCK_SIZE * MMBLOCK_SIZE * sizeof(MinimapTile);
    static constexpr uint32_t COMPRESS_LEVEL = 3;

    auto it = m_tileBlocks[z].find(index);
    if (it == m_tileBlocks[z].end())
        return false;

    auto block = it->second;

    if (!block->wasSeen())
        return false;

    try {
        const auto& fin = g_resources.createFile(getFileName(z, index));
        fin->cache();

        const auto& pos = getIndexPosition(index, z);
        fin->addU16(pos.x);
        fin->addU16(pos.y);
        fin->addU8(pos.z);

        std::vector<uint8_t> compressBuffer(compressBound(blockSize));

        unsigned long len = blockSize;
        compress2(compressBuffer.data(), &len, (uint8_t*)&block->getTiles(), blockSize, COMPRESS_LEVEL);
        fin->addU16(len);
        fin->write(compressBuffer.data(), len);

        // Evitar erro de leitura
        const Position invalidPos;
        fin->addU16(invalidPos.x);
        fin->addU16(invalidPos.y);
        fin->addU8(invalidPos.z);

        fin->flush();
        fin->close();

        m_blockSaved[z].insert(index);

        return true;
    } catch (const stdext::exception& e) {
        g_logger.error("failed to save minimap: {}", e.what());
    }

    return false;
}

void Minimap::save()
{
    std::scoped_lock lock(m_lock);
    for (uint_fast8_t z = 0; z <= g_gameConfig.getMapMaxZ(); ++z) {
        for (const auto& [index, block] : m_tileBlocks[z]) {
            saveBlock(z, index);
        }
    }
}

void Minimap::setHDMode(bool v) {
    if (m_hdMode == v)
        return;

    save();
    clean();

    m_hdMode = v;
}

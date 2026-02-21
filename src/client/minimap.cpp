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

#include <algorithm>
#include <array>
#include <cassert>
#include <cmath>
#include <chrono>
#include <iterator>
#include <limits>
#include <zlib.h>
#include <framework/core/asyncdispatcher.h>
#include <framework/core/filestream.h>
#include <framework/core/resourcemanager.h>
#include <framework/core/eventdispatcher.h>
#include <framework/graphics/drawpoolmanager.h>
#include <framework/graphics/image.h>
#include <framework/graphics/texture.h>
#include <type_traits>

Minimap g_minimap;
static const MinimapTile nulltile{};

const auto& MINIMAP_PATH = std::string("/minimap/");
static std::mutex g_minimapIOLock;

static constexpr uint16_t MINIMAP_MAX_ASYNC_LOADS = 3;
static constexpr uint16_t MINIMAP_MAX_ASYNC_SAVES = 2;
static constexpr uint16_t MINIMAP_MAX_UPDATED_TILES_PER_CYCLE = 256;
static constexpr uint16_t MINIMAP_PRIORITY_FLOOR_UPDATES_PER_CYCLE = 192;
static constexpr uint16_t MINIMAP_BACKGROUND_FLOOR_UPDATES_PER_CYCLE = 24;
static constexpr uint16_t MINIMAP_MAX_SYNC_LOADS_PER_CYCLE = 4;
static constexpr uint8_t MINIMAP_HD_BUILD_INTERVAL_MS = 2;

MinimapBlock::MinimapBlock()
{
    m_lastUpdate.restart();
}

void MinimapBlock::clean()
{
    m_texture = nullptr;
    m_mustUpdate = false;
    m_hdTextureReady = false;
}

void MinimapBlock::update()
{
    m_lastUpdate.restart();

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

    m_hdTextureReady = false;
    m_mustUpdate = false;
}

void MinimapBlock::updateHD(const Position& pos)
{
    static Timer m_timerToLoader;

    m_lastUpdate.restart();

    if (!m_mustUpdate)
        return;

    if (m_timerToLoader.ticksElapsed() < MINIMAP_HD_BUILD_INTERVAL_MS) {
        m_lastUpdate.restart();
        return;
    }

    bool hasAnyItems = false;
    bool hasAnyColor = false;
    for (int_fast8_t y = -1; ++y < MMBLOCK_SIZE;) {
        for (int_fast8_t x = -1; ++x < MMBLOCK_SIZE;) {
            const auto& tile = getTile(x, y);
            if (tile.color != UINT8_MAX)
                hasAnyColor = true;
            if (tile.hasItems())
                hasAnyItems = true;

            if (hasAnyColor && hasAnyItems) {
                break;
            }
        }

        if (hasAnyColor && hasAnyItems)
            break;
    }

    m_mustUpdate = false;

    if (!hasAnyColor && !hasAnyItems) {
        m_texture = nullptr;
        m_hdTextureReady = true;
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
            // Avoid synchronous disk load while drawing HD minimap blocks.
            g_minimap.load(pos.z, g_minimap.getBlockIndex(position), false);
            return g_minimap.hasBlock(position) ? g_minimap.getTile(position) : nulltile;
        }

        return m_tiles[getTileIndex(x, y)];
    };

    // Draw a color fallback base for every visible minimap tile. This avoids black holes
    // when HD sprite composition is missing/incomplete for a tile.
    if (hasAnyColor) {
        for (int y = 0; y < MMBLOCK_SIZE; ++y) {
            for (int x = 0; x < MMBLOCK_SIZE; ++x) {
                const auto& tile = getTile(x, y);
                if (tile.color == UINT8_MAX)
                    continue;

                g_drawPool.addFilledRect(
                    Rect(x * MMTILE_SIZE, y * MMTILE_SIZE, MMTILE_SIZE, MMTILE_SIZE),
                    Color::from8bit(tile.color)
                );
            }
        }
    }

    const auto oldScale = g_drawPool.getScaleFactor();
    const float scaleFactor = MMTILE_SIZE / static_cast<float>(g_gameConfig.getSpriteSize());
    g_drawPool.setScaleFactor(scaleFactor);

    if (hasAnyItems) {
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
    }

    g_drawPool.addAction([self = shared_from_this()] {
        const auto& fbo = g_minimap.getFrameBuffer();
        fbo->release();
        self->m_texture = fbo->extractTexture();
    });
    g_drawPool.flush();

    g_drawPool.setScaleFactor(oldScale);
    m_hdTextureReady = true;
}

bool MinimapBlock::updateTile(int x, int y, const MinimapTile& newTile)
{
    m_lastUpdate.restart();

    auto& tile = m_tiles[getTileIndex(x, y)];
    if (tile.equalsItems(newTile)) {
        tile.flags = newTile.flags;
        tile.color = newTile.color;
        tile.speed = newTile.speed;
        return false;
    }

    tile = newTile;
    m_mustUpdate = true;
    m_hdTextureReady = false;
    return true;
}

void Minimap::init() {
    g_dispatcher.addEvent([this] {
        {
            std::scoped_lock ioLock(g_minimapIOLock);
            g_resources.makeDir(MINIMAP_PATH);
        }
        cacheBlockFileName();
    });

    m_tileBlocks.resize(g_gameConfig.getMapMaxZ() + 1);
    m_cachedBlock.resize(g_gameConfig.getMapMaxZ() + 1);
    m_blockSaved.resize(g_gameConfig.getMapMaxZ() + 1);
    m_newSavedBlocks.resize(g_gameConfig.getMapMaxZ() + 1);
    updatedTiles.resize(g_gameConfig.getMapMaxZ() + 1);

    m_fbo = std::make_shared<FrameBuffer>();

    // Garbage Collection
    {
        static constexpr uint16_t
            WAITING_TIME = 2 * 1000,
            IDLE_TIME = 20 * 1000,
            CACHED_IDLE_TIME = 60 * 1000,
            MAX_UNLOADS_PER_CYCLE = 64,
            MAX_CACHED_PRUNE_PER_CYCLE = 256;

        m_gcEvent = g_dispatcher.cycleEvent([&] {
            flushAllSavedBlocks(false);

            std::unique_lock<std::mutex> lock(m_lock, std::try_to_lock);
            if (!lock.owns_lock())
                return;

            applyAsyncLoadedBlocks(lock);

            const auto& playerPos = g_game.getLocalPlayer() ? g_game.getLocalPlayer()->getPosition() : Position();
            uint16_t unloadedBlocks = 0;
            uint16_t prunedCachedBlocks = 0;
            static uint32_t gcCycleCount = 0;

            const auto shrinkUnordered = [](auto& container, const size_t minBuckets = 2048) {
                if (container.bucket_count() <= minBuckets)
                    return;

                if (container.size() * 4 >= container.bucket_count())
                    return;

                using Container = std::remove_reference_t<decltype(container)>;
                Container compacted;
                compacted.reserve(container.size());
                compacted.insert(container.begin(), container.end());
                container.swap(compacted);
            };

            ++gcCycleCount;
            const bool shouldShrink = (gcCycleCount % 5) == 0;

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
                        invalidateAsyncLoad(z, index);
                        if (block && block->wasSeen())
                            saveBlock(z, index, block->getTiles());

                        auto& cachedBlock = getCachedBlock(z, index);
                        cachedBlock.loaded = EnumCachedBlockLoad::UNLOADED;
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
                        invalidateAsyncLoad(z, index);
                        it = cachedBlocks.erase(it);
                        if (++prunedCachedBlocks >= MAX_CACHED_PRUNE_PER_CYCLE)
                            break;
                    } else ++it;
                }

            }

            if (shouldShrink) {
                static uint8_t shrinkFloor = 0;
                const uint8_t floorCount = static_cast<uint8_t>(g_gameConfig.getMapMaxZ() + 1);
                const uint8_t z = shrinkFloor % floorCount;

                shrinkUnordered(m_tileBlocks[z]);
                shrinkUnordered(m_cachedBlock[z]);
                shrinkUnordered(updatedTiles[z], 512);

                shrinkFloor = static_cast<uint8_t>((shrinkFloor + 1) % floorCount);
            }
        }, WAITING_TIME);
    }
}

void Minimap::cacheBlockFileName() {
    std::list<std::string> files;
    {
        std::scoped_lock ioLock(g_minimapIOLock);
        files = g_resources.listDirectoryFiles(MINIMAP_PATH);
    }

    std::scoped_lock savedLock(m_savedBlocksLock);
    for (uint_fast8_t i = 0; i <= g_gameConfig.getMapMaxZ(); ++i) {
        m_blockSaved[i].clear();
        m_newSavedBlocks[i].clear();
    }

    const std::string& minimapNameStart = "minimap_";
    for (auto file : files) {
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

        m_blockSaved[z].push_back(block);
    }

    for (uint_fast8_t i = 0; i <= g_gameConfig.getMapMaxZ(); ++i) {
        auto& blocks = m_blockSaved[i];
        std::sort(blocks.begin(), blocks.end());
        blocks.erase(std::unique(blocks.begin(), blocks.end()), blocks.end());
    }
}

bool Minimap::hasSavedBlock(uint8_t z, uint32_t blockIndex) const
{
    std::scoped_lock savedLock(m_savedBlocksLock);

    const auto& savedBlocks = m_blockSaved[z];
    if (std::binary_search(savedBlocks.begin(), savedBlocks.end(), blockIndex))
        return true;

    const auto& pendingBlocks = m_newSavedBlocks[z];
    return std::binary_search(pendingBlocks.begin(), pendingBlocks.end(), blockIndex);
}

void Minimap::markSavedBlock(uint8_t z, uint32_t blockIndex)
{
    bool shouldForceFlush = false;
    {
        std::scoped_lock savedLock(m_savedBlocksLock);

        const auto& savedBlocks = m_blockSaved[z];
        if (std::binary_search(savedBlocks.begin(), savedBlocks.end(), blockIndex))
            return;

        auto& pendingBlocks = m_newSavedBlocks[z];
        const auto it = std::lower_bound(pendingBlocks.begin(), pendingBlocks.end(), blockIndex);
        if (it != pendingBlocks.end() && *it == blockIndex)
            return;

        pendingBlocks.insert(it, blockIndex);
        shouldForceFlush = pendingBlocks.size() >= 128;
    }

    if (shouldForceFlush)
        flushSavedBlocks(z, true);
}

void Minimap::flushSavedBlocks(uint8_t z, bool force)
{
    std::scoped_lock savedLock(m_savedBlocksLock);

    auto& pendingBlocks = m_newSavedBlocks[z];
    if (pendingBlocks.empty())
        return;

    static constexpr uint16_t MERGE_INTERVAL = 5 * 1000;
    static constexpr size_t MIN_PENDING_TO_MERGE = 64;

    if (!force) {
        if (pendingBlocks.size() < MIN_PENDING_TO_MERGE && m_savedBlocksMergeTimer.ticksElapsed() < MERGE_INTERVAL)
            return;
    }

    auto& savedBlocks = m_blockSaved[z];

    std::vector<uint32_t> merged;
    merged.reserve(savedBlocks.size() + pendingBlocks.size());
    std::merge(savedBlocks.begin(), savedBlocks.end(), pendingBlocks.begin(), pendingBlocks.end(), std::back_inserter(merged));
    merged.erase(std::unique(merged.begin(), merged.end()), merged.end());

    savedBlocks.swap(merged);
    std::vector<uint32_t>().swap(pendingBlocks);

    m_savedBlocksMergeTimer.restart();
}

void Minimap::flushAllSavedBlocks(bool force)
{
    for (uint_fast8_t z = 0; z <= g_gameConfig.getMapMaxZ(); ++z)
        flushSavedBlocks(z, force);
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
    waitAsyncSaves();
    flushAllSavedBlocks(true);

    {
        std::scoped_lock asyncLock(m_asyncLoadLock);
        std::deque<AsyncLoadRequest>().swap(m_asyncLoadQueue);
        std::deque<AsyncLoadedBlock>().swap(m_asyncLoadedBlocks);
        std::unordered_set<uint64_t>().swap(m_asyncQueuedBlocks);
        std::unordered_map<uint64_t, uint32_t>().swap(m_asyncLoadGeneration);
        m_asyncActiveLoads = 0;
    }

    std::unique_lock<std::mutex> lock(m_lock);
    for (uint_fast8_t i = 0; i <= g_gameConfig.getMapMaxZ(); ++i) {
        std::unordered_map<uint32_t, MinimapBlock_ptr>().swap(m_tileBlocks[i]);
        std::unordered_map<uint32_t, CacheBlock>().swap(m_cachedBlock[i]);
        std::unordered_map<Position, MinimapTile, Position::Hasher>().swap(updatedTiles[i]);
    }
}

void Minimap::cleanFast()
{
    flushAllSavedBlocks(true);

    {
        std::scoped_lock asyncLock(m_asyncLoadLock);
        std::deque<AsyncLoadRequest>().swap(m_asyncLoadQueue);
        std::deque<AsyncLoadedBlock>().swap(m_asyncLoadedBlocks);
        std::unordered_set<uint64_t>().swap(m_asyncQueuedBlocks);
        std::unordered_map<uint64_t, uint32_t>().swap(m_asyncLoadGeneration);
        m_asyncActiveLoads = 0;
    }

    std::unique_lock<std::mutex> lock(m_lock);
    for (uint_fast8_t i = 0; i <= g_gameConfig.getMapMaxZ(); ++i) {
        std::unordered_map<uint32_t, MinimapBlock_ptr>().swap(m_tileBlocks[i]);
        std::unordered_map<uint32_t, CacheBlock>().swap(m_cachedBlock[i]);
        std::unordered_map<Position, MinimapTile, Position::Hasher>().swap(updatedTiles[i]);
    }
}

void Minimap::draw(const Rect& screenRect, const Position& mapCenter, float scale, const Color& color, const Point& cameraOffset)
{
    if (screenRect.isEmpty())
        return;

    std::unique_lock<std::mutex> lock(m_lock);

    struct Data
    {
        Rect dest;
        TexturePtr txt;
        float opacity = 1.f;
    };

    std::vector<Data> textures;
    std::vector<std::pair<Point, Position>> positionsToDraw;

    applyAsyncLoadedBlocks(lock);
    checkUpdatedTiles(lock);

    const float spriteSize = static_cast<float>(std::max<int>(g_gameConfig.getSpriteSize(), 1));
    const PointF cameraOffsetTiles(cameraOffset.x / spriteSize, cameraOffset.y / spriteSize);
    const Point cameraOffsetPx(
        static_cast<int>(std::round(-cameraOffsetTiles.x * scale)),
        static_cast<int>(std::round(-cameraOffsetTiles.y * scale))
    );

    const auto& preDraw = [&](const Position& camera) {
        const auto& mapRect = calcMapRect(screenRect, camera, scale);
        const auto& blockOff = getBlockOffset(mapRect.topLeft());
        auto off = (Point((mapRect.size() * scale).toPoint() - screenRect.size().toPoint()) / 2);

        const auto& start = screenRect.topLeft() - (mapRect.topLeft() - blockOff) * scale - off + cameraOffsetPx;

        for (int_fast32_t y = blockOff.y, ys = start.y; ys < screenRect.bottom(); y += MMBLOCK_SIZE, ys += MMBLOCK_SIZE * scale) {
            if (y < 0 || y >= 65536)
                continue;

            for (int_fast32_t x = blockOff.x, xs = start.x; xs < screenRect.right(); x += MMBLOCK_SIZE, xs += MMBLOCK_SIZE * scale) {
                if (x < 0 || x >= 65536)
                    continue;

                const auto& pos = Position(x, y, camera.z);

                if (!hasBlock(pos))
                    load(pos.z, getBlockIndex(pos), false); // Load first time

                if (hasBlock(pos) || hasCachedBlock(pos) && getCachedBlock(pos).texture)
                    positionsToDraw.emplace_back(Point(xs, ys), pos);
            }
        }
    };

    g_drawPool.resetClipRect();

    const auto& oldClipRect = g_drawPool.getClipRect();
    // Keep minimap rendering deterministic: HD mode renders only the current floor.
    // Auxiliary-floor composition can leak low-res block textures and cause visual artifacts.
    if (MMBLOCK_SIZE * scale > 1 && mapCenter.isMapPosition())
        preDraw(mapCenter);

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
                block->touch();
                if (m_hdMode) {
                    if (pos.z == mapCenter.z) {
                        if (!block->isHDReady())
                            block->mustUpdate();
                        block->updateHD(pos);
                    } else {
                        // Off-floor context in minimap: keep a cheaper texture update to reduce frame spikes.
                        block->update();
                    }
                } else
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
    const auto& floorBlocks = m_tileBlocks[pos.z];
    return floorBlocks.find(getBlockIndex(pos)) != floorBlocks.end();
}

Point Minimap::getTilePoint(const Position& pos, const Rect& screenRect, const Position& mapCenter, float scale, const Point& cameraOffset)
{
    if (screenRect.isEmpty() || pos.z != mapCenter.z)
        return { -1 };

    const auto& mapRect = calcMapRect(screenRect, mapCenter, scale);
    const auto& off = Point((mapRect.size() * scale).toPoint() - screenRect.size().toPoint()) / 2;
    const auto& posoff = (Point(pos.x, pos.y) - mapRect.topLeft()) * scale;
    const float spriteSize = static_cast<float>(std::max<int>(g_gameConfig.getSpriteSize(), 1));
    const PointF cameraOffsetTiles(cameraOffset.x / spriteSize, cameraOffset.y / spriteSize);
    const Point cameraOffsetPx(
        static_cast<int>(std::round(-cameraOffsetTiles.x * scale)),
        static_cast<int>(std::round(-cameraOffsetTiles.y * scale))
    );
    return posoff + screenRect.topLeft() - off + cameraOffsetPx + (Point(1) * scale) / 2;
}

Position Minimap::getTilePosition(const Point& point, const Rect& screenRect, const Position& mapCenter, float scale, const Point& cameraOffset)
{
    if (screenRect.isEmpty())
        return {};

    const auto& mapRect = calcMapRect(screenRect, mapCenter, scale);
    const auto& off = Point((mapRect.size() * scale).toPoint() - screenRect.size().toPoint()) / 2;
    const float spriteSize = static_cast<float>(std::max<int>(g_gameConfig.getSpriteSize(), 1));
    const PointF cameraOffsetTiles(cameraOffset.x / spriteSize, cameraOffset.y / spriteSize);
    const Point cameraOffsetPx(
        static_cast<int>(std::round(-cameraOffsetTiles.x * scale)),
        static_cast<int>(std::round(-cameraOffsetTiles.y * scale))
    );
    const auto& pos2d = (point - screenRect.topLeft() + off - cameraOffsetPx) / scale + mapRect.topLeft();
    return { pos2d.x, pos2d.y, mapCenter.z };
}

Rect Minimap::getTileRect(const Position& pos, const Rect& screenRect, const Position& mapCenter, float scale, const Point& cameraOffset)
{
    if (screenRect.isEmpty() || pos.z != mapCenter.z)
        return {};

    const int tileSize = g_gameConfig.getSpriteSize() * scale;

    Rect tileRect(0, 0, tileSize, tileSize);
    tileRect.moveCenter(getTilePoint(pos, screenRect, mapCenter, scale, cameraOffset));
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

bool Minimap::checkUpdatedTiles(const std::unique_lock<std::mutex>& minimapLock) {
    assert(minimapLock.owns_lock());
    assert(minimapLock.mutex() == &m_lock);

    uint16_t remainingBudget = MINIMAP_MAX_UPDATED_TILES_PER_CYCLE;
    uint16_t syncLoads = 0;

    const auto processFloor = [&](uint8_t z, uint16_t floorBudget, bool allowSyncLoad) -> uint16_t {
        if (floorBudget == 0 || z > g_gameConfig.getMapMaxZ())
            return 0;

        auto& tiles = updatedTiles[z];
        if (tiles.empty())
            return 0;

        uint16_t processed = 0;
        std::unordered_map<uint32_t, MinimapBlock_ptr> loadedBlocks;
        loadedBlocks.reserve(std::min<size_t>(tiles.size(), 96));

        for (auto itTile = tiles.begin(); itTile != tiles.end() && processed < floorBudget;) {
            const auto pos = itTile->first;
            const auto minimapTile = itTile->second;
            const uint32_t blockIndex = getBlockIndex(pos);

            auto itLoaded = loadedBlocks.find(blockIndex);
            if (itLoaded == loadedBlocks.end()) {
                if (!hasBlock(pos) && hasSavedBlock(pos.z, blockIndex)) {
                    if (!allowSyncLoad) {
                        load(pos.z, blockIndex, false);
                        ++itTile;
                        continue;
                    }

                    if (syncLoads >= MINIMAP_MAX_SYNC_LOADS_PER_CYCLE) {
                        ++itTile;
                        continue;
                    }

                    invalidateAsyncLoad(pos.z, blockIndex);
                    load(pos.z, blockIndex, true); // sync load only for current floor and strict budget
                    ++syncLoads;
                }

                itLoaded = loadedBlocks.emplace(blockIndex, getBlock(pos)).first;
            }

            const auto& offsetPos = getBlockOffset(Point(pos.x, pos.y));
            if (itLoaded->second->updateTile(pos.x - offsetPos.x, pos.y - offsetPos.y, minimapTile))
                itLoaded->second->justSaw();

            itTile = tiles.erase(itTile);
            ++processed;
        }

        return processed;
    };

    uint8_t playerFloor = g_gameConfig.getMapMaxZ() + 1;
    if (const auto& player = g_game.getLocalPlayer()) {
        const Position pos = player->getPosition();
        if (pos.isValid())
            playerFloor = pos.z;
    }

    if (playerFloor <= g_gameConfig.getMapMaxZ() && remainingBudget > 0) {
        const uint16_t playerBudget = std::min<uint16_t>(remainingBudget, MINIMAP_PRIORITY_FLOOR_UPDATES_PER_CYCLE);
        remainingBudget -= processFloor(playerFloor, playerBudget, true);
    }

    for (int z = 0; z <= g_gameConfig.getMapMaxZ() && remainingBudget > 0; ++z) {
        const auto floor = static_cast<uint8_t>(z);
        if (z == playerFloor)
            continue;

        const uint16_t floorBudget = std::min<uint16_t>(remainingBudget, MINIMAP_BACKGROUND_FLOOR_UPDATES_PER_CYCLE);
        remainingBudget -= processFloor(floor, floorBudget, false);
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
        std::scoped_lock lock(m_lock);

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

bool Minimap::writeMinimapBlockData(const uint8_t z, const uint32_t index, const std::array<MinimapTile, MMBLOCK_SIZE* MMBLOCK_SIZE>& tiles)
{
    static constexpr uint32_t blockSize = MMBLOCK_SIZE * MMBLOCK_SIZE * sizeof(MinimapTile);
    static constexpr uint32_t COMPRESS_LEVEL = 3;
    static const uint32_t maxCompressedSize = static_cast<uint32_t>(compressBound(blockSize));

    thread_local std::vector<uint8_t> compressBuffer;
    if (compressBuffer.size() < maxCompressedSize)
        compressBuffer.resize(maxCompressedSize);

    unsigned long len = static_cast<unsigned long>(compressBuffer.size());
    const int ret = compress2(compressBuffer.data(), &len, reinterpret_cast<const uint8_t*>(tiles.data()), blockSize, COMPRESS_LEVEL);
    if (ret != Z_OK)
        return false;
    if (len > std::numeric_limits<uint16_t>::max())
        return false;

    std::scoped_lock ioLock(g_minimapIOLock);
    const auto& fin = g_resources.createFile(getFileName(z, index));
    if (!fin)
        return false;

    fin->cache();

    const Position pos = getIndexPosition(index, z);
    fin->addU16(pos.x);
    fin->addU16(pos.y);
    fin->addU8(pos.z);
    fin->addU16(static_cast<uint16_t>(len));
    fin->write(compressBuffer.data(), len);

    // end marker for reader validation
    const Position invalidPos;
    fin->addU16(invalidPos.x);
    fin->addU16(invalidPos.y);
    fin->addU8(invalidPos.z);

    fin->flush();
    fin->close();
    return true;
}

static bool readMinimapBlockData(const uint8_t z, const uint32_t block, std::array<MinimapTile, MMBLOCK_SIZE* MMBLOCK_SIZE>& outTiles)
{
    static constexpr uint32_t blockSize = MMBLOCK_SIZE * MMBLOCK_SIZE * sizeof(MinimapTile);
    static constexpr uint32_t tilesPerBlock = MMBLOCK_SIZE * MMBLOCK_SIZE;
    static constexpr uint32_t legacyBasicBlockSize = tilesPerBlock * 3; // flags + color + speed
    static constexpr uint32_t legacyGroundTopBlockSize = tilesPerBlock * 7; // flags + color + speed + groundId + topId
    static const uint32_t maxCompressedSize = static_cast<uint32_t>(compressBound(blockSize));
    static constexpr uint32_t blocksPerAxis = 65536 / MMBLOCK_SIZE;
    thread_local std::vector<uint8_t> compressBuffer;
    thread_local std::vector<uint8_t> decompressBuffer;
    if (compressBuffer.size() < maxCompressedSize)
        compressBuffer.resize(maxCompressedSize);
    if (decompressBuffer.size() < blockSize)
        decompressBuffer.resize(blockSize);

    uint16_t compressedSize = 0;

    {
        std::scoped_lock ioLock(g_minimapIOLock);
        const auto& fin = g_resources.openFile(getFileName(z, block));
        if (!fin) {
            g_logger.warning("invalid minimap block {}:{} (open failed)", z, block);
            return false;
        }

        Position pos;
        pos.x = fin->getU16();
        pos.y = fin->getU16();
        pos.z = fin->getU8();
        if (!pos.isValid() || pos.z >= g_gameConfig.getMapMaxZ() + 1 || pos.z != z) {
            g_logger.warning("invalid minimap block {}:{} (invalid header position: {})", z, block, pos);
            return false;
        }

        const uint32_t fileBlockIndex = ((pos.y / MMBLOCK_SIZE) * blocksPerAxis) + (pos.x / MMBLOCK_SIZE);
        if (fileBlockIndex != block) {
            g_logger.warning("invalid minimap block {}:{} (header index mismatch: {})", z, block, fileBlockIndex);
            return false;
        }

        const uint16_t len = fin->getU16();
        if (len == 0 || len > maxCompressedSize) {
            g_logger.warning("invalid minimap block {}:{} (compressed size out of range: {})", z, block, len);
            return false;
        }

        fin->read(compressBuffer.data(), len);
        compressedSize = len;

        Position endPos;
        endPos.x = fin->getU16();
        endPos.y = fin->getU16();
        endPos.z = fin->getU8();
        if (endPos.isValid()) {
            g_logger.warning("invalid minimap block {}:{} (missing end marker)", z, block);
            return false;
        }

        fin->close();
    }

    if (compressedSize == 0) {
        g_logger.warning("invalid minimap block {}:{} (missing compressed payload)", z, block);
        return false;
    }

    // Current format (HD-capable MinimapTile)
    unsigned long destLen = blockSize;
    int ret = uncompress(decompressBuffer.data(), &destLen, compressBuffer.data(), static_cast<unsigned long>(compressedSize));
    if (ret == Z_OK && destLen == blockSize) {
        memcpy(reinterpret_cast<uint8_t*>(outTiles.data()), decompressBuffer.data(), blockSize);
        return true;
    }

#pragma pack(push, 1)
    struct LegacyBasicTile {
        uint8_t flags;
        uint8_t color;
        uint8_t speed;
    };

    struct LegacyGroundTopTile {
        uint8_t flags;
        uint8_t color;
        uint8_t speed;
        uint16_t groundId;
        uint16_t topId;
    };
#pragma pack(pop)

    const auto chooseLegacyLayout = [&](const uint8_t* rawData, size_t stride) -> std::array<uint8_t, 3> {
        static constexpr std::array<std::array<uint8_t, 3>, 6> candidates{ {
            { 0, 1, 2 }, // flags, color, speed
            { 0, 2, 1 }, // flags, speed, color
            { 1, 0, 2 }, // color, flags, speed
            { 1, 2, 0 }, // color, speed, flags
            { 2, 0, 1 }, // speed, flags, color
            { 2, 1, 0 }  // speed, color, flags
        } };

        constexpr uint8_t allowedFlagsMask = MinimapTileWasSeen | MinimapTileNotPathable | MinimapTileNotWalkable | MinimapTileEmpty;

        uint32_t bestScore = 0;
        std::array<uint8_t, 3> best = candidates[0];

        for (const auto& candidate : candidates) {
            uint32_t validFlags = 0;
            uint32_t plausibleSpeed = 0;

            for (size_t i = 0; i < outTiles.size(); ++i) {
                const auto* tilePtr = rawData + (i * stride);
                const uint8_t flags = tilePtr[candidate[0]];
                const uint8_t speed = tilePtr[candidate[2]];

                if ((flags & ~allowedFlagsMask) == 0)
                    ++validFlags;
                if (speed <= 40)
                    ++plausibleSpeed;
            }

            const uint32_t score = validFlags * 4 + plausibleSpeed;
            if (score > bestScore) {
                bestScore = score;
                best = candidate;
            }
        }

        return best;
    };

    // Legacy format: flags/color/speed + ground/top ids
    destLen = legacyGroundTopBlockSize;
    ret = uncompress(decompressBuffer.data(), &destLen, compressBuffer.data(), static_cast<unsigned long>(compressedSize));
    if (ret == Z_OK && destLen == legacyGroundTopBlockSize) {
        const auto layout = chooseLegacyLayout(decompressBuffer.data(), sizeof(LegacyGroundTopTile));
        const auto* legacyTiles = reinterpret_cast<const LegacyGroundTopTile*>(decompressBuffer.data());
        for (size_t i = 0; i < outTiles.size(); ++i) {
            MinimapTile tile{};
            const auto* rawTile = reinterpret_cast<const uint8_t*>(&legacyTiles[i]);
            tile.flags = rawTile[layout[0]];
            tile.color = rawTile[layout[1]];
            tile.speed = rawTile[layout[2]];
            if (tile.color != UINT8_MAX)
                tile.flags |= MinimapTileWasSeen;

            if (legacyTiles[i].groundId > 0)
                tile.items[0].id = legacyTiles[i].groundId;
            if (legacyTiles[i].topId > 0)
                tile.items[1].id = legacyTiles[i].topId;

            outTiles[i] = tile;
        }
        return true;
    }

    // Legacy format: flags/color/speed
    destLen = legacyBasicBlockSize;
    ret = uncompress(decompressBuffer.data(), &destLen, compressBuffer.data(), static_cast<unsigned long>(compressedSize));
    if (ret == Z_OK && destLen == legacyBasicBlockSize) {
        const auto layout = chooseLegacyLayout(decompressBuffer.data(), sizeof(LegacyBasicTile));
        const auto* legacyTiles = reinterpret_cast<const LegacyBasicTile*>(decompressBuffer.data());
        for (size_t i = 0; i < outTiles.size(); ++i) {
            MinimapTile tile{};
            const auto* rawTile = reinterpret_cast<const uint8_t*>(&legacyTiles[i]);
            tile.flags = rawTile[layout[0]];
            tile.color = rawTile[layout[1]];
            tile.speed = rawTile[layout[2]];
            if (tile.color != UINT8_MAX)
                tile.flags |= MinimapTileWasSeen;
            outTiles[i] = tile;
        }
        return true;
    }

    g_logger.warning("invalid minimap block {}:{} (decompress failed for known formats, last ret={}, size={})", z, block, ret, destLen);
    return false;
}

bool Minimap::importOtmm(const std::string& fileName, bool overwrite)
{
    try {
        static constexpr uint32_t blockSize = MMBLOCK_SIZE * MMBLOCK_SIZE * sizeof(MinimapTile);
        static const uint32_t maxCompressedSize = static_cast<uint32_t>(compressBound(blockSize));

        uint32_t imported = 0;
        uint32_t skipped = 0;
        {
            std::scoped_lock ioLock(g_minimapIOLock);

            const auto& fin = g_resources.openFile(fileName);
            if (!fin)
                throw stdext::exception("unable to open file");

            const uint32_t signature = fin->getU32();
            if (signature != OTMM_SIGNATURE)
                throw stdext::exception("invalid OTMM file");

            const uint16_t start = fin->getU16();
            const uint16_t version = fin->getU16();
            fin->getU32(); // flags

            switch (version) {
                case OTMM_VERSION:
                    fin->getString(); // description
                    break;
                default:
                    throw stdext::exception("OTMM version not supported");
            }

            fin->seek(start);
            g_resources.makeDir(MINIMAP_PATH);

            std::vector<uint8_t> compressedBlock;
            while (true) {
                Position pos;
                pos.x = fin->getU16();
                pos.y = fin->getU16();
                pos.z = fin->getU8();

                // end of file or file is corrupted
                if (!pos.isValid() || pos.z >= g_gameConfig.getMapMaxZ() + 1)
                    break;

                const uint16_t len = fin->getU16();
                if (len == 0 || len > maxCompressedSize) {
                    g_logger.warning(
                        "invalid OTMM block {}:{} (compressed size out of range: {}) while importing '{}'",
                        pos.z,
                        getBlockIndex(pos),
                        len,
                        fileName
                    );
                    break;
                }

                compressedBlock.resize(len);
                fin->read(compressedBlock.data(), len);

                const uint32_t blockIndex = getBlockIndex(pos);
                if (!overwrite && hasSavedBlock(pos.z, blockIndex)) {
                    ++skipped;
                    continue;
                }

                const auto& fout = g_resources.createFile(getFileName(pos.z, blockIndex));
                fout->cache();
                fout->addU16(pos.x);
                fout->addU16(pos.y);
                fout->addU8(pos.z);
                fout->addU16(len);
                fout->write(compressedBlock.data(), len);

                // end of file marker
                const Position invalidPos;
                fout->addU16(invalidPos.x);
                fout->addU16(invalidPos.y);
                fout->addU8(invalidPos.z);

                fout->flush();
                fout->close();

                markSavedBlock(pos.z, blockIndex);
                ++imported;
            }

            fin->close();
        }

        flushAllSavedBlocks(true);

        g_logger.info("minimap OTMM import completed: {} imported, {} skipped", imported, skipped);
        return true;
    } catch (const stdext::exception& e) {
        g_logger.error("failed to import OTMM minimap '{}': {}", fileName, e.what());
        return false;
    }
}

void Minimap::preloadAllBlocks(bool buildTextures, bool forceSync)
{
    waitAsyncSaves();
    flushAllSavedBlocks(true);

    std::vector<std::pair<uint8_t, uint32_t>> blocksToPreload;
    {
        std::scoped_lock savedLock(m_savedBlocksLock);
        size_t totalBlocks = 0;
        for (uint_fast8_t z = 0; z <= g_gameConfig.getMapMaxZ(); ++z)
            totalBlocks += m_blockSaved[z].size();

        blocksToPreload.reserve(totalBlocks);
        for (uint_fast8_t z = 0; z <= g_gameConfig.getMapMaxZ(); ++z) {
            for (const auto blockIndex : m_blockSaved[z])
                blocksToPreload.emplace_back(static_cast<uint8_t>(z), blockIndex);
        }
    }

    if (blocksToPreload.empty()) {
        g_logger.info("minimap preload completed: no saved blocks found");
        return;
    }

    const auto startedAt = std::chrono::steady_clock::now();
    uint32_t loadedBlocks = 0;
    uint32_t failedBlocks = 0;
    uint32_t texturedBlocks = 0;

    std::unique_lock<std::mutex> lock(m_lock);
    applyAsyncLoadedBlocks(lock);

    for (const auto& [z, blockIndex] : blocksToPreload) {
        const auto state = forceSync ? loadSync(z, blockIndex) : load(z, blockIndex, false);

        if (state != EnumCachedBlockLoad::LOADED) {
            ++failedBlocks;
            continue;
        }

        ++loadedBlocks;

        if (!buildTextures)
            continue;

        const auto pos = getIndexPosition(blockIndex, z);
        if (!hasBlock(pos))
            continue;

        const auto& block = getBlock(pos);
        block->mustUpdate();
        if (m_hdMode)
            block->updateHD(pos);
        else
            block->update();

        ++texturedBlocks;
    }

    if (!forceSync)
        applyAsyncLoadedBlocks(lock);

    const auto elapsedMs = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - startedAt).count();
    g_logger.info(
        "minimap preload completed: total={}, loaded={}, failed={}, textured={}, buildTextures={}, forceSync={}, elapsed={}ms",
        blocksToPreload.size(),
        loadedBlocks,
        failedBlocks,
        texturedBlocks,
        buildTextures,
        forceSync,
        elapsedMs
    );
}

void Minimap::queueAsyncLoad(uint8_t z, uint32_t blockIndex)
{
    const uint64_t key = getAsyncLoadKey(z, blockIndex);

    {
        std::scoped_lock asyncLock(m_asyncLoadLock);
        if (m_asyncQueuedBlocks.find(key) != m_asyncQueuedBlocks.end())
            return;

        const uint32_t generation = ++m_asyncLoadGeneration[key];
        m_asyncQueuedBlocks.emplace(key);
        m_asyncLoadQueue.push_back({ z, blockIndex, generation });
    }

    dispatchAsyncLoads();
}

void Minimap::invalidateAsyncLoad(uint8_t z, uint32_t blockIndex)
{
    const uint64_t key = getAsyncLoadKey(z, blockIndex);
    std::scoped_lock asyncLock(m_asyncLoadLock);

    if (const auto it = m_asyncLoadGeneration.find(key); it != m_asyncLoadGeneration.end())
        ++it->second;

    m_asyncQueuedBlocks.erase(key);

    m_asyncLoadQueue.erase(
        std::remove_if(m_asyncLoadQueue.begin(), m_asyncLoadQueue.end(), [key](const AsyncLoadRequest& req) {
            return getAsyncLoadKey(req.z, req.blockIndex) == key;
        }),
        m_asyncLoadQueue.end()
    );

    m_asyncLoadedBlocks.erase(
        std::remove_if(m_asyncLoadedBlocks.begin(), m_asyncLoadedBlocks.end(), [key](const AsyncLoadedBlock& block) {
            return getAsyncLoadKey(block.z, block.blockIndex) == key;
        }),
        m_asyncLoadedBlocks.end()
    );
}

void Minimap::dispatchAsyncLoads()
{
    std::vector<AsyncLoadRequest> jobs;
    jobs.reserve(MINIMAP_MAX_ASYNC_LOADS);

    {
        std::scoped_lock asyncLock(m_asyncLoadLock);
        while (m_asyncActiveLoads < MINIMAP_MAX_ASYNC_LOADS && !m_asyncLoadQueue.empty()) {
            jobs.emplace_back(m_asyncLoadQueue.front());
            m_asyncLoadQueue.pop_front();
            ++m_asyncActiveLoads;
        }
    }

    for (const auto& request : jobs) {
        g_asyncDispatcher.detach_task([this, request] {
            AsyncLoadedBlock loadedBlock;
            loadedBlock.z = request.z;
            loadedBlock.blockIndex = request.blockIndex;
            loadedBlock.generation = request.generation;

            try {
                loadedBlock.state = readMinimapBlockData(request.z, request.blockIndex, loadedBlock.tiles)
                    ? EnumCachedBlockLoad::LOADED
                    : EnumCachedBlockLoad::NOT_LOADED;
            } catch (const stdext::exception& e) {
                loadedBlock.state = EnumCachedBlockLoad::NOT_LOADED;
                g_logger.error("failed to load minimap({}): {}", getFileName(request.z, request.blockIndex), e.what());
            } catch (...) {
                loadedBlock.state = EnumCachedBlockLoad::NOT_LOADED;
                g_logger.error("failed to load minimap({}): unknown exception", getFileName(request.z, request.blockIndex));
            }

            {
                std::scoped_lock asyncLock(m_asyncLoadLock);
                m_asyncLoadedBlocks.emplace_back(std::move(loadedBlock));
                if (m_asyncActiveLoads > 0)
                    --m_asyncActiveLoads;
            }

            g_dispatcher.addEvent([this] {
                dispatchAsyncLoads();
            });
        });
    }
}

void Minimap::queueAsyncSave(uint8_t z, uint32_t blockIndex, const std::array<MinimapTile, MMBLOCK_SIZE* MMBLOCK_SIZE>& tiles)
{
    const uint64_t key = getAsyncLoadKey(z, blockIndex);
    bool shouldDispatch = false;

    {
        std::scoped_lock asyncSaveLock(m_asyncSaveLock);
        auto [it, inserted] = m_asyncSavePending.try_emplace(key, AsyncSaveRequest{ z, blockIndex, tiles });
        if (!inserted)
            it->second.tiles = tiles;

        const bool isInFlight = m_asyncSaveInFlight.find(key) != m_asyncSaveInFlight.end();
        if (isInFlight)
            return;

        const bool alreadyQueued = std::find(m_asyncSaveOrder.begin(), m_asyncSaveOrder.end(), key) != m_asyncSaveOrder.end();
        if (!alreadyQueued)
            m_asyncSaveOrder.push_back(key);

        shouldDispatch = true;
    }

    if (shouldDispatch)
        dispatchAsyncSaves();
}

void Minimap::dispatchAsyncSaves()
{
    std::vector<AsyncSaveRequest> jobs;
    jobs.reserve(MINIMAP_MAX_ASYNC_SAVES);

    {
        std::scoped_lock asyncSaveLock(m_asyncSaveLock);
        while (m_asyncActiveSaves < MINIMAP_MAX_ASYNC_SAVES && !m_asyncSaveOrder.empty()) {
            const uint64_t key = m_asyncSaveOrder.front();
            m_asyncSaveOrder.pop_front();

            const auto it = m_asyncSavePending.find(key);
            if (it == m_asyncSavePending.end())
                continue;

            jobs.emplace_back(std::move(it->second));
            m_asyncSavePending.erase(it);
            m_asyncSaveInFlight.emplace(key);
            ++m_asyncActiveSaves;
        }
    }

    for (const auto& request : jobs) {
        g_asyncDispatcher.detach_task([this, request] {
            bool saved = false;

            try {
                saved = writeMinimapBlockData(request.z, request.blockIndex, request.tiles);
            } catch (const stdext::exception& e) {
                g_logger.error("failed to save minimap({}): {}", getFileName(request.z, request.blockIndex), e.what());
            } catch (...) {
                g_logger.error("failed to save minimap({}): unknown exception", getFileName(request.z, request.blockIndex));
            }

            if (saved)
                markSavedBlock(request.z, request.blockIndex);

            const uint64_t key = getAsyncLoadKey(request.z, request.blockIndex);
            bool shouldNotify = false;
            {
                std::scoped_lock asyncSaveLock(m_asyncSaveLock);
                if (m_asyncActiveSaves > 0)
                    --m_asyncActiveSaves;
                m_asyncSaveInFlight.erase(key);

                if (m_asyncSavePending.find(key) != m_asyncSavePending.end()) {
                    const bool alreadyQueued = std::find(m_asyncSaveOrder.begin(), m_asyncSaveOrder.end(), key) != m_asyncSaveOrder.end();
                    if (!alreadyQueued)
                        m_asyncSaveOrder.push_back(key);
                }

                shouldNotify = m_asyncActiveSaves == 0 && m_asyncSaveOrder.empty() && m_asyncSavePending.empty();
            }

            if (shouldNotify)
                m_asyncSaveCv.notify_all();

            g_dispatcher.addEvent([this] {
                dispatchAsyncSaves();
            });
        });
    }
}

void Minimap::waitAsyncSaves()
{
    std::unique_lock<std::mutex> lock(m_asyncSaveLock);
    auto isIdle = [this] {
        return m_asyncActiveSaves == 0 && m_asyncSaveOrder.empty() && m_asyncSavePending.empty();
    };

    static constexpr auto STEP = std::chrono::milliseconds(500);
    static constexpr auto TIMEOUT = std::chrono::seconds(15);

    auto waited = std::chrono::milliseconds::zero();
    while (!isIdle()) {
        if (m_asyncSaveCv.wait_for(lock, STEP, isIdle))
            break;

        waited += STEP;

        if (waited < TIMEOUT)
            continue;

        g_logger.warning(
            "minimap async save wait timeout: active={}, queued={}, pending={}; forcing sync flush of pending jobs",
            m_asyncActiveSaves,
            m_asyncSaveOrder.size(),
            m_asyncSavePending.size()
        );

        if (m_asyncActiveSaves == 0) {
            std::vector<AsyncSaveRequest> fallbackJobs;
            fallbackJobs.reserve(m_asyncSavePending.size());

            while (!m_asyncSaveOrder.empty()) {
                const uint64_t key = m_asyncSaveOrder.front();
                m_asyncSaveOrder.pop_front();

                const auto it = m_asyncSavePending.find(key);
                if (it == m_asyncSavePending.end())
                    continue;

                fallbackJobs.emplace_back(std::move(it->second));
                m_asyncSavePending.erase(it);
            }

            for (auto& [key, request] : m_asyncSavePending)
                fallbackJobs.emplace_back(std::move(request));
            m_asyncSavePending.clear();

            lock.unlock();
            for (const auto& request : fallbackJobs) {
                bool saved = false;
                try {
                    saved = writeMinimapBlockData(request.z, request.blockIndex, request.tiles);
                } catch (const stdext::exception& e) {
                    g_logger.error("failed to save minimap({}): {}", getFileName(request.z, request.blockIndex), e.what());
                } catch (...) {
                    g_logger.error("failed to save minimap({}): unknown exception", getFileName(request.z, request.blockIndex));
                }

                if (saved)
                    markSavedBlock(request.z, request.blockIndex);
            }
            lock.lock();
        }

        if (!isIdle()) {
            g_logger.warning(
                "minimap async save wait aborted to avoid freeze: active={}, queued={}, pending={}",
                m_asyncActiveSaves,
                m_asyncSaveOrder.size(),
                m_asyncSavePending.size()
            );
        }
        break;
    }
}

void Minimap::applyAsyncLoadedBlocks(const std::unique_lock<std::mutex>& minimapLock)
{
    assert(minimapLock.owns_lock());
    assert(minimapLock.mutex() == &m_lock);

    std::deque<AsyncLoadedBlock> loadedBlocks;

    {
        std::scoped_lock asyncLock(m_asyncLoadLock);
        if (m_asyncLoadedBlocks.empty())
            return;

        loadedBlocks.swap(m_asyncLoadedBlocks);
    }

    for (const auto& loadedBlock : loadedBlocks) {
        const uint64_t key = getAsyncLoadKey(loadedBlock.z, loadedBlock.blockIndex);
        bool isExpectedGeneration = false;

        {
            std::scoped_lock asyncLock(m_asyncLoadLock);
            m_asyncQueuedBlocks.erase(key);

            const auto it = m_asyncLoadGeneration.find(key);
            if (it != m_asyncLoadGeneration.end() && it->second == loadedBlock.generation) {
                isExpectedGeneration = true;
                m_asyncLoadGeneration.erase(it);
            }
        }

        if (!isExpectedGeneration)
            continue;

        auto& cachedBlock = getCachedBlock(loadedBlock.z, loadedBlock.blockIndex);
        if (cachedBlock.loaded != EnumCachedBlockLoad::LOADING)
            continue;

        if (loadedBlock.state != EnumCachedBlockLoad::LOADED) {
            cachedBlock.loaded = EnumCachedBlockLoad::NOT_LOADED;
            continue;
        }

        auto& floorBlocks = m_tileBlocks[loadedBlock.z];
        auto itBlock = floorBlocks.find(loadedBlock.blockIndex);
        if (itBlock != floorBlocks.end() && itBlock->second && itBlock->second->wasSeen()) {
            cachedBlock.loaded = EnumCachedBlockLoad::LOADED;
            cachedBlock.m_lastUpdate.restart();
            continue;
        }

        const auto pos = getIndexPosition(loadedBlock.blockIndex, loadedBlock.z);
        const auto& block = (itBlock != floorBlocks.end() && itBlock->second) ? itBlock->second : getBlock(pos);
        memcpy(reinterpret_cast<uint8_t*>(&block->getTiles()), reinterpret_cast<const uint8_t*>(loadedBlock.tiles.data()), sizeof(loadedBlock.tiles));
        if (!cachedBlock.texture)
            block->mustUpdate();
        block->touch();

        cachedBlock.loaded = EnumCachedBlockLoad::LOADED;
        cachedBlock.m_lastUpdate.restart();
    }
}

EnumCachedBlockLoad Minimap::loadSync(const uint8_t z, const uint32_t block)
{
    static Timer m_timerLoader;

    auto& cachedBlock = getCachedBlock(z, block);

    try {
        std::array<MinimapTile, MMBLOCK_SIZE* MMBLOCK_SIZE> tiles;
        if (!readMinimapBlockData(z, block, tiles)) {
            cachedBlock.loaded = EnumCachedBlockLoad::NOT_LOADED;
            return cachedBlock.loaded;
        }

        const auto pos = getIndexPosition(block, z);
        const auto& loadedBlock = getBlock(pos);
        memcpy(reinterpret_cast<uint8_t*>(&loadedBlock->getTiles()), reinterpret_cast<const uint8_t*>(tiles.data()), sizeof(tiles));
        if (!cachedBlock.texture)
            loadedBlock->mustUpdate();

        cachedBlock.loaded = EnumCachedBlockLoad::LOADED;
        m_timerLoader.restart();
    } catch (const stdext::exception& e) {
        cachedBlock.loaded = EnumCachedBlockLoad::NOT_LOADED;
        g_logger.error("failed to load minimap({}): {}", getFileName(z, block), e.what());
    }

    return cachedBlock.loaded;
}

EnumCachedBlockLoad Minimap::load(const uint8_t z, const uint32_t block, bool forceLoad) {
    if (!hasSavedBlock(z, block))
        return EnumCachedBlockLoad::FILE_NOT_FOUND;

    auto& cachedBlock = getCachedBlock(z, block);

    if (cachedBlock.loaded == EnumCachedBlockLoad::LOADED)
        return cachedBlock.loaded;

    if (cachedBlock.loaded == EnumCachedBlockLoad::UNLOADED && !forceLoad && cachedBlock.texture)
        return EnumCachedBlockLoad::UNLOADED;

    if (forceLoad)
        return loadSync(z, block);

    if (cachedBlock.loaded == EnumCachedBlockLoad::LOADING)
        return cachedBlock.loaded;

    cachedBlock.loaded = EnumCachedBlockLoad::LOADING;
    cachedBlock.m_lastUpdate.restart();
    queueAsyncLoad(z, block);
    return cachedBlock.loaded;
}

bool Minimap::saveBlock(const uint8_t z, const uint32_t index, const std::array<MinimapTile, MMBLOCK_SIZE* MMBLOCK_SIZE>& tiles) {
    queueAsyncSave(z, index, tiles);
    return true;
}

void Minimap::doSave(const bool waitForSaves)
{
    {
        std::unique_lock<std::mutex> lock(m_lock);
        applyAsyncLoadedBlocks(lock);

        // Ensure queued tile updates are materialized into blocks before writing .mmz files.
        for (uint16_t guard = 0; guard < 2048; ++guard) {
            size_t pendingBefore = 0;
            for (uint_fast8_t z = 0; z <= g_gameConfig.getMapMaxZ(); ++z)
                pendingBefore += updatedTiles[z].size();

            if (pendingBefore == 0)
                break;

            checkUpdatedTiles(lock);

            size_t pendingAfter = 0;
            for (uint_fast8_t z = 0; z <= g_gameConfig.getMapMaxZ(); ++z)
                pendingAfter += updatedTiles[z].size();

            if (pendingAfter == pendingBefore)
                break;
        }

        for (uint_fast8_t z = 0; z <= g_gameConfig.getMapMaxZ(); ++z) {
            for (const auto& [index, block] : m_tileBlocks[z]) {
                if (block && block->wasSeen())
                    saveBlock(z, index, block->getTiles());
            }
        }
    }

    if (waitForSaves)
        waitAsyncSaves();

    flushAllSavedBlocks(waitForSaves);
}

void Minimap::save()
{
    doSave(true);
}

void Minimap::saveAsync()
{
    doSave(false);
}

void Minimap::setHDMode(bool v) {
    if (m_hdMode == v)
        return;

    save();
    clean();

    m_hdMode = v;
}

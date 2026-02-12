/*
 * Copyright (c) 2010-2026 OTClient <https://github.com/edubart/otclient>
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

#include "gameconfig.h"
#include "map.h"
#include "tile.h"
#include "item.h"
#include "thingtypemanager.h"
#include "framework/core/filestream.h"
#include "framework/core/resourcemanager.h"
#include "framework/graphics/drawpoolmanager.h"
#include "framework/graphics/image.h"
#include "framework/graphics/texture.h"
#include <algorithm>
#include <unordered_map>

Minimap g_minimap;
static MinimapTile nulltile;

namespace {
    constexpr uint32_t MINIMAP_TRIM_INTERVAL_FRAMES = 120;
    constexpr uint32_t MINIMAP_TRIM_GRACE_FRAMES = 4;

    ItemPtr findMinimapTopItem(const TilePtr& tile)
    {
        const auto& things = tile->getThings();
        for (auto it = things.rbegin(); it != things.rend(); ++it) {
            const auto& thing = *it;
            if (!thing || !thing->isItem())
                continue;

            const auto& item = thing->static_self_cast<Item>();
            if (item->isGround())
                continue;

            return item;
        }

        return nullptr;
    }

    bool hasMinimapTileContent(const MinimapTile& tile)
    {
        return tile.groundId != 0 || tile.topId != 0 || tile.color != UINT8_MAX;
    }

    void drawMinimapTileItems(const TilePtr& tile, const Point& drawPos)
    {
        if (!tile)
            return;

        const auto& things = tile->getThings();

        for (const auto& thing : things) {
            if (!thing || !thing->isItem())
                continue;

            if (!thing->isGround() && !thing->isGroundBorder() && !thing->isOnBottom())
                continue;

            thing->draw(drawPos, true);
        }

        if (tile->hasCommonItem()) {
            for (auto it = things.rbegin(); it != things.rend(); ++it) {
                const auto& thing = *it;
                if (!thing || !thing->isItem() || !thing->isCommon())
                    continue;

                thing->draw(drawPos, true);
            }
        }

        if (tile->hasTopItem()) {
            for (const auto& thing : things) {
                if (!thing || !thing->isItem() || !thing->isOnTop())
                    continue;

                thing->draw(drawPos, true);
            }
        }
    }

    bool drawMinimapTileFromData(const MinimapTile& tile, const Point& drawPos, const float opacity, const bool drawColor)
    {
        if (!hasMinimapTileContent(tile))
            return false;

        const float prevOpacity = g_drawPool.getOpacity();
        if (opacity < 1.f)
            g_drawPool.setOpacity(opacity);

        bool drawn = false;
        if (tile.groundId != 0) {
            const ThingTypePtr& thing = g_things.getThingType(tile.groundId, ThingCategoryItem);
            if (thing) {
                thing->draw(drawPos, 0, 0, 0, 0, 0, Color::white);
                drawn = true;
            }
        }

        if (tile.topId != 0) {
            const ThingTypePtr& thing = g_things.getThingType(tile.topId, ThingCategoryItem);
            if (thing) {
                thing->draw(drawPos, 0, 0, 0, 0, 0, Color::white);
                drawn = true;
            }
        }

        if (!drawn && drawColor && tile.color != UINT8_MAX) {
            Color col = Color::from8bit(tile.color);
            if (opacity < 1.f)
                col = Color(col, opacity);

            const int spriteSize = g_gameConfig.getSpriteSize();
            g_drawPool.addFilledRect(Rect(drawPos, Size{ spriteSize }), col);
            drawn = true;
        }

        if (opacity < 1.f)
            g_drawPool.setOpacity(prevOpacity);

        return drawn;
    }
}

void MinimapBlock::clean()
{
    SpinLock::Guard lock(m_blockLock);
    m_tiles.fill({});
    m_texture.reset();
    m_image.reset();
    m_stagingImage.reset();
    m_mustUpdate = false;
    m_pendingUpload = false;
    m_isBuilding = false;
    m_imageShouldDraw = false;
    ++m_revision;
    m_imageRevision = m_revision;
}

void MinimapBlock::update()
{
    std::array<MinimapTile, MMBLOCK_SIZE* MMBLOCK_SIZE> tilesSnapshot;
    ImagePtr stagingImage;
    uint32_t snapshotRevision = 0;
    {
        SpinLock::Guard lock(m_blockLock);
        if (!m_mustUpdate || m_isBuilding)
            return;

        m_isBuilding = true;
        tilesSnapshot = m_tiles;
        snapshotRevision = m_revision;
        m_mustUpdate = false;
        if (!m_stagingImage)
            m_stagingImage = std::make_shared<Image>(m_size);
        stagingImage = m_stagingImage;
    }

    bool shouldDraw = false;
    for (uint_fast8_t x = 0; x < MMBLOCK_SIZE; ++x) {
        for (uint_fast8_t y = 0; y < MMBLOCK_SIZE; ++y) {
            const uint8_t c = tilesSnapshot[getTileIndex(x, y)].color;

            Color col = Color::black;
            if (c != UINT8_MAX) {
                col = Color::from8bit(c);
                shouldDraw = true;
            }

            stagingImage->setPixel(x, y, col);
        }
    }

    // Stage CPU image only. Texture upload is deferred to uploadTexture() on render thread.
    {
        SpinLock::Guard lock(m_blockLock);
        m_image.swap(m_stagingImage);
        m_imageShouldDraw = shouldDraw;
        m_imageRevision = snapshotRevision;
        m_pendingUpload = true;
        m_isBuilding = false;
        if (m_imageRevision != m_revision)
            m_mustUpdate = true;
    }
}

void MinimapBlock::uploadTexture()
{
    ImagePtr image;
    TexturePtr texture;
    bool shouldDraw = false;
    uint32_t imageRevision = 0;
    bool staleBeforeUpload = false;
    {
        SpinLock::Guard lock(m_blockLock);
        if (!m_pendingUpload)
            return;

        image = m_image;
        texture = m_texture;
        shouldDraw = m_imageShouldDraw;
        imageRevision = m_imageRevision;
        staleBeforeUpload = (imageRevision != m_revision);
        m_pendingUpload = false;
    }

    if (staleBeforeUpload) {
        SpinLock::Guard lock(m_blockLock);
        m_mustUpdate = true;
        return;
    }

    if (!shouldDraw) {
        texture.reset();
    } else if (!texture) {
        texture = std::make_shared<Texture>(image, true, false);
    } else if (texture->isEmpty()) {
        texture->updateImage(image);
    } else {
        texture->uploadPixels(image, true, false);
    }

    {
        SpinLock::Guard lock(m_blockLock);
        if (imageRevision != m_revision) {
            m_mustUpdate = true;
            return;
        }
        m_texture = std::move(texture);
    }
}

void MinimapBlock::updateTile(const int x, const int y, const MinimapTile& tile)
{
    SpinLock::Guard lock(m_blockLock);
    const auto idx = getTileIndex(x, y);
    if (m_tiles[idx] != tile) {
        m_mustUpdate = true;
        ++m_revision;
    }

    m_tiles[idx] = tile;
}

void Minimap::init() {
    m_tileBlocks.resize(g_gameConfig.getMapMaxZ() + 1);
}

void Minimap::terminate() { clean(); }

void Minimap::clean()
{
    SpinLock::Guard lock(m_lock);
    for (uint_fast8_t i = 0; i <= g_gameConfig.getMapMaxZ(); ++i)
        m_tileBlocks[i].clear();
    m_frameBlockCache.clear();
    m_frameCounter = 0;
}

void Minimap::trimBlocksMemory()
{
    if (m_maxBlocksInMemory == 0)
        return;

    struct CandidateBlock {
        uint8_t z;
        uint32_t index;
        uint32_t lastUseFrame;
    };

    size_t totalBlocks = 0;
    std::vector<CandidateBlock> candidates;
    {
        SpinLock::Guard lock(m_lock);
        for (uint_fast8_t z = 0; z <= g_gameConfig.getMapMaxZ(); ++z) {
            const auto& blocks = m_tileBlocks[z];
            totalBlocks += blocks.size();
            for (const auto& [index, block] : blocks) {
                if (!block)
                    continue;
                candidates.push_back({
                    static_cast<uint8_t>(z),
                    index,
                    block->getLastUseFrame()
                    });
            }
        }
    }

    if (totalBlocks <= m_maxBlocksInMemory || candidates.empty())
        return;

    std::sort(candidates.begin(), candidates.end(), [](const CandidateBlock& a, const CandidateBlock& b) {
        return a.lastUseFrame < b.lastUseFrame;
        });

    size_t toErase = totalBlocks - m_maxBlocksInMemory;
    const uint32_t protectedFrame = m_frameCounter > MINIMAP_TRIM_GRACE_FRAMES ? m_frameCounter - MINIMAP_TRIM_GRACE_FRAMES : 0;
    {
        SpinLock::Guard lock(m_lock);
        for (const auto& candidate : candidates) {
            if (toErase == 0)
                break;

            auto& blocks = m_tileBlocks[candidate.z];
            const auto it = blocks.find(candidate.index);
            if (it == blocks.end())
                continue;

            if (it->second && it->second->getLastUseFrame() > protectedFrame)
                continue;

            blocks.erase(it);
            --toErase;
        }
    }

    m_frameBlockCache.clear();
}

void Minimap::draw(const Rect& screenRect, const Position& mapCenter, const float scale, const Color& color)
{
    if (screenRect.isEmpty())
        return;

    const auto& oldClipRect = g_drawPool.getClipRect();
    g_drawPool.setClipRect(screenRect);

    g_drawPool.addFilledRect(screenRect, color);

    if (mapCenter.isMapPosition()) {
        ++m_frameCounter;
        const int spriteSize = g_gameConfig.getSpriteSize();
        const float spriteScale = scale / spriteSize;
        const auto mapRect = calcMapRect(screenRect, mapCenter, scale);
        const bool showAllFloors = m_showAllFloors && scale > 1.0f;
        const bool hdEnabled = m_hdEnabled;
        const bool needsTileDraw = hdEnabled || showAllFloors;
        const int maxZ = g_gameConfig.getMapMaxZ();
        const int seaFloor = g_gameConfig.getMapSeaFloor();
        const int surfaceFloor = std::clamp(seaFloor + m_surfaceFloorOffset, 0, maxZ);
        int maxVisibleZ = maxZ;
        if (showAllFloors) {
            if (mapCenter.z < surfaceFloor) {
                // Above surface: only allow one floor below, never deeper than surface floor.
                maxVisibleZ = std::min<int>(mapCenter.z + 1, surfaceFloor);
            } else if (mapCenter.z == surfaceFloor) {
                maxVisibleZ = std::min<int>(surfaceFloor + g_gameConfig.getMapAwareUndergroundFloorRange(), maxZ);
            } else {
                maxVisibleZ = std::min<int>(mapCenter.z + g_gameConfig.getMapAwareUndergroundFloorRange(), maxZ);
            }
        }

        const int startX = std::max<int>(0, mapRect.left());
        const int startY = std::max<int>(0, mapRect.top());
        const int endX = std::min<int>(65535, mapRect.right());
        const int endY = std::min<int>(65535, mapRect.bottom());

        const int startBlockX = startX / MMBLOCK_SIZE;
        const int startBlockY = startY / MMBLOCK_SIZE;
        const int endBlockX = endX / MMBLOCK_SIZE;
        const int endBlockY = endY / MMBLOCK_SIZE;

        const float screenCenterX = screenRect.center().x;
        const float screenCenterY = screenRect.center().y;
        constexpr int MAX_TRACKED_LOWER_FLOORS = 16;

        struct VisibleBlock {
            MinimapBlock_ptr block;
            std::array<MinimapBlock_ptr, MAX_TRACKED_LOWER_FLOORS> lowerBlocks{};
            uint8_t lowerCount{ 0 };
            int worldX;
            int worldY;
        };

        std::vector<VisibleBlock> visibleBlocks;
        if (needsTileDraw) {
            const int blockCountX = std::max(0, endBlockX - startBlockX + 1);
            const int blockCountY = std::max(0, endBlockY - startBlockY + 1);
            visibleBlocks.reserve(blockCountX * blockCountY);
        }

        m_frameBlockCache.clear();
        if (needsTileDraw) {
            const int blockCountX = std::max(0, endBlockX - startBlockX + 1);
            const int blockCountY = std::max(0, endBlockY - startBlockY + 1);
            const int lowerCount = (showAllFloors && mapCenter.z < maxVisibleZ)
                ? std::min<int>(maxVisibleZ - mapCenter.z, MAX_TRACKED_LOWER_FLOORS)
                : 0;
            const size_t expectedCacheEntries = static_cast<size_t>(blockCountX * blockCountY * (lowerCount + 1));
            if (m_frameBlockCache.bucket_count() < expectedCacheEntries)
                m_frameBlockCache.reserve(expectedCacheEntries);
        }

        const auto getCachedBlock = [&](const int z, const uint32_t index) -> MinimapBlock_ptr {
            const uint64_t cacheKey = (static_cast<uint64_t>(z) << 32u) | index;
            const auto itCached = m_frameBlockCache.find(cacheKey);
            if (itCached != m_frameBlockCache.end())
                return itCached->second;

            MinimapBlock_ptr result;
            {
                SpinLock::Guard lock(m_lock);
                const auto& blocks = m_tileBlocks[z];
                const auto it = blocks.find(index);
                if (it != blocks.end())
                    result = it->second;
            }

            m_frameBlockCache.emplace(cacheKey, result);
            return result;
        };

        for (int by = startBlockY; by <= endBlockY; ++by) {
            for (int bx = startBlockX; bx <= endBlockX; ++bx) {
                const int blockWorldX = bx * MMBLOCK_SIZE;
                const int blockWorldY = by * MMBLOCK_SIZE;
                const Position blockPos(blockWorldX, blockWorldY, mapCenter.z);
                const uint32_t blockIndex = getBlockIndex(blockPos);

                MinimapBlock_ptr block = getCachedBlock(mapCenter.z, blockIndex);
                VisibleBlock visibleBlock;
                visibleBlock.block = block;
                visibleBlock.worldX = blockWorldX;
                visibleBlock.worldY = blockWorldY;

                bool hasLower = false;
                if (showAllFloors && mapCenter.z < maxVisibleZ) {
                    const int lowerCount = std::min<int>(maxVisibleZ - mapCenter.z, MAX_TRACKED_LOWER_FLOORS);
                    visibleBlock.lowerCount = static_cast<uint8_t>(lowerCount);
                    for (int i = 0; i < lowerCount; ++i) {
                        const auto lowerBlock = getCachedBlock(mapCenter.z + 1 + i, blockIndex);
                        visibleBlock.lowerBlocks[i] = lowerBlock;
                        if (lowerBlock) {
                            lowerBlock->touch(m_frameCounter);
                            hasLower = true;
                        }
                    }
                }

                if (!block && showAllFloors) {
                    if (!hasLower)
                        continue;
                } else if (!block) {
                    continue;
                }

                if (block) {
                    block->touch(m_frameCounter);
                    block->update();
                    block->uploadTexture();
                    if (const auto texture = block->getTextureCopy()) {
                        const float screenX = screenCenterX + (blockWorldX - mapCenter.x) * scale - scale / 2.0f;
                        const float screenY = screenCenterY + (blockWorldY - mapCenter.y) * scale - scale / 2.0f;
                        const int width = static_cast<int>(std::ceil(MMBLOCK_SIZE * scale));
                        const int height = static_cast<int>(std::ceil(MMBLOCK_SIZE * scale));
                        g_drawPool.addTexturedRect(Rect(Point(static_cast<int>(screenX), static_cast<int>(screenY)), Size{ width, height }), texture);
                    }
                }

                if (needsTileDraw)
                    visibleBlocks.push_back(visibleBlock);
            }
        }

        if (!needsTileDraw) {
            g_drawPool.setClipRect(oldClipRect);
            return;
        }

        g_drawPool.pushTransformMatrix();
        g_drawPool.scale(spriteScale);

        // Center of map in World Pixels (including half-tile offset for centering)
        const float mapCenterPixelX = mapCenter.x * spriteSize + spriteSize / 2.0f;
        const float mapCenterPixelY = mapCenter.y * spriteSize + spriteSize / 2.0f;

        for (const auto& vis : visibleBlocks) {
            const int tileStartX = std::max<int>(startX, vis.worldX);
            const int tileEndX = std::min<int>(endX, vis.worldX + MMBLOCK_SIZE - 1);
            const int tileStartY = std::max<int>(startY, vis.worldY);
            const int tileEndY = std::min<int>(endY, vis.worldY + MMBLOCK_SIZE - 1);
            std::array<MinimapTile, MMBLOCK_SIZE* MMBLOCK_SIZE> tilesSnapshot;
            const bool hasSnapshot = static_cast<bool>(vis.block);
            if (hasSnapshot)
                vis.block->copyTiles(tilesSnapshot);

            for (int y = tileStartY; y <= tileEndY; ++y) {
                for (int x = tileStartX; x <= tileEndX; ++x) {
                    const Position pos(x, y, mapCenter.z);
                    const int tileOffsetX = x - vis.worldX;
                    const int tileOffsetY = y - vis.worldY;
                    const MinimapTile mtile = hasSnapshot ? tilesSnapshot[tileOffsetY * MMBLOCK_SIZE + tileOffsetX] : nulltile;
                    const bool hasGroundFromData = mtile.groundId != 0;

                    // Calculate Screen Position manually
                    const float tileWorldX = x * spriteSize;
                    const float tileWorldY = y * spriteSize;
                    const float diffX = tileWorldX - mapCenterPixelX;
                    const float diffY = tileWorldY - mapCenterPixelY;
                    const float screenX = screenCenterX + diffX * spriteScale;
                    const float screenY = screenCenterY + diffY * spriteScale;

                    // Compensate for global scale to draw at correct position
                    const Point drawPos(static_cast<int>(screenX / spriteScale), static_cast<int>(screenY / spriteScale));

                    bool hasGround = hasGroundFromData;
                    const TilePtr tile = g_map.getTile(pos);
                    if (tile && tile->getGround())
                        hasGround = true;

                    if (showAllFloors && !hasGround) {
                        constexpr float baseAlpha = 0.6f;
                        constexpr float stepAlpha = 0.65f;
                        float alpha = baseAlpha;

                        for (int i = 0; i < vis.lowerCount; ++i) {
                            const auto& lowerBlock = vis.lowerBlocks[i];
                            if (!lowerBlock) {
                                alpha *= stepAlpha;
                                if (alpha <= 0.05f)
                                    break;
                                continue;
                            }

                            const MinimapTile lowerTile = lowerBlock->getTileCopy(tileOffsetX, tileOffsetY);
                            if (drawMinimapTileFromData(lowerTile, drawPos, alpha, true)) {
                                // keep blending deeper floors
                            }

                            alpha *= stepAlpha;
                            if (alpha <= 0.05f)
                                break;
                        }
                    }

                    if (hdEnabled) {
                        if (tile && tile->isDrawable()) {
                            if (!tile->getGround() && !showAllFloors) {
                                g_drawPool.addFilledRect(Rect(drawPos, Size{ spriteSize }), Color::black);
                            }
                            drawMinimapTileItems(tile, drawPos);
                            continue;
                        }

                        if (!drawMinimapTileFromData(mtile, drawPos, 1.f, false))
                            continue;
                    }
                }
            }
        }

        g_drawPool.popTransformMatrix();

        if (m_maxBlocksInMemory > 0 && (m_frameCounter % MINIMAP_TRIM_INTERVAL_FRAMES) == 0)
            trimBlocksMemory();
    }

    g_drawPool.setClipRect(oldClipRect);
}

Point Minimap::getTilePoint(const Position& pos, const Rect& screenRect, const Position& mapCenter, const float scale)
{
    if (screenRect.isEmpty() || pos.z != mapCenter.z)
        return { -1 };

    const auto& mapRect = calcMapRect(screenRect, mapCenter, scale);
    const auto& off = Point((mapRect.size() * scale).toPoint() - screenRect.size().toPoint()) / 2;
    const auto& posoff = (Point(pos.x, pos.y) - mapRect.topLeft()) * scale;
    return posoff + screenRect.topLeft() - off + (Point(1) * scale) / 2;
}

Position Minimap::getTilePosition(const Point& point, const Rect& screenRect, const Position& mapCenter, const float scale)
{
    if (screenRect.isEmpty())
        return {};

    const auto& mapRect = calcMapRect(screenRect, mapCenter, scale);
    const auto& off = Point((mapRect.size() * scale).toPoint() - screenRect.size().toPoint()) / 2;
    const auto& pos2d = (point - screenRect.topLeft() + off) / scale + mapRect.topLeft();
    return { pos2d.x, pos2d.y, mapCenter.z };
}

Rect Minimap::getTileRect(const Position& pos, const Rect& screenRect, const Position& mapCenter, const float scale)
{
    if (screenRect.isEmpty() || pos.z != mapCenter.z)
        return {};

    const int tileSize = g_gameConfig.getSpriteSize() * scale;

    Rect tileRect(0, 0, tileSize, tileSize);
    tileRect.moveCenter(getTilePoint(pos, screenRect, mapCenter, scale));
    return tileRect;
}

Rect Minimap::calcMapRect(const Rect& screenRect, const Position& mapCenter, const float scale) const
{
    const int w = screenRect.width() / scale;
    const int h = std::ceil(screenRect.height() / scale);

    Rect mapRect(0, 0, w, h);
    mapRect.moveCenter(Point(mapCenter.x, mapCenter.y));
    return mapRect;
}

void Minimap::updateTile(const Position& pos, const TilePtr& tile)
{
    MinimapTile minimapTile;
    if (tile) {
        minimapTile.color = tile->getMinimapColorByte();
        minimapTile.flags |= MinimapTileWasSeen;
        if (!tile->isWalkable(true))
            minimapTile.flags |= MinimapTileNotWalkable;
        if (!tile->isPathable())
            minimapTile.flags |= MinimapTileNotPathable;
        minimapTile.speed = std::min<int>(static_cast<int>(std::ceil(tile->getGroundSpeed() / 10.f)), UINT8_MAX);

        if (const auto& ground = tile->getGround())
            minimapTile.groundId = ground->getId();

        if (const auto& topItem = findMinimapTopItem(tile))
            minimapTile.topId = topItem->getId();
    } else {
        minimapTile.flags |= MinimapTileNotWalkable | MinimapTileNotPathable;
    }

    if (minimapTile != nulltile) {
        MinimapBlock& block = getBlock(pos);
        const auto& offsetPos = getBlockOffset(Point(pos.x, pos.y));
        block.updateTile(pos.x - offsetPos.x, pos.y - offsetPos.y, minimapTile);
        block.justSaw();
        block.touch(m_frameCounter);
    }
}

MinimapTile Minimap::getTile(const Position& pos)
{
    if (pos.z <= g_gameConfig.getMapMaxZ()) {
        MinimapBlock_ptr block;
        {
            SpinLock::Guard lock(m_lock);
            const auto& blocks = m_tileBlocks[pos.z];
            const auto it = blocks.find(getBlockIndex(pos));
            if (it != blocks.end())
                block = it->second;
        }

        if (block) {
            const auto offsetPos = getBlockOffset(Point(pos.x, pos.y));
            return block->getTileCopy(pos.x - offsetPos.x, pos.y - offsetPos.y);
        }
    }
    return nulltile;
}

std::pair<MinimapBlock_ptr, MinimapTile> Minimap::threadGetTile(const Position& pos)
{
    if (pos.z <= g_gameConfig.getMapMaxZ()) {
        MinimapBlock_ptr block;
        {
            SpinLock::Guard lock(m_lock);
            const auto& blocks = m_tileBlocks[pos.z];
            const auto it = blocks.find(getBlockIndex(pos));
            if (it != blocks.end())
                block = it->second;
        }

        if (block) {
            const auto offsetPos = getBlockOffset(Point(pos.x, pos.y));
            return std::make_pair(block, block->getTileCopy(pos.x - offsetPos.x, pos.y - offsetPos.y));
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
                MinimapBlock& block = getBlock(pos);
                const auto& offsetPos = getBlockOffset(Point(pos.x, pos.y));
                const int tileX = pos.x - offsetPos.x;
                const int tileY = pos.y - offsetPos.y;
                MinimapTile tile = block.getTileCopy(tileX, tileY);
                if (!(tile.flags & MinimapTileWasSeen)) {
                    tile.color = c;
                    tile.flags = flags;
                    block.updateTile(tileX, tileY, tile);
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

bool Minimap::loadOtmm(const std::string& fileName)
{
    try {
        const FileStreamPtr fin = g_resources.openFile(fileName);
        if (!fin)
            throw Exception("unable to open file");

        fin->cache();

        const uint32_t signature = fin->getU32();
        if (signature != OTMM_SIGNATURE)
            throw Exception("invalid OTMM file");

        const uint16_t start = fin->getU16();
        const uint16_t version = fin->getU16();
        fin->getU32(); // flags

        switch (version) {
            case 1:
            case 2:
            case 3:
            {
                fin->getString(); // description
                break;
            }
            default:
                throw Exception("OTMM version not supported");
        }

        fin->seek(start);

        const uint32_t currentTileSize = sizeof(MinimapTile);
        // Versions <= 2 used 3 bytes (flags, color, speed)
        #pragma pack(push,1)
        struct MinimapTileV1 {
            uint8_t flags;
            uint8_t color;
            uint8_t speed;
        };
        #pragma pack(pop)
        const uint32_t tileSizeV1 = sizeof(MinimapTileV1);
        const uint32_t blockSizeV1 = MMBLOCK_SIZE * MMBLOCK_SIZE * tileSizeV1;
        const uint32_t blockSizeV3 = MMBLOCK_SIZE * MMBLOCK_SIZE * currentTileSize;
        const uint32_t maxBlockSize = std::max(blockSizeV1, blockSizeV3);

        std::vector<uint8_t> compressBuffer(compressBound(maxBlockSize));
        std::vector<uint8_t> decompressBuffer(maxBlockSize);

        while (true) {
            Position pos;
            pos.x = fin->getU16();
            pos.y = fin->getU16();
            pos.z = fin->getU8();

            // end of file or file is corrupted
            if (!pos.isValid() || pos.z >= g_gameConfig.getMapMaxZ() + 1)
                break;

            MinimapBlock& block = getBlock(pos);
            const uint16_t len = fin->getU16();
            fin->read(compressBuffer.data(), len);

            unsigned long destLen = maxBlockSize;
            const int ret = uncompress(decompressBuffer.data(), &destLen, compressBuffer.data(), len);

            if (ret != Z_OK)
                break;

            if (destLen == blockSizeV3) {
                block.loadTiles(decompressBuffer.data(), blockSizeV3);
            } else if (destLen == blockSizeV1 && version <= 2) {
                block.loadLegacyTiles(decompressBuffer.data(), blockSizeV1);
            } else {
                break;
            }
            
            block.justSaw();
        }

        fin->close();
        return true;
    } catch (const stdext::exception& e) {
        g_logger.error("failed to load OTMM minimap: {}", e.what());
        return false;
    }
}

void Minimap::saveOtmm(const std::string& fileName)
{
    try {
        const FileStreamPtr fin = g_resources.createFile(fileName);
        fin->cache();

        //TODO: compression flag with zlib
        constexpr uint32_t flags = 0;

        // header
        fin->addU32(OTMM_SIGNATURE);
        fin->addU16(0); // data start, will be overwritten later
        fin->addU16(OTMM_VERSION);
        fin->addU32(flags);

        // version 3 header
        fin->addString("OTMM 3.0 HD"); // description

        // go back and rewrite where the map data starts
        const uint32_t start = fin->tell();
        fin->seek(4);
        fin->addU16(start);
        fin->seek(start);

        constexpr uint32_t blockSize = MMBLOCK_SIZE * MMBLOCK_SIZE * sizeof(MinimapTile);
        constexpr uint32_t COMPRESS_LEVEL = 3;
        std::vector<uint8_t> compressBuffer(compressBound(blockSize));
        std::vector<uint8_t> tilesBuffer(blockSize);

        for (uint_fast8_t z = 0; z <= g_gameConfig.getMapMaxZ(); ++z) {
            for (const auto& [index, block] : m_tileBlocks[z]) {
                if (!block->wasSeen())
                    continue;

                const auto& pos = getIndexPosition(index, z);
                fin->addU16(pos.x);
                fin->addU16(pos.y);
                fin->addU8(pos.z);

                unsigned long len = blockSize;
                block->copyTiles(tilesBuffer.data(), tilesBuffer.size());
                compress2(compressBuffer.data(), &len, tilesBuffer.data(), blockSize, COMPRESS_LEVEL);
                fin->addU16(len);
                fin->write(compressBuffer.data(), len);
            }
        }

        // end of file
        constexpr Position invalidPos;
        fin->addU16(invalidPos.x);
        fin->addU16(invalidPos.y);
        fin->addU8(invalidPos.z);

        fin->flush();

        fin->close();
    } catch (const stdext::exception& e) {
        g_logger.error("failed to save OTMM minimap: {}", e.what());
    }
}

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

#pragma once

#include "declarations.h"
#include <framework/graphics/declarations.h>
#include <framework/util/spinlock.h>
#include <algorithm>
#include <array>
#include <cstring>
#include <unordered_map>
#include <vector>

constexpr uint8_t MMBLOCK_SIZE = 64;
constexpr uint8_t OTMM_VERSION = 3;
constexpr uint32_t OTMM_SIGNATURE = 0x4D4d544F;

enum MinimapTileFlags
{
    MinimapTileWasSeen = 1,
    MinimapTileNotPathable = 2,
    MinimapTileNotWalkable = 4,
    MinimapTileEmpty = 8
};

#pragma pack(push,1) // disable memory alignment
struct MinimapTile
{
    uint8_t flags{ 0 };
    uint8_t color{ 255 };
    uint8_t speed{ 10 };
    uint16_t groundId{ 0 };
    uint16_t topId{ 0 };
    bool hasFlag(const MinimapTileFlags flag) const { return flags & flag; }
    int getSpeed() const { return speed * 10; }
    bool operator==(const MinimapTile& other) const { return color == other.color && flags == other.flags && speed == other.speed && groundId == other.groundId && topId == other.topId; }
    bool operator!=(const MinimapTile& other) const { return !(*this == other); }
};

class MinimapBlock
{
public:
    void clean();
    void update();
    void uploadTexture();
    void updateTile(int x, int y, const MinimapTile& tile);
    MinimapTile getTileCopy(int x, int y) const
    {
        SpinLock::Guard lock(m_blockLock);
        return m_tiles[getTileIndex(x, y)];
    }
    void resetTile(const int x, const int y)
    {
        SpinLock::Guard lock(m_blockLock);
        m_tiles[getTileIndex(x, y)] = MinimapTile();
        m_mustUpdate = true;
        ++m_revision;
    }
    uint32_t getTileIndex(const int x, const int y) const { return ((y % MMBLOCK_SIZE) * MMBLOCK_SIZE) + (x % MMBLOCK_SIZE); }
    TexturePtr getTextureCopy() const
    {
        SpinLock::Guard lock(m_blockLock);
        return m_texture;
    }
    void copyTiles(uint8_t* out, const size_t len) const
    {
        SpinLock::Guard lock(m_blockLock);
        memcpy(out, m_tiles.data(), std::min(len, sizeof(m_tiles)));
    }
    void copyTiles(std::array<MinimapTile, MMBLOCK_SIZE* MMBLOCK_SIZE>& out) const
    {
        SpinLock::Guard lock(m_blockLock);
        out = m_tiles;
    }
    void loadTiles(const uint8_t* in, const size_t len)
    {
        SpinLock::Guard lock(m_blockLock);
        m_tiles.fill({});
        memcpy(m_tiles.data(), in, std::min(len, sizeof(m_tiles)));
        m_mustUpdate = true;
        ++m_revision;
    }
    void loadLegacyTiles(const uint8_t* in, const size_t len)
    {
        SpinLock::Guard lock(m_blockLock);
        m_tiles.fill({});
        const auto count = std::min<size_t>(m_tiles.size(), len / 3);
        for (size_t i = 0; i < count; ++i) {
            const size_t offset = i * 3;
            m_tiles[i].flags = in[offset];
            m_tiles[i].color = in[offset + 1];
            m_tiles[i].speed = in[offset + 2];
            m_tiles[i].groundId = 0;
            m_tiles[i].topId = 0;
        }
        m_mustUpdate = true;
        ++m_revision;
    }
    void mustUpdate()
    {
        SpinLock::Guard lock(m_blockLock);
        m_mustUpdate = true;
    }
    void justSaw()
    {
        SpinLock::Guard lock(m_blockLock);
        m_wasSeen = true;
    }
    bool wasSeen() const
    {
        SpinLock::Guard lock(m_blockLock);
        return m_wasSeen;
    }
    void touch(const uint32_t frame)
    {
        SpinLock::Guard lock(m_blockLock);
        m_lastUseFrame = frame;
    }
    uint32_t getLastUseFrame() const
    {
        SpinLock::Guard lock(m_blockLock);
        return m_lastUseFrame;
    }
private:
    mutable SpinLock m_blockLock;
    TexturePtr m_texture;
    ImagePtr m_image;
    ImagePtr m_stagingImage;

    Size m_size{ MMBLOCK_SIZE, MMBLOCK_SIZE };

    std::array<MinimapTile, MMBLOCK_SIZE* MMBLOCK_SIZE> m_tiles;

    bool m_mustUpdate{ true };
    bool m_pendingUpload{ false };
    bool m_isBuilding{ false };
    bool m_imageShouldDraw{ false };
    bool m_wasSeen{ false };
    uint32_t m_revision{ 0 };
    uint32_t m_imageRevision{ 0 };
    uint32_t m_lastUseFrame{ 0 };
};

#pragma pack(pop)

using MinimapBlock_ptr = std::shared_ptr<MinimapBlock>;

class Minimap
{
public:
    void init();
    void terminate();

    void clean();

    void draw(const Rect& screenRect, const Position& mapCenter, float scale, const Color& color);
    Point getTilePoint(const Position& pos, const Rect& screenRect, const Position& mapCenter, float scale);
    Position getTilePosition(const Point& point, const Rect& screenRect, const Position& mapCenter, float scale);
    Rect getTileRect(const Position& pos, const Rect& screenRect, const Position& mapCenter, float scale);

    void updateTile(const Position& pos, const TilePtr& tile);
    MinimapTile getTile(const Position& pos);
    std::pair<MinimapBlock_ptr, MinimapTile> threadGetTile(const Position& pos);

    bool loadImage(const std::string& fileName, const Position& topLeft, float colorFactor);
    void saveImage(const std::string& fileName, const Rect& mapRect);
    bool loadOtmm(const std::string& fileName);
    void saveOtmm(const std::string& fileName);
    void setShowAllFloors(bool value) { m_showAllFloors = value; }
    bool isShowAllFloors() const { return m_showAllFloors; }
    void setHdEnabled(bool value) { m_hdEnabled = value; }
    bool isHdEnabled() const { return m_hdEnabled; }
    void setSurfaceFloorOffset(int value) { m_surfaceFloorOffset = value; }
    int getSurfaceFloorOffset() const { return m_surfaceFloorOffset; }
    void setMaxBlocksInMemory(uint32_t value) { m_maxBlocksInMemory = value; }
    uint32_t getMaxBlocksInMemory() const { return m_maxBlocksInMemory; }

private:
    void trimBlocksMemory();
    Rect calcMapRect(const Rect& screenRect, const Position& mapCenter, float scale) const;
    bool hasBlock(const Position& pos) { return m_tileBlocks[pos.z].contains(getBlockIndex(pos)); }
    MinimapBlock& getBlock(const Position& pos)
    {
        SpinLock::Guard lock(m_lock);
        auto& ptr = m_tileBlocks[pos.z][getBlockIndex(pos)];
        if (!ptr)
            ptr = std::make_shared<MinimapBlock>();
        return *ptr;
    }
    Point getBlockOffset(const Point& pos)
    {
        return {
            pos.x - pos.x % MMBLOCK_SIZE,
                     pos.y - pos.y % MMBLOCK_SIZE
        };
    }
    Position getIndexPosition(const int index, const int z)
    {
        return {
            (index % (65536 / MMBLOCK_SIZE)) * MMBLOCK_SIZE,
            (index / (65536 / MMBLOCK_SIZE)) * MMBLOCK_SIZE,
            static_cast<uint8_t>(z)
        };
    }
    uint32_t getBlockIndex(const Position& pos) { return ((pos.y / MMBLOCK_SIZE) * (65536 / MMBLOCK_SIZE)) + (pos.x / MMBLOCK_SIZE); }
    std::vector<std::unordered_map<uint32_t, MinimapBlock_ptr>> m_tileBlocks;
    std::unordered_map<uint64_t, MinimapBlock_ptr> m_frameBlockCache;
    SpinLock m_lock;
    bool m_showAllFloors{ false };
    bool m_hdEnabled{ true };
    int m_surfaceFloorOffset{ 0 };
    uint32_t m_frameCounter{ 0 };
    uint32_t m_maxBlocksInMemory{ 0 };
};

extern Minimap g_minimap;

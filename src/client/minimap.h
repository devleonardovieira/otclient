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

#pragma once

#include <condition_variable>
#include <deque>
#include <unordered_set>

#include <framework/graphics/declarations.h>
#include "declarations.h"
#include "gameconfig.h"
#include <framework/core/timer.h>

constexpr uint8_t MMBLOCK_SIZE = 32;
constexpr uint8_t MMTILE_SIZE = 32;
constexpr uint16_t MMTEXTURE_SIZE = MMBLOCK_SIZE * MMTILE_SIZE;

constexpr uint8_t OTMM_VERSION = 1;
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
    struct ItemData
    {
        uint32_t id = 0;
        uint8_t xPattern = 0;
        uint8_t yPattern = 0;
        uint8_t zPattern = 0;
    };

    std::array<ItemData, 5> items;
    uint8_t flags{ 0 };
    uint8_t color{ 255 };
    uint8_t speed{ 10 };

    bool hasItems() const { return items[0].id > 0; }
    bool hasFlag(MinimapTileFlags flag) const { return flags & flag; }
    int getSpeed() const { return speed * 10; }
    bool operator==(const MinimapTile& other) const {
        return flags == other.flags && speed == other.speed && equalsItems(other);
    }
    bool operator!=(const MinimapTile& other) const { return !(*this == other); }

    bool equalsItems(const MinimapTile& other) const {
        if (hasItems() != other.hasItems())
            return false;

        for (int_fast8_t i = -1, s = items.size(); ++i < s;) {
            if (items[i].id != other.items[i].id ||
                items[i].xPattern != other.items[i].xPattern ||
                items[i].yPattern != other.items[i].yPattern ||
                items[i].zPattern != other.items[i].zPattern)
                return false;
        }

        return true;
    }
};

static_assert(sizeof(MinimapTile::ItemData) == 7, "Minimap item layout changed");
static_assert(sizeof(MinimapTile) == 38, "Minimap tile layout changed, this breaks .mmz compatibility");

class MinimapBlock : public std::enable_shared_from_this<MinimapBlock>
{
public:
    MinimapBlock();
    void clean();
    void updateHD(const Position& pos);
    void update();

    bool updateTile(int x, int y, const MinimapTile& tile);
    MinimapTile& getTile(int x, int y) { return m_tiles[getTileIndex(x, y)]; }
    void resetTile(int x, int y) { m_tiles[getTileIndex(x, y)] = MinimapTile(); }
    uint getTileIndex(int x, int y) { return ((y % MMBLOCK_SIZE) * MMBLOCK_SIZE) + (x % MMBLOCK_SIZE); }
    TexturePtr getTexture() const {
        return m_texture;
    }
    auto& getTiles() { return m_tiles; }
    void touch() { m_lastUpdate.restart(); }
    void mustUpdate() { m_mustUpdate = true; }
    void justSaw() { m_wasSeen = true; }
    bool wasSeen() const { return m_wasSeen; }
    auto lastUpdate() const { return m_lastUpdate.ticksElapsed(); }

private:
    TexturePtr m_texture;
    std::array<MinimapTile, MMBLOCK_SIZE* MMBLOCK_SIZE> m_tiles;

    bool m_mustUpdate{ false };
    bool m_wasSeen{ false };

    Timer m_lastUpdate;
};

enum class EnumCachedBlockLoad
{
    FILE_NOT_FOUND,
    NOT_LOADED,
    LOADING,
    LOADED,
    UNLOADED
};

struct CacheBlock
{
    TexturePtr texture;
    EnumCachedBlockLoad loaded = EnumCachedBlockLoad::UNLOADED;
    Timer m_lastUpdate;
    auto lastUpdate() const { return m_lastUpdate.ticksElapsed(); }

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
    const MinimapTile& getTile(const Position& pos);
    std::pair<MinimapBlock_ptr, MinimapTile> threadGetTile(const Position& pos);

    bool loadImage(const std::string& fileName, const Position& topLeft, float colorFactor);
    void saveImage(const std::string& fileName, const Rect& mapRect);
    bool importOtmm(const std::string& fileName, bool overwrite = false);

    EnumCachedBlockLoad load(const uint8_t z, const uint32_t  index, bool forceIfNotLoaded = false);
    void save();
    void preloadAllBlocks(bool buildTextures = false, bool forceSync = true);

    FrameBufferPtr getFrameBuffer() const {
        return m_fbo;
    }

    void setHDMode(bool v);
    bool isHDMode() {
        return m_hdMode;
    }

    void cacheBlockFileName();

private:
    struct AsyncLoadRequest
    {
        uint8_t z = 0;
        uint32_t blockIndex = 0;
        uint32_t generation = 0;
    };

    struct AsyncLoadedBlock
    {
        uint8_t z = 0;
        uint32_t blockIndex = 0;
        uint32_t generation = 0;
        EnumCachedBlockLoad state = EnumCachedBlockLoad::NOT_LOADED;
        std::array<MinimapTile, MMBLOCK_SIZE* MMBLOCK_SIZE> tiles;
    };

    struct AsyncSaveRequest
    {
        uint8_t z = 0;
        uint32_t blockIndex = 0;
        std::array<MinimapTile, MMBLOCK_SIZE* MMBLOCK_SIZE> tiles;
    };

    // Saves using an immutable tile snapshot captured by the caller while m_lock is held.
    bool saveBlock(const uint8_t z, const uint32_t index, const std::array<MinimapTile, MMBLOCK_SIZE* MMBLOCK_SIZE>& tiles);
    bool hasSavedBlock(uint8_t z, uint32_t blockIndex) const;
    void markSavedBlock(uint8_t z, uint32_t blockIndex);
    void flushSavedBlocks(uint8_t z, bool force = false);
    void flushAllSavedBlocks(bool force = false);
    void queueAsyncLoad(uint8_t z, uint32_t blockIndex);
    void invalidateAsyncLoad(uint8_t z, uint32_t blockIndex);
    void dispatchAsyncLoads();
    void queueAsyncSave(uint8_t z, uint32_t blockIndex, const std::array<MinimapTile, MMBLOCK_SIZE* MMBLOCK_SIZE>& tiles);
    void dispatchAsyncSaves();
    void waitAsyncSaves();
    static bool writeMinimapBlockData(uint8_t z, uint32_t index, const std::array<MinimapTile, MMBLOCK_SIZE* MMBLOCK_SIZE>& tiles);
    // Must be called with m_lock held (main thread).
    void applyAsyncLoadedBlocks(const std::unique_lock<std::mutex>& minimapLock);
    EnumCachedBlockLoad loadSync(const uint8_t z, const uint32_t block);
    static uint64_t getAsyncLoadKey(uint8_t z, uint32_t blockIndex) { return (static_cast<uint64_t>(z) << 32) | blockIndex; }

    Rect calcMapRect(const Rect& screenRect, const Position& mapCenter, float scale) const;
    bool hasBlock(const Position& pos);
    bool hasCachedBlock(const Position& pos) const {
        const auto& floorBlocks = m_cachedBlock[pos.z];
        return floorBlocks.find(getBlockIndex(pos)) != floorBlocks.end();
    }

    // Must be called with m_lock held (main thread).
    bool checkUpdatedTiles(const std::unique_lock<std::mutex>& minimapLock);

    MinimapBlock_ptr getBlock(const Position& pos) { return getBlock(pos.z, getBlockIndex(pos)); }
    MinimapBlock_ptr getBlock(uint8_t z, uint32_t blockIndex)
    {
        auto& ptr = m_tileBlocks[z][blockIndex];
        if (!ptr)
            ptr = std::make_shared<MinimapBlock>();
        return ptr;
    }

    auto& getCachedBlock(const Position& pos) { return getCachedBlock(pos.z, getBlockIndex(pos)); }
    CacheBlock& getCachedBlock(uint8_t z, uint32_t blockIndex) {
        auto it = m_cachedBlock[z].find(blockIndex);
        if (it != m_cachedBlock[z].end())
            return it->second;

        return m_cachedBlock[z]
            .emplace(blockIndex, CacheBlock{ nullptr, EnumCachedBlockLoad::NOT_LOADED })
            .first->second;
    }

    static uint getTileIndex(int x, int y) { return ((y % MMBLOCK_SIZE) * MMBLOCK_SIZE) + (x % MMBLOCK_SIZE); }

    static Point getBlockOffset(const Point& pos)
    {
        return {
            pos.x - pos.x % MMBLOCK_SIZE,
                     pos.y - pos.y % MMBLOCK_SIZE
        };
    }

    static Position getIndexPosition(int index, int z)
    {
        return {
            (index % (65536 / MMBLOCK_SIZE)) * MMBLOCK_SIZE,
                        (index / (65536 / MMBLOCK_SIZE)) * MMBLOCK_SIZE, static_cast<uint8_t>(z)
        };
    }
    static uint32_t getBlockIndex(const Position& pos) { return ((pos.y / MMBLOCK_SIZE) * (65536 / MMBLOCK_SIZE)) + (pos.x / MMBLOCK_SIZE); }

    std::vector<std::unordered_map<uint32_t, MinimapBlock_ptr>> m_tileBlocks;
    std::vector<std::unordered_map<uint32_t, CacheBlock>> m_cachedBlock;
    std::vector<std::vector<uint32_t>> m_blockSaved;
    std::vector<std::vector<uint32_t>> m_newSavedBlocks;
    std::vector<std::unordered_map<Position, MinimapTile, Position::Hasher>> updatedTiles;
    Timer m_savedBlocksMergeTimer;
    std::deque<AsyncLoadRequest> m_asyncLoadQueue;
    std::deque<AsyncLoadedBlock> m_asyncLoadedBlocks;
    std::unordered_set<uint64_t> m_asyncQueuedBlocks;
    std::unordered_map<uint64_t, uint32_t> m_asyncLoadGeneration;
    uint16_t m_asyncActiveLoads{ 0 };
    std::unordered_map<uint64_t, AsyncSaveRequest> m_asyncSavePending;
    std::deque<uint64_t> m_asyncSaveOrder;
    std::unordered_set<uint64_t> m_asyncSaveInFlight;
    uint16_t m_asyncActiveSaves{ 0 };

    // Locking policy:
    // 1) Never call flushAllSavedBlocks while m_lock is held.
    // 2) For nested locks, never acquire m_lock after m_savedBlocksLock/m_asyncLoadLock/m_asyncSaveLock.
    mutable std::mutex m_savedBlocksLock;
    mutable std::mutex m_asyncLoadLock;
    mutable std::mutex m_asyncSaveLock;
    std::condition_variable m_asyncSaveCv;
    std::mutex m_lock;

    ScheduledEventPtr m_gcEvent;

    FrameBufferPtr m_fbo;
    bool m_hdMode{ true };

    friend class MinimapBlock;
    friend struct CacheBlock;
};

extern Minimap g_minimap;

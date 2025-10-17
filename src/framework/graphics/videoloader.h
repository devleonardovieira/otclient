#pragma once

#include <cstdint>
#include <string>

// Minimal video data container, mirroring apng_data style
struct video_data {
    int width = 0;
    int height = 0;
    int bpp = 4; // RGBA

    // Frames are stored contiguously: frame0 RGBA..., frame1 RGBA..., etc.
    uint8_t* pdata = nullptr;
    uint16_t* frames_delay = nullptr; // delay per frame in milliseconds

    uint32_t num_frames = 0;
    uint32_t num_plays = 0; // 0 = infinite, 1 = play once

    // Frame indices to play (inclusive range semantics like apngloader)
    uint32_t first_frame = 0;
    uint32_t last_frame = 0;
};

// Load MP4 video from a real filesystem path into RGBA frames.
// Returns 0 on success, non-zero on failure.
int videoloader_load_mp4(const std::string& realPath, video_data* out);

// Release buffers allocated by videoloader_load_mp4.
void videoloader_free(video_data* v);
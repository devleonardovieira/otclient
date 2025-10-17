#include "videoloader.h"

extern "C" {
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libswscale/swscale.h>
#include <libavutil/imgutils.h>
}

#include <vector>
#include <cmath>
#include <algorithm>

// Avoid Windows macros interfering with std::min/std::max in unity builds
#ifdef max
#undef max
#endif
#ifdef min
#undef min
#endif

static int ms_from_rate(AVRational rate) {
    if (rate.num == 0 || rate.den == 0) return 40; // default ~25fps
    const double fps = av_q2d(rate);
    if (fps <= 0.0) return 40;
    return std::max(1, (int)std::lround(1000.0 / fps));
}

int videoloader_load_mp4(const std::string& realPath, video_data* out)
{
    if (!out) return -1;
    *out = video_data{};

    AVFormatContext* fmt = nullptr;
    int ret = avformat_open_input(&fmt, realPath.c_str(), nullptr, nullptr);
    if (ret < 0) {
        return -2;
    }

    ret = avformat_find_stream_info(fmt, nullptr);
    if (ret < 0) {
        avformat_close_input(&fmt);
        return -3;
    }

    const int vindex = av_find_best_stream(fmt, AVMEDIA_TYPE_VIDEO, -1, -1, nullptr, 0);
    if (vindex < 0) {
        avformat_close_input(&fmt);
        return -4;
    }

    AVStream* vstream = fmt->streams[vindex];
    const AVCodec* codec = avcodec_find_decoder(vstream->codecpar->codec_id);
    if (!codec) {
        avformat_close_input(&fmt);
        return -5;
    }

    AVCodecContext* cctx = avcodec_alloc_context3(codec);
    if (!cctx) {
        avformat_close_input(&fmt);
        return -6;
    }
    ret = avcodec_parameters_to_context(cctx, vstream->codecpar);
    if (ret < 0) {
        avcodec_free_context(&cctx);
        avformat_close_input(&fmt);
        return -7;
    }
    ret = avcodec_open2(cctx, codec, nullptr);
    if (ret < 0) {
        avcodec_free_context(&cctx);
        avformat_close_input(&fmt);
        return -8;
    }

    const int width = cctx->width;
    const int height = cctx->height;
    if (width <= 0 || height <= 0) {
        avcodec_free_context(&cctx);
        avformat_close_input(&fmt);
        return -9;
    }

    SwsContext* sws = sws_getContext(width, height, cctx->pix_fmt,
                                     width, height, AV_PIX_FMT_RGBA,
                                     SWS_BILINEAR, nullptr, nullptr, nullptr);
    if (!sws) {
        avcodec_free_context(&cctx);
        avformat_close_input(&fmt);
        return -10;
    }

    AVFrame* frame = av_frame_alloc();
    AVFrame* rgb = av_frame_alloc();
    if (!frame || !rgb) {
        if (frame) av_frame_free(&frame);
        if (rgb) av_frame_free(&rgb);
        sws_freeContext(sws);
        avcodec_free_context(&cctx);
        avformat_close_input(&fmt);
        return -11;
    }

    const int rgbBufSize = av_image_get_buffer_size(AV_PIX_FMT_RGBA, width, height, 1);
    std::vector<uint8_t> rgbBuf(rgbBufSize);
    av_image_fill_arrays(rgb->data, rgb->linesize, rgbBuf.data(), AV_PIX_FMT_RGBA, width, height, 1);

    AVPacket* pkt = av_packet_alloc();
    if (!pkt) {
        av_frame_free(&frame);
        av_frame_free(&rgb);
        sws_freeContext(sws);
        avcodec_free_context(&cctx);
        avformat_close_input(&fmt);
        return -12;
    }

    std::vector<uint8_t> allFrames;
    std::vector<uint16_t> delays;
    int default_ms = ms_from_rate(vstream->avg_frame_rate.num ? vstream->avg_frame_rate : vstream->r_frame_rate);
    int64_t last_pts = AV_NOPTS_VALUE;
    const double tb = av_q2d(vstream->time_base);

    while (av_read_frame(fmt, pkt) >= 0) {
        if (pkt->stream_index != vindex) {
            av_packet_unref(pkt);
            continue;
        }
        if (avcodec_send_packet(cctx, pkt) < 0) {
            av_packet_unref(pkt);
            break;
        }
        av_packet_unref(pkt);

        while (avcodec_receive_frame(cctx, frame) == 0) {
            // Convert to RGBA
            sws_scale(sws, frame->data, frame->linesize, 0, height, rgb->data, rgb->linesize);
            allFrames.insert(allFrames.end(), rgbBuf.begin(), rgbBuf.end());

            // Compute delay
            int64_t pts = frame->best_effort_timestamp;
            int ms = default_ms;
            if (last_pts != AV_NOPTS_VALUE && pts != AV_NOPTS_VALUE) {
                const double delta = (pts - last_pts) * tb;
                ms = std::max(1, (int)std::lround(delta * 1000.0));
            }
            delays.push_back((uint16_t)std::clamp(ms, 1, 65535));
            last_pts = pts;
        }
    }

    // Flush decoder
    avcodec_send_packet(cctx, nullptr);
    while (avcodec_receive_frame(cctx, frame) == 0) {
        sws_scale(sws, frame->data, frame->linesize, 0, height, rgb->data, rgb->linesize);
        allFrames.insert(allFrames.end(), rgbBuf.begin(), rgbBuf.end());
        delays.push_back((uint16_t)std::clamp(default_ms, 1, 65535));
    }

    av_packet_free(&pkt);
    av_frame_free(&frame);
    av_frame_free(&rgb);
    sws_freeContext(sws);
    avcodec_free_context(&cctx);
    avformat_close_input(&fmt);

    if (allFrames.empty()) {
        return -13;
    }

    // Copy out to contiguous buffers
    out->width = width;
    out->height = height;
    out->bpp = 4;
    out->num_frames = (uint32_t)(allFrames.size() / (width * height * 4));
    out->first_frame = 0;
    out->last_frame = out->num_frames ? (out->num_frames - 1) : 0;
    out->num_plays = 0; // loop

    out->pdata = (uint8_t*)malloc(allFrames.size());
    if (!out->pdata) {
        return -14;
    }
    std::copy(allFrames.begin(), allFrames.end(), out->pdata);

    out->frames_delay = (uint16_t*)malloc(sizeof(uint16_t) * out->num_frames);
    if (!out->frames_delay) {
        free(out->pdata);
        out->pdata = nullptr;
        return -15;
    }
    // If delays vector shorter due to edge cases, fill remaining with default
    for (uint32_t i = 0; i < out->num_frames; ++i) {
        uint16_t d = (i < delays.size()) ? delays[i] : (uint16_t)std::clamp(default_ms, 1, 65535);
        out->frames_delay[i] = d;
    }

    return 0;
}

void videoloader_free(video_data* v)
{
    if (!v) return;
    if (v->pdata) { free(v->pdata); v->pdata = nullptr; }
    if (v->frames_delay) { free(v->frames_delay); v->frames_delay = nullptr; }
    v->num_frames = 0;
}
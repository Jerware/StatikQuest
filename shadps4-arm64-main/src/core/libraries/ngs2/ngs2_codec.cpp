// SPDX-FileCopyrightText: Copyright 2026 shadPS4 Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

#include <algorithm>
#include <cstring>

#include "common/logging/log.h"
#include "core/libraries/error_codes.h"
#include "core/libraries/ngs2/ngs2_codec.h"
#include "core/libraries/ngs2/ngs2_error.h"
#include "core/libraries/ngs2/ngs2_hevag_table.h"

extern "C" {
#include <libatrac9.h>
}

namespace Libraries::Ngs2 {

namespace {

constexpr size_t VagFrameSize = 16;
constexpr size_t VagFrameSamples = 28;

/// Bytes per sample of a PCM type, 0 for anything else.
u32 PcmSampleSize(u32 type) {
    switch (type) {
    case WaveformPcmI8:
    case WaveformPcmU8:
        return 1;
    case WaveformPcmI16L:
    case WaveformPcmI16B:
        return 2;
    case WaveformPcmI24L:
    case WaveformPcmI24B:
        return 3;
    case WaveformPcmI32L:
    case WaveformPcmI32B:
    case WaveformPcmF32L:
    case WaveformPcmF32B:
        return 4;
    case WaveformPcmF64L:
    case WaveformPcmF64B:
        return 8;
    default:
        return 0;
    }
}

float ReadPcm(u32 type, const u8* p) {
    switch (type) {
    case WaveformPcmI8:
        return static_cast<s8>(p[0]) / 128.0f;
    case WaveformPcmU8:
        return (static_cast<int>(p[0]) - 128) / 128.0f;
    case WaveformPcmI16L:
        return static_cast<s16>(p[0] | (p[1] << 8)) / 32768.0f;
    case WaveformPcmI16B:
        return static_cast<s16>(p[1] | (p[0] << 8)) / 32768.0f;
    case WaveformPcmI24L:
        return static_cast<s32>((p[0] << 8) | (p[1] << 16) | (static_cast<u32>(p[2]) << 24)) /
               2147483648.0f;
    case WaveformPcmI24B:
        return static_cast<s32>((p[2] << 8) | (p[1] << 16) | (static_cast<u32>(p[0]) << 24)) /
               2147483648.0f;
    case WaveformPcmI32L:
        return static_cast<s32>(p[0] | (p[1] << 8) | (p[2] << 16) |
                                (static_cast<u32>(p[3]) << 24)) /
               2147483648.0f;
    case WaveformPcmI32B:
        return static_cast<s32>(p[3] | (p[2] << 8) | (p[1] << 16) |
                                (static_cast<u32>(p[0]) << 24)) /
               2147483648.0f;
    case WaveformPcmF32L: {
        float value;
        std::memcpy(&value, p, sizeof(value));
        return value;
    }
    case WaveformPcmF32B: {
        const u8 swapped[4] = {p[3], p[2], p[1], p[0]};
        float value;
        std::memcpy(&value, swapped, sizeof(value));
        return value;
    }
    case WaveformPcmF64L: {
        double value;
        std::memcpy(&value, p, sizeof(value));
        return static_cast<float>(value);
    }
    case WaveformPcmF64B: {
        u8 swapped[8];
        for (int i = 0; i < 8; ++i) {
            swapped[i] = p[7 - i];
        }
        double value;
        std::memcpy(&value, swapped, sizeof(value));
        return static_cast<float>(value);
    }
    default:
        return 0.0f;
    }
}

} // namespace

WaveformDecoder::~WaveformDecoder() {
    Release();
}

void WaveformDecoder::Release() {
    if (atrac9 != nullptr) {
        Atrac9ReleaseHandle(atrac9);
        atrac9 = nullptr;
    }
}

bool WaveformDecoder::Setup(const OrbisNgs2WaveformFormat& format) {
    Release();
    type = WaveformNone;
    channels = 0;
    if (format.numChannels == 0 || format.numChannels > ORBIS_NGS2_MAX_VOICE_CHANNELS) {
        return false;
    }

    if (format.waveformType == WaveformAtrac9) {
        // The configuration travels as the number its four bytes spell.
        atrac9_config[0] = static_cast<u8>(format.configData >> 24);
        atrac9_config[1] = static_cast<u8>(format.configData >> 16);
        atrac9_config[2] = static_cast<u8>(format.configData >> 8);
        atrac9_config[3] = static_cast<u8>(format.configData);
        atrac9 = Atrac9GetHandle();
        Atrac9CodecInfo info{};
        if (atrac9 == nullptr || Atrac9InitDecoder(atrac9, atrac9_config) != 0 ||
            Atrac9GetCodecInfo(atrac9, &info) != 0 || info.framesInSuperframe <= 0 ||
            info.channels <= 0 || info.channels > ORBIS_NGS2_MAX_VOICE_CHANNELS) {
            LOG_ERROR(Lib_Ngs2, "unusable ATRAC9 configuration {:#010x}", format.configData);
            Release();
            return false;
        }
        superframe_size = info.superframeSize;
        frames_in_superframe = info.framesInSuperframe;
        frame_samples = info.frameSamples;
        channels = static_cast<u32>(info.channels);
    } else if (format.waveformType == WaveformVag || PcmSampleSize(format.waveformType) != 0) {
        channels = format.numChannels;
    } else {
        LOG_ERROR(Lib_Ngs2, "unknown waveform type {:#x}", format.waveformType);
        return false;
    }
    type = format.waveformType;
    Restart();
    return true;
}

void WaveformDecoder::Restart() {
    std::memset(vag_history, 0, sizeof(vag_history));
    frame_index = 0;
    superframe_remaining = superframe_size;
    if (type == WaveformAtrac9 && atrac9 != nullptr) {
        // The decoder overlaps each frame with the one before it; starting clean keeps the
        // tail of unrelated audio out of the first frame.
        Atrac9ReleaseHandle(atrac9);
        atrac9 = Atrac9GetHandle();
        if (atrac9 != nullptr) {
            Atrac9InitDecoder(atrac9, atrac9_config);
        }
    }
}

size_t WaveformDecoder::DecodeFrame(const u8* data, size_t size, std::vector<float>& out) {
    if (type == WaveformAtrac9) {
        if (atrac9 == nullptr || size < static_cast<size_t>(superframe_remaining)) {
            return 0;
        }
        const size_t start = out.size();
        out.resize(start + static_cast<size_t>(frame_samples) * channels);
        int used = 0;
        const int ret =
            Atrac9DecodeF32(atrac9, data, superframe_remaining, out.data() + start, &used, 0);
        if (ret != 0 || used <= 0 || used > superframe_remaining) {
            // A frame that does not decode is played as silence, the stream stays in step.
            std::fill(out.begin() + static_cast<std::ptrdiff_t>(start), out.end(), 0.0f);
            used = superframe_remaining;
            frame_index = frames_in_superframe - 1;
        }
        size_t consumed = static_cast<size_t>(used);
        superframe_remaining -= used;
        if (++frame_index >= frames_in_superframe) {
            // Whatever is left of the superframe is padding.
            consumed += static_cast<size_t>(superframe_remaining);
            superframe_remaining = superframe_size;
            frame_index = 0;
        }
        return consumed;
    }

    if (type == WaveformVag) {
        // One 16-byte frame per channel in turn.
        if (size < VagFrameSize * channels) {
            return 0;
        }
        const size_t start = out.size();
        out.resize(start + VagFrameSamples * channels);
        for (u32 channel = 0; channel < channels; ++channel) {
            const u8* frame = data + VagFrameSize * channel;
            u32 predictor = ((frame[0] >> 4) & 0xf) | (frame[1] & 0xf0);
            const u32 shift = frame[0] & 0xf;
            const u32 flag = frame[1] & 0xf;
            if (predictor > 127) {
                predictor = 0;
            }
            const float* coefficients = HevagCoefficients[predictor];
            float* history = vag_history[channel];
            for (size_t i = 0; i < VagFrameSamples; ++i) {
                float sample = 0.0f;
                // Flag 7 marks a frame that is there to be skipped.
                if (flag < 7) {
                    const u8 byte = frame[2 + i / 2];
                    const int nibble = (i & 1) != 0 ? byte >> 4 : byte & 0xf;
                    const int code = ((nibble ^ 8) - 8) * 4096;
                    sample = static_cast<float>(shift < 32 ? code >> shift : 0) +
                             history[0] * coefficients[0] + history[1] * coefficients[1] +
                             history[2] * coefficients[2] + history[3] * coefficients[3];
                }
                history[3] = history[2];
                history[2] = history[1];
                history[1] = history[0];
                history[0] = sample;
                out[start + i * channels + channel] =
                    std::clamp(sample, -32768.0f, 32767.0f) / 32768.0f;
            }
        }
        return VagFrameSize * channels;
    }

    const u32 sample_size = PcmSampleSize(type);
    if (sample_size == 0) {
        return 0;
    }
    const size_t frame_size = size_t{sample_size} * channels;
    // PCM has no frames of its own; a few hundred samples at a time keeps the queue short.
    const size_t frames = std::min<size_t>(size / frame_size, 256);
    if (frames == 0) {
        return 0;
    }
    const size_t start = out.size();
    out.resize(start + frames * channels);
    for (size_t i = 0; i < frames * channels; ++i) {
        out[start + i] = ReadPcm(type, data + i * sample_size);
    }
    return frames * frame_size;
}

namespace {

u32 Read16(const u8* p) {
    return p[0] | (p[1] << 8);
}

u32 Read32(const u8* p) {
    return p[0] | (p[1] << 8) | (p[2] << 16) | (static_cast<u32>(p[3]) << 24);
}

bool IsChunk(const u8* p, const char* id) {
    return std::memcmp(p, id, 4) == 0;
}

/// The WAVE_FORMAT_EXTENSIBLE subformat of ATRAC9.
constexpr u8 Atrac9Guid[16] = {0xd2, 0x42, 0xe1, 0x47, 0xba, 0x36, 0x8d, 0x4d,
                               0x88, 0xfc, 0x61, 0x65, 0x4f, 0x8c, 0x83, 0x6c};
/// The subformats that stand for a plain format tag: the tag, then these bytes.
constexpr u8 WaveGuidTail[14] = {0x00, 0x00, 0x00, 0x00, 0x10, 0x00, 0x80,
                                 0x00, 0x00, 0xaa, 0x00, 0x38, 0x9b, 0x71};

/// The waveform type of a WAVE format tag, WaveformNone for one that cannot be played.
u32 WaveTypeOf(u32 tag, u32 bits) {
    if (tag == 1) { // WAVE_FORMAT_PCM
        switch (bits) {
        case 8:
            return WaveformPcmU8;
        case 16:
            return WaveformPcmI16L;
        case 24:
            return WaveformPcmI24L;
        case 32:
            return WaveformPcmI32L;
        }
    } else if (tag == 3) { // WAVE_FORMAT_IEEE_FLOAT
        switch (bits) {
        case 32:
            return WaveformPcmF32L;
        case 64:
            return WaveformPcmF64L;
        }
    }
    return WaveformNone;
}

} // namespace

s32 GetWaveformLayout(const OrbisNgs2WaveformFormat& format, WaveformLayout& out) {
    out = {};
    if (format.waveformType == WaveformAtrac9) {
        u8 config[4] = {
            static_cast<u8>(format.configData >> 24), static_cast<u8>(format.configData >> 16),
            static_cast<u8>(format.configData >> 8), static_cast<u8>(format.configData)};
        void* handle = Atrac9GetHandle();
        Atrac9CodecInfo info{};
        const bool valid = handle != nullptr && Atrac9InitDecoder(handle, config) == 0 &&
                           Atrac9GetCodecInfo(handle, &info) == 0;
        if (handle != nullptr) {
            Atrac9ReleaseHandle(handle);
        }
        if (!valid || info.framesInSuperframe <= 0 || info.frameSamples <= 0 ||
            info.superframeSize <= 0) {
            return ORBIS_NGS2_ERROR_INVALID_WAVEFORM_CONFIG;
        }
        out.unit_size = static_cast<u32>(info.superframeSize / info.framesInSuperframe);
        out.unit_samples = static_cast<u32>(info.frameSamples);
        out.units_per_frame = static_cast<u32>(info.framesInSuperframe);
        // Each frame overlaps the one before it, so the first frame's worth of output is the
        // decoder starting up. Sony's encoder records the same delay in the "fact" chunk.
        out.delay_samples = out.unit_samples;
        out.preroll_frames = 1;
        return ORBIS_OK;
    }
    if (format.numChannels == 0 || format.numChannels > ORBIS_NGS2_MAX_VOICE_CHANNELS) {
        return ORBIS_NGS2_ERROR_INVALID_WAVEFORM_FORMAT;
    }
    if (format.waveformType == WaveformVag) {
        out.unit_size = static_cast<u32>(VagFrameSize) * format.numChannels;
        out.unit_samples = static_cast<u32>(VagFrameSamples);
        out.units_per_frame = 1;
        // Each sample is predicted from the ones before it.
        out.preroll_frames = 1;
        return ORBIS_OK;
    }
    const u32 sample_size = PcmSampleSize(format.waveformType);
    if (sample_size == 0) {
        return ORBIS_NGS2_ERROR_INVALID_WAVEFORM_TYPE;
    }
    out.unit_size = sample_size * format.numChannels;
    out.unit_samples = 1;
    out.units_per_frame = 1;
    return ORBIS_OK;
}

s32 ParseWaveformData(const u8* data, size_t size, OrbisNgs2WaveformInfo& info) {
    if (size < 12 || !IsChunk(data, "RIFF") || !IsChunk(data + 8, "WAVE")) {
        LOG_ERROR(Lib_Ngs2, "not a RIFF/WAVE file ({} bytes)", size);
        return ORBIS_NGS2_ERROR_UNKNOWN_WAVEFORM_FORMAT;
    }
    OrbisNgs2WaveformFormat format{};
    bool have_format = false;
    bool have_fact = false;
    u32 fact_samples = 0;
    // The chunks follow one another, each padded to an even size; "data" comes after the ones
    // that describe it.
    for (size_t pos = 12; pos + 8 <= size;) {
        const u8* chunk = data + pos;
        const u32 chunk_size = Read32(chunk + 4);
        const u8* body = chunk + 8;
        const size_t available = std::min<size_t>(chunk_size, size - pos - 8);
        if (IsChunk(chunk, "fmt ")) {
            if (available < 16) {
                LOG_ERROR(Lib_Ngs2, "short WAVE format chunk ({} bytes)", available);
                return ORBIS_NGS2_ERROR_INVALID_WAVEFORM_FORMAT;
            }
            u32 tag = Read16(body);
            const u32 bits = Read16(body + 14);
            format.numChannels = Read16(body + 2);
            format.sampleRate = Read32(body + 4);
            format.waveformType = WaveformNone;
            if (tag == 0xfffe && available >= 40) { // WAVE_FORMAT_EXTENSIBLE
                const u8* subformat = body + 24;
                if (std::memcmp(subformat, Atrac9Guid, sizeof(Atrac9Guid)) == 0 &&
                    available >= 48) {
                    format.waveformType = WaveformAtrac9;
                    // The configuration's four bytes, read as one big-endian number.
                    format.configData = (static_cast<u32>(body[44]) << 24) | (body[45] << 16) |
                                        (body[46] << 8) | body[47];
                } else if (std::memcmp(subformat + 2, WaveGuidTail, sizeof(WaveGuidTail)) == 0) {
                    tag = Read16(subformat);
                }
            }
            if (format.waveformType == WaveformNone) {
                format.waveformType = WaveTypeOf(tag, bits);
            }
            if (format.waveformType == WaveformNone) {
                LOG_ERROR(Lib_Ngs2, "unsupported WAVE format {:#x} with {} bits", tag, bits);
                return ORBIS_NGS2_ERROR_UNKNOWN_WAVEFORM_FORMAT;
            }
            have_format = true;
        } else if (IsChunk(chunk, "fact") && available >= 4) {
            fact_samples = Read32(body);
            have_fact = true;
        } else if (IsChunk(chunk, "data")) {
            if (!have_format) {
                break;
            }
            WaveformLayout layout;
            if (const s32 result = GetWaveformLayout(format, layout); result != ORBIS_OK) {
                LOG_ERROR(Lib_Ngs2, "unusable WAVE format: type {:#x}, {} channels, config {:#x}",
                          format.waveformType, format.numChannels, format.configData);
                return result;
            }
            u32 num_samples = fact_samples;
            if (!have_fact) {
                const u64 decoded = u64{chunk_size / layout.FrameSize()} * layout.FrameSamples();
                num_samples = static_cast<u32>(
                    decoded > layout.delay_samples ? decoded - layout.delay_samples : 0);
            }
            const u32 data_offset = static_cast<u32>(pos + 8);
            info = {};
            info.format = format;
            info.dataOffset = data_offset;
            info.dataSize = chunk_size;
            info.numSamples = num_samples;
            info.audioUnitSize = layout.unit_size;
            info.numAudioUnitSamples = layout.unit_samples;
            info.numAudioUnitPerFrame = layout.units_per_frame;
            info.audioFrameSize = layout.FrameSize();
            info.numAudioFrameSamples = layout.FrameSamples();
            info.numDelaySamples = layout.delay_samples;
            // Loop points (a "smpl" chunk) are not read: one block plays the whole sound. Its
            // offset counts from the start of the file, the address titles give the sampler.
            info.numBlocks = 1;
            auto& block = info.aBlock[0];
            block.dataOffset = data_offset;
            block.dataSize = chunk_size;
            block.numSkipSamples = layout.delay_samples;
            block.numSamples = num_samples;
            return ORBIS_OK;
        }
        pos += 8 + size_t{chunk_size} + (chunk_size & 1);
    }
    LOG_ERROR(Lib_Ngs2, "no WAVE format and data in {} bytes", size);
    return ORBIS_NGS2_ERROR_INVALID_WAVEFORM_DATA;
}

s32 CalcWaveformBlock(const OrbisNgs2WaveformFormat& format, u32 sample_pos, u32 num_samples,
                      OrbisNgs2WaveformBlock& block) {
    WaveformLayout layout;
    if (const s32 result = GetWaveformLayout(format, layout); result != ORBIS_OK) {
        return result;
    }
    // Positions count from the first sample of the sound, which comes after the decoder's delay.
    // The block starts at a whole frame, one before the frame holding the first sample when the
    // decoder needs one to settle, and skips the samples up to that first one.
    const u64 frame_samples = layout.FrameSamples();
    const u64 start = u64{sample_pos} + layout.delay_samples;
    const u64 end = start + num_samples;
    u64 first = start / frame_samples;
    first -= std::min<u64>(first, layout.preroll_frames);
    const u64 last = (end + frame_samples - 1) / frame_samples;
    block = {};
    block.dataOffset = static_cast<u32>(first * layout.FrameSize());
    block.dataSize = static_cast<u32>((last - first) * layout.FrameSize());
    block.numSkipSamples = static_cast<u32>(start - first * frame_samples);
    block.numSamples = num_samples;
    return ORBIS_OK;
}

} // namespace Libraries::Ngs2

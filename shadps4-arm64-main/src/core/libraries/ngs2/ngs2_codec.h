// SPDX-FileCopyrightText: Copyright 2026 shadPS4 Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <vector>

#include "common/types.h"
#include "core/libraries/ngs2/ngs2.h"

namespace Libraries::Ngs2 {

/// OrbisNgs2WaveformFormat::waveformType, and the sample format of render buffers.
enum WaveformType : u32 {
    WaveformNone = 0x00,
    WaveformPcmI8 = 0x10,
    WaveformPcmU8 = 0x11,
    WaveformPcmI16L = 0x12,
    WaveformPcmI16B = 0x13,
    WaveformPcmI24L = 0x14,
    WaveformPcmI24B = 0x15,
    WaveformPcmI32L = 0x16,
    WaveformPcmI32B = 0x17,
    WaveformPcmF32L = 0x18,
    WaveformPcmF32B = 0x19,
    WaveformPcmF64L = 0x1a,
    WaveformPcmF64B = 0x1b,
    WaveformVag = 0x1c,
    WaveformAtrac9 = 0x40,
};

/// Turns the encoded audio a sampler voice is fed into floating point samples, a frame at a time.
class WaveformDecoder {
public:
    WaveformDecoder() = default;
    ~WaveformDecoder();
    WaveformDecoder(const WaveformDecoder&) = delete;
    WaveformDecoder& operator=(const WaveformDecoder&) = delete;

    /// Returns false when the format is not one that can be decoded.
    bool Setup(const OrbisNgs2WaveformFormat& format);

    /// Forgets what earlier data left behind; the next frame is the first one of a block.
    void Restart();

    /// Decodes the frame at the start of `data` and appends its samples to `out`, interleaved.
    /// Returns the number of bytes used, or 0 when `size` bytes do not hold a whole frame.
    size_t DecodeFrame(const u8* data, size_t size, std::vector<float>& out);

    u32 Channels() const {
        return channels;
    }

private:
    void Release();

    u32 type{WaveformNone};
    u32 channels{};

    // ATRAC9
    void* atrac9{};
    u8 atrac9_config[4]{};
    int superframe_size{};
    int frames_in_superframe{};
    int frame_samples{};
    int frame_index{};
    int superframe_remaining{};

    // VAG: the four samples before the current one, per channel.
    float vag_history[ORBIS_NGS2_MAX_VOICE_CHANNELS][4]{};
};

/// How the encoded data of a waveform format is cut up. A unit is the codec's own frame (an
/// ATRAC9 frame, a VAG frame of every channel, a sample of every channel); a frame is the
/// smallest piece that decodes on its own, and the place where a block can start (an ATRAC9
/// superframe).
struct WaveformLayout {
    u32 unit_size{};
    u32 unit_samples{};
    u32 units_per_frame{};
    /// Samples the decoder puts out before the first sample of the sound.
    u32 delay_samples{};
    /// Frames to decode, and throw away, before the one a block is meant to start at, for
    /// decoders that carry state from one frame to the next.
    u32 preroll_frames{};

    u32 FrameSize() const {
        return unit_size * units_per_frame;
    }
    u32 FrameSamples() const {
        return unit_samples * units_per_frame;
    }
};

/// Returns ORBIS_OK, or the error that makes `format` unusable.
s32 GetWaveformLayout(const OrbisNgs2WaveformFormat& format, WaveformLayout& out);

/// sceNgs2ParseWaveformData: describes the RIFF/WAVE file at `data`. `size` may cover only the
/// start of the file, as long as that holds everything up to the start of the "data" chunk.
s32 ParseWaveformData(const u8* data, size_t size, OrbisNgs2WaveformInfo& info);

/// sceNgs2CalcWaveformBlock: the block that plays `num_samples` samples from `sample_pos` on.
/// Its data offset counts from the first frame of the sound, not from the start of the file.
s32 CalcWaveformBlock(const OrbisNgs2WaveformFormat& format, u32 sample_pos, u32 num_samples,
                      OrbisNgs2WaveformBlock& block);

} // namespace Libraries::Ngs2

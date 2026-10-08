#pragma once

#include <cstddef>
#include <cstdint>

namespace Libraries::VrTracker {

// 0x90-byte layout used by Statik's tracker initialization at eboot 0x27ddabc.
// Only the fields consumed by our host-backed tracker are named. The game's
// stores establish calibration at 0x20, buffers at 0x40, and compute IDs at 0x70.
struct LegacyTrackerInit {
    std::uint32_t size;
    std::uint32_t profile;
    std::byte header[24];
    std::uint32_t calibration[8];
    void* onion;
    std::uint32_t onion_size;
    std::uint32_t onion_alignment;
    void* garlic;
    std::uint32_t garlic_size;
    std::uint32_t garlic_alignment;
    void* work;
    std::uint32_t work_size;
    std::uint32_t work_alignment;
    std::int32_t pipe;
    std::int32_t queue;
    std::byte tail[24];
};
static_assert(sizeof(LegacyTrackerInit) == 0x90);
static_assert(offsetof(LegacyTrackerInit, calibration) == 0x20);
static_assert(offsetof(LegacyTrackerInit, onion) == 0x40);
static_assert(offsetof(LegacyTrackerInit, garlic) == 0x50);
static_assert(offsetof(LegacyTrackerInit, work) == 0x60);
static_assert(offsetof(LegacyTrackerInit, pipe) == 0x70);

template <class Param>
Param NormalizeLegacyTrackerInit(const LegacyTrackerInit& legacy) {
    Param out{};
    out.size = sizeof(Param);
    out.profile = static_cast<decltype(out.profile)>(legacy.profile);
    auto& cal = out.calibration_settings;
    cal.hmd_position = static_cast<decltype(cal.hmd_position)>(legacy.calibration[0]);
    cal.pad_position = static_cast<decltype(cal.pad_position)>(legacy.calibration[1]);
    cal.move_position = static_cast<decltype(cal.move_position)>(legacy.calibration[2]);
    cal.gun_position = static_cast<decltype(cal.gun_position)>(legacy.calibration[3]);
    out.direct_memory_onion = legacy.onion;
    out.direct_memory_onion_size = legacy.onion_size;
    out.direct_memory_onion_alignment = legacy.onion_alignment;
    out.direct_memory_garlic = legacy.garlic;
    out.direct_memory_garlic_size = legacy.garlic_size;
    out.direct_memory_garlic_alignment = legacy.garlic_alignment;
    out.work_memory = legacy.work;
    out.work_memory_size = legacy.work_size;
    out.work_memory_alignment = legacy.work_alignment;
    out.gpu_pipe_id = legacy.pipe;
    out.gpu_queue_id = legacy.queue;
    return out;
}
} // namespace Libraries::VrTracker

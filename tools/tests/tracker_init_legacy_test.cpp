#include <cassert>
#include <cstring>
#include <array>
#include "core/libraries/vr_tracker/tracker_init_legacy.h"
using namespace Libraries::VrTracker;
// Minimal destination mirrors the fields the decoder consumes, not the guest ABI.
struct Param {
    unsigned size, profile;
    struct { unsigned hmd_position, pad_position, move_position, gun_position; } calibration_settings;
    void* direct_memory_onion;
    unsigned direct_memory_onion_size, direct_memory_onion_alignment;
    void* direct_memory_garlic;
    unsigned direct_memory_garlic_size, direct_memory_garlic_alignment;
    void* work_memory;
    unsigned work_memory_size, work_memory_alignment;
    int gpu_pipe_id, gpu_queue_id;
};
int main() {
    std::array<std::byte, 0x90> bytes{};
    auto put = [&](size_t offset, auto value) { std::memcpy(bytes.data() + offset, &value, sizeof(value)); };
    put(0, 0x90u); put(4, 100u);
    put(0x24, 1u); put(0x28, 1u);
    put(0x40, std::uintptr_t{0x100000}); put(0x48, 0x800000u); put(0x4c, 0x10000u);
    put(0x50, std::uintptr_t{0x200000}); put(0x58, 0x3000000u); put(0x5c, 0x10000u);
    put(0x60, std::uintptr_t{0x300000}); put(0x68, 0x1000000u); put(0x6c, 0x10000u);
    put(0x70, 6); put(0x74, 0);
    LegacyTrackerInit legacy{};
    std::memcpy(&legacy, bytes.data(), bytes.size());
    auto p = NormalizeLegacyTrackerInit<Param>(legacy);
    assert(p.size == sizeof(Param) && p.profile == 100);
    assert(p.calibration_settings.hmd_position == 0 && p.calibration_settings.pad_position == 1);
    assert(p.calibration_settings.move_position == 1 && p.calibration_settings.gun_position == 0);
    assert(p.direct_memory_onion == reinterpret_cast<void*>(0x100000));
    assert(p.direct_memory_onion_size == 0x800000 && p.direct_memory_onion_alignment == 0x10000);
    assert(p.direct_memory_garlic == reinterpret_cast<void*>(0x200000));
    assert(p.direct_memory_garlic_size == 0x3000000 && p.direct_memory_garlic_alignment == 0x10000);
    assert(p.work_memory == reinterpret_cast<void*>(0x300000));
    assert(p.work_memory_size == 0x1000000 && p.work_memory_alignment == 0x10000);
    assert(p.gpu_pipe_id == 6 && p.gpu_queue_id == 0);
}

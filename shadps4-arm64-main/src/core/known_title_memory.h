#pragma once

#include <algorithm>
#include <span>

#include "common/elf_info.h"
#include "core/known_title_builds.h"
#include "core/memory.h"

namespace Core::KnownTitle {

inline bool Accessible(VAddr address, u64 bytes, bool write = false) {
    if (address == 0) {
        return false;
    }
    void* end{};
    u32 protection{};
    if (Memory::Instance()->QueryProtection(address, nullptr, &end, &protection) != 0) {
        return false;
    }
    const auto limit = reinterpret_cast<VAddr>(end);
    const u32 required = write ? 3 : 1;
    return limit >= address && bytes <= limit - address && (protection & required) == required;
}

inline const Builds::Build* RecognizeBuild(VAddr base, u64 size) {
    if (Common::ElfInfo::Instance().GameSerial() != "CUSA12392" || base == 0) {
        return nullptr;
    }
    const auto image = std::span{reinterpret_cast<const u8*>(base), static_cast<size_t>(size)};
    const auto mapped = [&](u64 at, u64 bytes) {
        return at <= image.size() && bytes <= image.size() - at && at <= UINT64_MAX - base &&
               Accessible(base + at, bytes);
    };
    const Builds::Build* selected = nullptr;
    for (const auto& build : Builds::Known) {
        if (!mapped(build.set_recentre, Builds::SetRecentreCode.size()) ||
            !mapped(build.manager_pointer, sizeof(u64)) ||
            !mapped(build.resolution_pointer, sizeof(u64)) ||
            !mapped(build.frame_rate, sizeof(double)) ||
            !mapped(build.frame_seconds, sizeof(float)) ||
            !mapped(build.frame_microseconds, sizeof(u64)) ||
            !mapped(build.size_widths, sizeof(u32) * Builds::ConsoleSizes.size()) ||
            !mapped(build.size_heights, sizeof(u32) * Builds::ConsoleSizes.size()) ||
            !mapped(build.size_pixels, 32 * 6 + sizeof(u64))) {
            continue;
        }
        const auto changes = Builds::SizeChanges(build, Builds::Sizes{});
        if (!std::ranges::all_of(
                changes, [&](const auto& change) { return mapped(change.at, change.bytes); })) {
            continue;
        }
        if (&build == &Builds::Known[1] &&
            !std::ranges::all_of(Builds::AlternateCode,
                                [&](const auto& check) { return mapped(check.at, check.size); })) {
            continue;
        }
        if (Builds::Is(build, image)) {
            if (selected != nullptr) {
                return nullptr;
            }
            selected = &build;
        }
    }
    return selected;
}

}

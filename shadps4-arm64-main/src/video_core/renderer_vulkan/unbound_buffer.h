#pragma once
#include <cstdint>
namespace Vulkan {
// Windows reserves the first 64 KiB. A conditional read-only resource in that
// region cannot have guest backing. Keep the descriptor slot, not a host mapping.
constexpr bool IsUnboundLowReadOnlyBuffer(std::uint64_t address, bool special, bool written) {
    return !special && !written && address < 0x10000;
}
}

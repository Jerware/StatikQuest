#pragma once
#include <algorithm>
#include <array>
#include <cstddef>
#include <cstring>

namespace Libraries::Kernel {
// OS reads cannot take the user-mode write faults used by GPU memory tracking.
// Read into ordinary host memory, then copy with CPU instructions so tracked
// guest pages go through the existing access-violation handler if necessary.
template <class Read>
std::size_t ReadViaHostBuffer(void* destination, std::size_t size, Read read) {
    thread_local std::array<unsigned char, 64 * 1024> staging;
    std::size_t total = 0;
    while (total < size) {
        const auto requested = (std::min)(size - total, staging.size());
        const auto count = read(staging.data(), requested);
        if (count > requested) return total; // Invalid reader result: never overrun staging.
        if (count != 0) {
            std::memcpy(static_cast<unsigned char*>(destination) + total, staging.data(), count);
            total += count;
        }
        if (count < requested) break;
    }
    return total;
}
} // namespace Libraries::Kernel

#pragma once

#include <algorithm>
#include <cmath>
#include <cstdint>

namespace Vulkan {
struct ClearBounds {
    int32_t x, y;
    uint32_t width, height;
};

// A viewport-sized clear must not erase neighbouring views in a packed target.
inline ClearBounds ViewportClearBounds(float x, float y, float width, float height,
                                      int32_t sx, int32_t sy, uint32_t sw, uint32_t sh,
                                      uint32_t target_width, uint32_t target_height) {
    const auto left = std::max({0.0, std::ceil(double(std::min(x, x + width))), double(sx)});
    const auto top = std::max({0.0, std::ceil(double(std::min(y, y + height))), double(sy)});
    const auto right = std::min({double(target_width),
        std::floor(double(std::max(x, x + width))), double(sx) + sw});
    const auto bottom = std::min({double(target_height),
        std::floor(double(std::max(y, y + height))), double(sy) + sh});
    if (right <= left || bottom <= top) return {};
    return {int32_t(left), int32_t(top), uint32_t(right-left), uint32_t(bottom-top)};
}
} // namespace Vulkan

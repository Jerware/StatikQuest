#pragma once
#include <array>
#include <cmath>

namespace Libraries::Hmd {
// Map normalized output-eye coordinates through scene tangents into overlay UVs.
inline bool OverlayUvTransform(const std::array<float, 4>& scene,
                               const std::array<float, 4>& overlay,
                               bool atlas, unsigned eye, std::array<float, 4>& result) {
    for (float value : scene) if (!std::isfinite(value)) return false;
    for (float value : overlay) if (!std::isfinite(value)) return false;
    if (std::abs(scene[0]) < 1e-6f || std::abs(scene[1]) < 1e-6f) return false;
    const float width = atlas ? 0.5f : 1.0f;
    const float start = atlas ? eye * 0.5f : 0.0f;
    result = {width * overlay[0] / scene[0], overlay[1] / scene[1],
              (start - scene[2]) * overlay[0] / scene[0] + overlay[2],
              -scene[3] * overlay[1] / scene[1] + overlay[3]};
    for (float value : result) if (!std::isfinite(value)) return false;
    return true;
}
}

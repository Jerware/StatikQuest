// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once
#include <cmath>

namespace Libraries::Hmd {
// Symmetric side-by-side atlas: opposite eye centers in one shared image.
// Equal centers (a monoscopic image), separate images and invalid mappings are unchanged.
inline bool IsSideBySideEyeAtlas(bool shared_image, float left_scale, float right_scale,
                                float left_center, float right_center) {
    return shared_image && std::isfinite(left_scale) && left_scale > 0 &&
           std::abs(left_scale - right_scale) < 0.0001f && left_center > 0 &&
           left_center < 0.5f && right_center > 0.5f && right_center < 1 &&
           std::abs(left_center + right_center - 1.0f) < 0.0001f;
}
} // namespace Libraries::Hmd

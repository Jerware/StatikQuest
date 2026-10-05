#pragma once

#include <algorithm>
#include <array>
#include <cmath>
#include <optional>

#include "core/vr/vr_runtime.h"

namespace Core::Vr {

struct ViewTangents {
    float left;
    float right;
    float up;
    float down;
};

inline std::optional<ViewTangents> ParallelViewTangents(const std::array<Vec3, 4>& corners) {
    if (std::ranges::any_of(corners, [](const Vec3& ray) {
            return !std::isfinite(ray.x) || !std::isfinite(ray.y) || !std::isfinite(ray.z) ||
                   ray.z >= -1e-5f;
        })) {
        return std::nullopt;
    }
    const auto horizontal =
        std::minmax({-corners[0].x / corners[0].z, -corners[1].x / corners[1].z,
                     -corners[2].x / corners[2].z, -corners[3].x / corners[3].z});
    const auto vertical = std::minmax({-corners[0].y / corners[0].z, -corners[1].y / corners[1].z,
                                       -corners[2].y / corners[2].z, -corners[3].y / corners[3].z});
    return ViewTangents{-horizontal.first, horizontal.second, vertical.second, -vertical.first};
}

}

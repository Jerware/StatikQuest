#include <array>
#include <cmath>
#include <cstdio>
#include <limits>

#include "core/vr/openxr_view.h"

using Core::Vr::ParallelViewTangents;
using Core::Vr::Vec3;

bool Near(float got, float expected) {
    if (std::abs(got - expected) < 1e-5f) {
        return true;
    }
    std::fprintf(stderr, "Expected %.6f, got %.6f\n", expected, got);
    return false;
}

int main() {
    const std::array corners{Vec3{-0.8f, 1.1f, -1.0f}, Vec3{1.2f, 1.1f, -1.0f},
                             Vec3{-0.8f, -0.9f, -1.0f}, Vec3{1.2f, -0.9f, -1.0f}};
    const auto parallel = ParallelViewTangents(corners);
    if (!parallel || !Near(parallel->left, 0.8f) || !Near(parallel->right, 1.2f) ||
        !Near(parallel->up, 1.1f) || !Near(parallel->down, 0.9f)) {
        return 1;
    }

    constexpr float cant = 5.0f * 3.14159265358979323846f / 180.0f;
    const auto canted_ray = [](const Vec3& ray) {
        return Vec3{std::cos(cant) * ray.x + std::sin(cant) * ray.z, ray.y,
                    -std::sin(cant) * ray.x + std::cos(cant) * ray.z};
    };
    const auto canted = ParallelViewTangents({canted_ray(corners[0]), canted_ray(corners[1]),
                                              canted_ray(corners[2]), canted_ray(corners[3])});
    const float depth = std::cos(cant) - 0.8f * std::sin(cant);
    if (!canted || !Near(canted->left, std::tan(std::atan(0.8f) + cant)) ||
        !Near(canted->right, std::tan(std::atan(1.2f) - cant)) || !Near(canted->up, 1.1f / depth) ||
        !Near(canted->down, 0.9f / depth)) {
        return 1;
    }
    const auto mirrored =
        ParallelViewTangents({Vec3{-1.2f, 1.1f, -1.0f}, Vec3{0.8f, 1.1f, -1.0f},
                              Vec3{-1.2f, -0.9f, -1.0f}, Vec3{0.8f, -0.9f, -1.0f}});
    if (!mirrored || !Near(mirrored->left, 1.2f) || !Near(mirrored->right, 0.8f)) {
        return 1;
    }
    const float nan = std::numeric_limits<float>::quiet_NaN();
    const float infinity = std::numeric_limits<float>::infinity();
    for (const Vec3 invalid :
         {Vec3{0, 0, 0}, Vec3{0, 0, 1}, Vec3{nan, 0, -1}, Vec3{0, infinity, -1}}) {
        if (ParallelViewTangents({invalid, corners[1], corners[2], corners[3]})) {
            std::fprintf(stderr, "Accepted an invalid view ray\n");
            return 1;
        }
    }
    std::puts("OpenXR parallel and canted view checks passed");
    return 0;
}

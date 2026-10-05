#include <cmath>
#include <cstdio>
#include <limits>

#include "core/vr/spectator_view.h"

using namespace Core::Vr;

bool Check(bool value, const char* name) {
    if (!value) {
        std::fprintf(stderr, "FAIL: %s\n", name);
    }
    return value;
}

bool Near(float a, float b) {
    return std::abs(a - b) < 1e-5f;
}

bool CoversWidth(u32 width, const Fov& fov) {
    const auto regions = CombinedEyeRegions(width, fov);
    for (const auto& region : regions) {
        if (region.x + region.width > width || region.clip_x + region.clip_width > width ||
            (region.clip_width != 0 &&
             (region.clip_x < region.x ||
              region.clip_x + region.clip_width > region.x + region.width))) {
            return false;
        }
    }
    for (u32 pixel = 0; pixel < width; ++pixel) {
        const bool primary =
            pixel >= regions[0].clip_x && pixel < regions[0].clip_x + regions[0].clip_width;
        const bool secondary =
            pixel >= regions[1].clip_x && pixel < regions[1].clip_x + regions[1].clip_width;
        if (primary == secondary) {
            return false;
        }
    }
    return true;
}

int main() {
    bool ok = true;
    ok &= Check(ParseDesktopView("") == DesktopView::Stereo &&
                    ParseDesktopView("unknown") == DesktopView::Stereo &&
                    ParseDesktopView("spectator") == DesktopView::Spectator &&
                    ParseDesktopView("combined") == DesktopView::Combined,
                "desktop modes");
    const Fov simple{2.0f, 1.0f, 1.5f, 1.0f};
    const Fov reversed{1.0f, 2.0f, 1.5f, 1.0f};
    const Fov symmetric{1.0f, 1.0f, 1.0f, 1.0f};
    const Fov invalid{std::numeric_limits<float>::quiet_NaN(), 1.0f, 1.0f, 1.0f};
    for (const float tangent :
         {0.0f, -1.0f, 1e-30f, 101.0f, std::numeric_limits<float>::infinity()}) {
        ok &= Check(!ValidSpectatorFov({1.0f, 1.0f, tangent, 1.0f}),
                    "reject unsafe projection bounds");
    }
    ok &= Check(Near(DesktopViewAspect(DesktopView::Stereo, simple, 0.9375f), 1.875f),
                "stereo keeps pixel aspect");
    ok &= Check(Near(DesktopViewAspect(DesktopView::Spectator, simple, 0.9375f), 0.9375f),
                "default single eye stays unchanged");
    ok &= Check(Near(DesktopViewAspect(DesktopView::Combined, simple, 0.9375f), 1.6f),
                "combined aspect covers both peripheral edges");
    ok &= Check(Near(DesktopViewAspect(DesktopView::Combined, invalid, 0.9375f), 0.9375f),
                "invalid FOV falls back to one eye");
    for (const auto& fov : {simple, reversed, symmetric, invalid}) {
        for (const u32 width : {0u, 1u, 2u, 3u, 101u, 1920u}) {
            ok &= Check(CoversWidth(width, fov), "combined regions cover every pixel exactly once");
        }
    }
    const auto layout = CombinedEyeRegions(100, simple);
    ok &= Check(layout[0].x == 0 && layout[0].width == 75 && layout[1].x == 25 &&
                    layout[1].width == 75 && layout[1].clip_x == 75 && layout[1].clip_width == 25,
                "combined keeps primary eye and right peripheral strip");
    const auto mirror = CombinedEyeRegions(100, reversed);
    ok &= Check(mirror[0].x == 25 && mirror[0].width == 75 && mirror[1].clip_x == 0 &&
                    mirror[1].clip_width == 25,
                "reversed asymmetry keeps left peripheral strip");
    std::puts(ok ? "spectator view checks passed" : "spectator view checks failed");
    return ok ? 0 : 1;
}

#include <cassert>
#include <limits>
#include "core/libraries/hmd/overlay_layout.h"

int main() {
    using Libraries::Hmd::OverlayUvTransform;
    std::array<float, 4> result{};
    const auto near = [](float a, float b) { return std::abs(a-b) < 0.00001f; };
    assert(OverlayUvTransform({0.2f,0.4f,0.25f,0.5f}, {0.4f,0.4f,0.5f,0.5f}, true, 0, result));
    assert(near(result[0],1) && near(result[1],1) && near(result[2],0) && near(result[3],0));
    assert(OverlayUvTransform({0.2f,0.4f,0.75f,0.5f}, {0.4f,0.4f,0.5f,0.5f}, true, 1, result));
    assert(near(result[0],1) && near(result[2],0));
    assert(OverlayUvTransform({0.4f,0.4f,0.5f,0.5f}, {0.2f,0.2f,0.6f,0.4f}, false, 0, result));
    assert(near(result[0],0.5f) && near(result[1],0.5f) && near(result[2],0.35f) && near(result[3],0.15f));
    assert(!OverlayUvTransform({0,1,0,0}, {1,1,0,0}, false, 0, result));
    assert(!OverlayUvTransform({1,1,0,0}, {std::numeric_limits<float>::quiet_NaN(),1,0,0}, false, 0, result));
}

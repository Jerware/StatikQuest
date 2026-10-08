#include <cassert>
#include <limits>
#include <cstdio>
#include "core/libraries/hmd/eye_layout.h"

int main() {
    using Libraries::Hmd::IsSideBySideEyeAtlas;
    assert(IsSideBySideEyeAtlas(true, .20931222f, .20931222f, .25272986f, .74727017f));
    assert(!IsSideBySideEyeAtlas(false, .20931222f, .20931222f, .25272986f, .74727017f));
    assert(!IsSideBySideEyeAtlas(true, .4f, .4f, .5f, .5f));
    assert(!IsSideBySideEyeAtlas(true, 0, 0, .25f, .75f));
    assert(!IsSideBySideEyeAtlas(true, .2f, .4f, .25f, .75f));
    assert(!IsSideBySideEyeAtlas(true, .2f, .2f, .2f, .7f));
    assert(!IsSideBySideEyeAtlas(true, std::numeric_limits<float>::quiet_NaN(), .2f, .25f, .75f));
    // Cropping the texture midpoint yields the inner angle, not the far edge of the other eye.
    const float inner = (.5f - .25272986f) / .20931222f;
    assert(inner > 1.18f && inner < 1.19f);
    std::puts("Eye layout: packed stereo, mono, separate images and invalid mappings passed");
}

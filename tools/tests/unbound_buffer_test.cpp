#include <cassert>
#include "video_core/renderer_vulkan/unbound_buffer.h"
int main() {
    using Vulkan::IsUnboundLowReadOnlyBuffer;
    assert(IsUnboundLowReadOnlyBuffer(0x692, false, false));
    assert(IsUnboundLowReadOnlyBuffer(0, false, false));
    assert(IsUnboundLowReadOnlyBuffer(0xffff, false, false));
    assert(!IsUnboundLowReadOnlyBuffer(0x10000, false, false));
    assert(!IsUnboundLowReadOnlyBuffer(0x244432800ULL, false, false));
    assert(!IsUnboundLowReadOnlyBuffer(0x692, false, true));
    assert(!IsUnboundLowReadOnlyBuffer(0x692, true, false));
}

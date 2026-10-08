#include <cassert>
#include <cstdio>
#include <intrin.h>
#include <windows.h>
#include "core/libraries/kernel/allocation_trace.h"

__declspec(noinline) __attribute__((sysv_abi)) void CheckRealFrame() {
    const auto expected = reinterpret_cast<std::uintptr_t>(_ReturnAddress());
    const auto slot = reinterpret_cast<std::uintptr_t>(_AddressOfReturnAddress());
    std::printf("Windows allocation frame test: host frame=%p\n", __builtin_frame_address(0));
    unsigned count = 0;
    Libraries::Kernel::WalkAllocationFrames(slot - sizeof(std::uintptr_t),
        [](std::uintptr_t at, void* data, std::size_t size) {
            SIZE_T copied{};
            return ReadProcessMemory(GetCurrentProcess(), reinterpret_cast<const void*>(at),
                                     data, size, &copied) && copied == size;
        },
        [&](unsigned depth, auto, std::uintptr_t caller) {
            if (depth == 0) {
                assert(caller != 0 && caller == expected);
            }
            ++count;
        });
    assert(count > 0);
}
int main() { CheckRealFrame(); }

#include <cassert>
#include <cstring>
#include "core/libraries/kernel/allocation_trace.h"
int main() {
    using namespace Libraries::Kernel;
    unsigned reports = 0;
    auto report = [&](unsigned, auto, auto) { ++reports; };
    WalkAllocationFrames(0x1000, [](auto, void*, auto) { return false; }, report);
    assert(reports == 0);
    WalkAllocationFrames(0x1001, [](auto, void*, auto) { assert(false); return true; }, report);
    assert(reports == 0);
    auto chain = [](std::uintptr_t at, void* out, std::size_t size) {
        std::uintptr_t words[]{at == 0x1000 ? 0x1020u : 0x1000u, 0x800331487ULL};
        std::memcpy(out, words, size);
        return true;
    };
    WalkAllocationFrames(0x1000, chain, report);
    assert(reports == 2); // Stops a cycle/backwards link.
    reports = 0;
    WalkAllocationFrames(0x1000, [](std::uintptr_t at, void* out, std::size_t size) {
        std::uintptr_t words[]{at + 16, 0};
        std::memcpy(out, words, size);
        return true;
    }, report);
    assert(reports == 32); // Hard cap even on a readable infinite chain.
}

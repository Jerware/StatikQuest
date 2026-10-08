#include <cassert>
#include <cstdio>
#include "core/libraries/libc_internal/ctype_table.h"

int main() {
    const auto* table = Libraries::LibcInternal::CtypeTable.data() + 1;
    assert(table[-1] == 0);
    // Independent ranges observed in the guest's C-locale table.
    struct Range { int first, last, mask; };
    constexpr Range ranges[] = {
        {0,8,0x80}, {9,9,0x4c0}, {10,13,0xc0}, {14,31,0x80}, {32,32,4},
        {33,47,8}, {48,57,0x21}, {58,64,8}, {65,70,3}, {71,90,2},
        {91,96,8}, {97,102,0x11}, {103,122,0x10}, {123,126,8},
        {127,127,0x80}, {128,255,0}
    };
    for (const auto& range : ranges)
        for (int c = range.first; c <= range.last; ++c)
            assert(table[c] == range.mask);
    std::puts("Guest ctype: all 257 entries passed");
}

// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include <array>
#include <cstdint>

namespace Libraries::LibcInternal {

// Guest C-locale masks, verified against Statik's libc _Getpctype table.
// These are not the host CRT's masks. Entry zero represents EOF (-1).
inline constexpr auto CtypeTable = [] {
    std::array<std::uint16_t, 257> table{};
    for (int c = 0; c < 256; ++c) {
        auto& mask = table[c + 1];
        if (c < 32 || c == 127) mask |= 0x80; // control
        if (c >= 9 && c <= 13) mask |= 0x40; // whitespace control
        if (c == 9) mask |= 0x400; // extra blank
        if (c == 32) mask |= 0x04; // space
        if (c >= '0' && c <= '9') mask |= 0x21; // digit, hex
        if (c >= 'A' && c <= 'Z') mask |= 0x02; // upper
        if (c >= 'a' && c <= 'z') mask |= 0x10; // lower
        if ((c >= 'A' && c <= 'F') || (c >= 'a' && c <= 'f')) mask |= 0x01;
        if (c >= 33 && c <= 126 && mask == 0) mask = 0x08; // punctuation
    }
    return table;
}();

} // namespace Libraries::LibcInternal

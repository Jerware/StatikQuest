#pragma once
#include <cstddef>
#include <cstdint>

namespace Libraries::Kernel {
// Best-effort frame-pointer walk, never an unchecked dereference. Guest x64
// code uses frame pointers; native frames without them may terminate the walk.
template <class Read, class Report>
void WalkAllocationFrames(std::uintptr_t frame, Read read, Report report) {
    for (unsigned depth = 0; depth < 32 && frame != 0; ++depth) {
        std::uintptr_t words[2]{};
        if (frame % alignof(std::uintptr_t) != 0 || !read(frame, words, sizeof(words))) {
            break;
        }
        report(depth, frame, words[1]);
        if (words[0] <= frame || words[0] - frame > 1024 * 1024) {
            break;
        }
        frame = words[0];
    }
}
} // namespace Libraries::Kernel

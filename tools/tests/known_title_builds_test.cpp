// Checks how the emulator tells the builds of ASTRO BOT Rescue Mission apart, and that it only
// ever writes into one it has recognised, all of what it means to write or nothing.
//
//   clang-cl /std:c++latest /EHsc -fuse-ld=lld /I shadps4-arm64-main/src
//       tools/tests/known_title_builds_test.cpp /Fe:build/tests/known_title_builds_test.exe
//   build/tests/known_title_builds_test.exe [plain ELF of an eboot.bin ...]
//
// Without arguments it works on images made up here, which hold what a build has at the places
// the emulator looks at and nothing else. Given executables (made plain with
// `node tools/ps4elf.mjs unwrap <eboot.bin> <out.elf>`), it also says which build each is.
#include <cstdio>
#include <cstring>
#include <fstream>
#include <string>
#include <vector>

#include "core/known_title_builds.h"

using namespace Core::KnownTitle::Builds;

static int failures = 0;

static void Check(bool ok, const std::string& what) {
    std::printf("%s  %s\n", ok ? "ok  " : "FAIL", what.c_str());
    failures += ok ? 0 : 1;
}

template <typename T>
static void Put(std::vector<u8>& image, u64 at, T value) {
    std::memcpy(image.data() + at, &value, sizeof(T));
}

/// An image that holds what `build` has, as loaded, in every place the emulator looks at.
static std::vector<u8> MadeUp(const Build& build) {
    std::vector<u8> image(0x3200000);
    std::memcpy(image.data() + build.set_recentre, SetRecentreCode.data(), SetRecentreCode.size());
    if (build.set_recentre == Known[1].set_recentre) {
        for (const auto& check : AlternateCode) {
            std::memcpy(image.data() + check.at, check.bytes.data(), check.size);
        }
    }
    Put(image, build.frame_rate, ConsoleFrameRate);
    Put(image, build.frame_seconds, ConsoleFrameSeconds);
    Put(image, build.frame_microseconds, ConsoleFrameMicroseconds);
    for (u32 level = 0; level < ConsoleSizes.size(); ++level) {
        Put(image, build.size_widths + 4 * level, ConsoleSizes[level][0]);
        Put(image, build.size_heights + 4 * level, ConsoleSizes[level][1]);
        Put(image, build.size_pixels + 32 * level,
            u64{ConsoleSizes[level][0]} * ConsoleSizes[level][1]);
    }
    for (const Change& change : SizeChanges(build, Sizes{})) {
        std::memcpy(image.data() + change.at, &change.was, change.bytes);
    }
    return image;
}

/// Twice the console's sizes, as the emulator works them out for a width of 2880.
static Sizes Doubled() {
    Sizes sizes;
    for (s32 level = FirstHeadsetLevel; level <= LastHeadsetLevel; ++level) {
        sizes.sizes[level] = {ConsoleSizes[level][0] * 2, ConsoleSizes[level][1] * 2};
    }
    sizes.target_pool = 880u << 20;
    sizes.small_pool = 44u << 20;
    sizes.graphics_heap = 2186ull << 20;
    return sizes;
}

/// The image an executable makes in memory: its loaded parts at their addresses.
static std::vector<u8> Load(const char* path) {
    std::ifstream file{path, std::ios::binary};
    std::vector<u8> elf{std::istreambuf_iterator<char>{file}, std::istreambuf_iterator<char>{}};
    if (elf.size() < 0x40 || std::memcmp(elf.data(), "\x7f" "ELF", 4) != 0) {
        return {};
    }
    const auto read = [&](u64 at, auto& value) {
        if (at + sizeof(value) > elf.size()) {
            return false;
        }
        std::memcpy(&value, elf.data() + at, sizeof(value));
        return true;
    };
    u64 headers = 0;
    u16 header_size = 0;
    u16 header_count = 0;
    read(0x20, headers);
    read(0x36, header_size);
    read(0x38, header_count);
    std::vector<u8> image;
    for (u32 i = 0; i < header_count; ++i) {
        const u64 at = headers + u64{i} * header_size;
        u32 type = 0;
        u64 offset = 0, address = 0, in_file = 0, in_memory = 0;
        if (!read(at, type) || !read(at + 8, offset) || !read(at + 16, address) ||
            !read(at + 32, in_file) || !read(at + 40, in_memory)) {
            return {};
        }
        // PT_LOAD and PT_SCE_RELRO.
        if ((type != 1 && type != 0x61000010) || offset + in_file > elf.size()) {
            continue;
        }
        if (image.size() < address + in_memory) {
            image.resize(address + in_memory);
        }
        std::memcpy(image.data() + address, elf.data() + offset, in_file);
    }
    return image;
}

int main(int argc, char** argv) {
    for (const Build& build : Known) {
        const std::string name = build.name;
        std::vector<u8> image = MadeUp(build);
        Check(Recognise(image) == &build, name + ": recognised");
        Check(Recognise(std::span<const u8>{}) == nullptr, name + ": not an empty image");
        Check(Recognise(std::span{image}.first(build.set_recentre + 4)) == nullptr,
              name + ": not an image cut short");

        // One byte off anywhere the emulator looks, and it is no build that is known.
        std::vector<u64> places{build.set_recentre + 3, build.frame_rate, build.frame_seconds,
                                build.frame_microseconds, build.size_widths + 4 * 6,
                                build.size_heights + 4 * 2, build.size_pixels};
        if (build.set_recentre == Known[1].set_recentre) {
            for (const auto& check : AlternateCode) {
                places.push_back(check.at);
            }
        }
        for (const Change& change : SizeChanges(build, Sizes{})) {
            places.push_back(change.at);
        }
        bool all_refused = true;
        for (const u64 place : places) {
            image[place] ^= 0x40;
            all_refused &= Recognise(image) == nullptr;
            image[place] ^= 0x40;
        }
        Check(all_refused, name + ": refused with any of " + std::to_string(places.size()) +
                               " places changed");
        Check(Recognise(image) == &build, name + ": recognised again once they are restored");

        // Larger sizes: all of them written, the television's left alone.
        const Sizes doubled = Doubled();
        const auto changes = SizeChanges(build, doubled);
        Check(changes.size() == 30, name + ": 30 places set the sizes");
        std::vector<u8> larger = image;
        Check(Apply(larger, changes) == nullptr, name + ": larger sizes written");
        bool written = true;
        for (const Change& change : changes) {
            u64 found = 0;
            std::memcpy(&found, larger.data() + change.at, change.bytes);
            written &= found == change.now;
        }
        Check(written, name + ": every place holds the larger size");
        u32 television = 0;
        std::memcpy(&television, larger.data() + build.size_widths + 4 * 2, sizeof(u32));
        Check(television == 1920, name + ": the television's sizes are left alone");
        Check(Apply(larger, changes) != nullptr, name + ": not written a second time");
        Check(Recognise(larger) == nullptr, name + ": an image with larger sizes is not asked "
                                                   "what it is again");

        // One place that is not as expected, the last one: nothing at all is written.
        std::vector<u8> odd = image;
        odd[changes.back().at] ^= 1;
        const std::vector<u8> before = odd;
        Check(Apply(odd, changes) == &changes.back() && odd == before,
              name + ": nothing written when the last place is not as expected");
        // A place beyond the image.
        const std::vector<Change> beyond{{image.size() - 2, 0, 1, 4}};
        Check(Apply(image, beyond) == &beyond[0], name + ": nothing written beyond the image");
        const std::vector<Change> overflow{{UINT64_MAX, 0, 1, 8}};
        Check(Apply(image, overflow) == &overflow[0], name + ": overflowing destination refused");
    }

    // An image that would be both builds at once is neither.
    std::vector<u8> both = MadeUp(Known[0]);
    const std::vector<u8> other = MadeUp(Known[1]);
    for (size_t i = 0; i < both.size(); ++i) {
        both[i] |= other[i];
    }
    Check(Is(Known[0], both) && Is(Known[1], both) && Recognise(both) == nullptr,
          "an image that is both builds at once is neither");

    for (int i = 1; i < argc; ++i) {
        const std::vector<u8> image = Load(argv[i]);
        const Build* build = image.empty() ? nullptr : Recognise(image);
        std::printf("%s: %s\n", argv[i],
                    image.empty() ? "not a plain ELF"
                                  : build != nullptr ? build->name : "no build that is known");
        if (build != nullptr) {
            std::vector<u8> larger = image;
            Check(Apply(larger, SizeChanges(*build, Doubled())) == nullptr,
                  std::string{"larger sizes written into "} + argv[i]);
        }
    }

    std::printf("failed: %d\n", failures);
    return failures == 0 ? 0 : 1;
}

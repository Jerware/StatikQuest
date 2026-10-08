#include <cassert>
#include <cerrno>
#include <cstdio>
#include <cstdint>
#include <vector>
#include <windows.h>
#include "core/libraries/kernel/guest_file_read.h"

static unsigned char* target;
static constexpr std::size_t Size = 256 * 1024;
static unsigned faults;
static LONG WINAPI WriteFault(EXCEPTION_POINTERS* e) {
    const auto& r = *e->ExceptionRecord;
    const auto address = r.ExceptionInformation[1];
    if (r.ExceptionCode != EXCEPTION_ACCESS_VIOLATION || r.ExceptionInformation[0] != 1 ||
        address < reinterpret_cast<std::uintptr_t>(target) ||
        address >= reinterpret_cast<std::uintptr_t>(target) + Size) return EXCEPTION_CONTINUE_SEARCH;
    DWORD old{};
    if (!VirtualProtect(target, Size, PAGE_READWRITE, &old)) return EXCEPTION_CONTINUE_SEARCH;
    ++faults;
    return EXCEPTION_CONTINUE_EXECUTION;
}

int main() {
    FILE* file{};
    assert(tmpfile_s(&file) == 0 && file);
    std::vector<unsigned char> expected(Size);
    for (std::size_t i = 0; i < Size; ++i) expected[i] = static_cast<unsigned char>(i * 37 + i / 256);
    assert(std::fwrite(expected.data(), 1, Size, file) == Size);
    assert(std::fflush(file) == 0);
    target = static_cast<unsigned char*>(VirtualAlloc(nullptr, Size, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE));
    assert(target);
    auto* handler = AddVectoredExceptionHandler(1, WriteFault);
    assert(handler);
    DWORD old{};
    assert(std::fseek(file, 0, SEEK_SET) == 0);
    assert(VirtualProtect(target, Size, PAGE_READONLY, &old));
    errno = 0;
    const auto direct = std::fread(target, 1, Size, file);
    std::printf("Direct fread into tracked page: bytes=%zu errno=%d ferror=%d CPU faults=%u\n",
                direct, errno, std::ferror(file), faults);
    assert(direct < Size && std::ferror(file) && faults == 0);
    std::clearerr(file);
    assert(std::fseek(file, 0, SEEK_SET) == 0);
    const auto staged = Libraries::Kernel::ReadViaHostBuffer(target, Size,
        [&](void* data, std::size_t count) { return std::fread(data, 1, count, file); });
    assert(staged == Size && faults == 1 && !std::ferror(file));
    assert(std::memcmp(target, expected.data(), Size) == 0);
    assert(std::ftell(file) == Size);
    // Model the graphics thread re-protecting the destination after each host
    // read, i.e. after initial invalidation but before copying to guest memory.
    assert(std::fseek(file, 0, SEEK_SET) == 0);
    unsigned chunks = 0;
    const auto raced = Libraries::Kernel::ReadViaHostBuffer(target, Size,
        [&](void* data, std::size_t count) {
            const auto result = std::fread(data, 1, count, file);
            DWORD previous{};
            assert(VirtualProtect(target, Size, PAGE_READONLY, &previous));
            ++chunks;
            return result;
        });
    assert(raced == Size && chunks == 4 && faults == 1 + chunks);
    assert(std::memcmp(target, expected.data(), Size) == 0);
    assert(std::fseek(file, Size - 17, SEEK_SET) == 0);
    const auto tail = Libraries::Kernel::ReadViaHostBuffer(target, Size,
        [&](void* data, std::size_t count) { return std::fread(data, 1, count, file); });
    assert(tail == 17 && std::memcmp(target, expected.data() + Size - 17, 17) == 0);
    assert(Libraries::Kernel::ReadViaHostBuffer(nullptr, 0,
        [](void*, std::size_t) -> std::size_t { assert(false); return 0; }) == 0);
    assert(RemoveVectoredExceptionHandler(handler));
    assert(VirtualFree(target, 0, MEM_RELEASE));
    assert(std::fclose(file) == 0);
    std::puts("Staged read passed: protected pages, full content, file position, EOF and zero length.");
}

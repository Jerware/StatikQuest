#pragma once

// Optional native Windows diagnostics. Restore and re-execute the original
// instruction instead of emulating it, preserving its register/flag semantics.
#include <atomic>
#include <cstdint>
#include <cstring>
#include <span>
#include <windows.h>

namespace Core {
inline bool ReadProbeMemory(std::uintptr_t address, void* out, std::size_t size) {
    SIZE_T copied{};
    return ReadProcessMemory(GetCurrentProcess(), reinterpret_cast<const void*>(address),
                             out, size, &copied) && copied == size;
}

class OneShotProbe {
public:
    // Install before guest threads start. Never patch an unrecognized binary.
    bool Install(std::uintptr_t address, std::span<const unsigned char> expected) {
        unsigned char actual[16]{};
        if (address_ || expected.empty() || expected.size() > sizeof(actual) ||
            !ReadProbeMemory(address, actual, expected.size()) ||
            std::memcmp(actual, expected.data(), expected.size()) != 0) {
            return false;
        }
        DWORD old{};
        if (!VirtualProtect(reinterpret_cast<void*>(address), 1, PAGE_EXECUTE_READWRITE, &old)) {
            return false;
        }
        address_ = address;
        original_ = actual[0];
        *reinterpret_cast<volatile unsigned char*>(address_) = 0xcc;
        FlushInstructionCache(GetCurrentProcess(), reinterpret_cast<void*>(address_), 1);
        DWORD ignored{};
        VirtualProtect(reinterpret_cast<void*>(address_), 1, old, &ignored);
        return true;
    }

    bool Resume(EXCEPTION_POINTERS* exception, bool& first) {
        first = false;
        if (!address_ || !exception || !exception->ExceptionRecord || !exception->ContextRecord ||
            exception->ExceptionRecord->ExceptionCode != EXCEPTION_BREAKPOINT ||
            reinterpret_cast<std::uintptr_t>(exception->ExceptionRecord->ExceptionAddress) != address_) {
            return false;
        }
        DWORD old{};
        if (!VirtualProtect(reinterpret_cast<void*>(address_), 1, PAGE_EXECUTE_READWRITE, &old)) {
            return false;
        }
        *reinterpret_cast<volatile unsigned char*>(address_) = original_;
        FlushInstructionCache(GetCurrentProcess(), reinterpret_cast<void*>(address_), 1);
        DWORD ignored{};
        VirtualProtect(reinterpret_cast<void*>(address_), 1, old, &ignored);
        exception->ContextRecord->Rip = address_;
        first = !reported_.exchange(true);
        return true; // Also handles another thread already trapped before restoration.
    }

private:
    std::uintptr_t address_{};
    unsigned char original_{};
    std::atomic<bool> reported_{};
};
} // namespace Core

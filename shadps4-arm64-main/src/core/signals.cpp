// SPDX-FileCopyrightText: Copyright 2024-2026 shadPS4 Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

#include <cstring>
#include <cstdlib>
#include "common/arch.h"
#include "common/assert.h"
#include "common/crash_reporter.h"
#include "common/decoder.h"
#include "common/signal_context.h"
#include "core/libraries/kernel/threads/exception.h"
#include "core/signals.h"
#ifdef SHADPS4_ENABLE_FEX_GUEST_CPU
#include "core/fex/fex_guest_engine.h"
#endif
#include "emulator.h"

#ifdef _WIN32
#include <windows.h>
#if defined(ARCH_X86_64)
#include "core/one_shot_probe.h"
#include "core/libraries/kernel/allocation_trace.h"
#include "core/libraries/kernel/allocation_read_history.h"
#endif
static constexpr DWORD MS_VC_EXCEPTION = 0x406D1388;
#else
#include <csignal>
#include <pthread.h>
#include <unistd.h>
#ifdef ARCH_X86_64
#include <Zydis/Formatter.h>
#endif
#endif

#ifndef _WIN32
namespace Libraries::Kernel {
void SigactionHandler(int native_signum, siginfo_t* inf, ucontext_t* raw_context);
extern std::array<OrbisKernelExceptionHandler, 32> Handlers;
} // namespace Libraries::Kernel
#endif

namespace Core {

#if defined(_WIN32) && defined(ARCH_X86_64)
static OneShotProbe statik_file_probes[5];
static constexpr const char* statik_probe_names[] = {
    "seek-failed", "buffer-refill-short", "direct-read-short", "invalid-refill-size",
    "empty-refill"
};

void InstallStatikFileProbes(u64 base) {
    const char* enabled = std::getenv("SHADPS4_TRACE_STATIK_FILE_ERRORS");
    if (!enabled || enabled[0] != '1') {
        return;
    }
    const u64 offsets[] = {0x1965ba, 0x196937, 0x196b72, 0x196b80, 0x196963};
    const unsigned char seek[] = {0x80, 0x4b, 0x08, 0x40};
    const unsigned char read[] = {0x41, 0x80, 0x4e, 0x08, 0x40};
    const unsigned char empty[] = {0x83, 0xca, 0x40};
    // Validate a second signature tying these addresses to the expected reader.
    unsigned char entry[4]{};
    const unsigned char expected_entry[] = {0x55, 0x48, 0x89, 0xe5};
    if (!ReadProbeMemory(base + 0x196820, entry, sizeof(entry)) ||
        std::memcmp(entry, expected_entry, sizeof(entry)) != 0) {
        LOG_WARNING(Debug, "Statik file probes: unsupported executable; not installed");
        return;
    }
    for (unsigned i = 0; i < 5; ++i) {
        const std::span<const unsigned char> bytes = i == 0 ? std::span<const unsigned char>(seek) :
            i == 4 ? std::span<const unsigned char>(empty) : std::span<const unsigned char>(read);
        const bool installed = statik_file_probes[i].Install(base + offsets[i], bytes);
        LOG_WARNING(Debug, "Statik file probe {}: {} at {:#x}", statik_probe_names[i],
                    installed ? "armed" : "NOT installed (byte mismatch or protection)",
                    base + offsets[i]);
    }
}

static bool HandleStatikFileProbe(EXCEPTION_POINTERS* exception) {
    for (unsigned i = 0; i < 5; ++i) {
        bool first{};
        if (!statik_file_probes[i].Resume(exception, first)) {
            continue;
        }
        if (!first) {
            return true;
        }
        const auto& c = *exception->ContextRecord;
        const auto reader = i == 0 ? c.Rbx : c.R14;
        LOG_WARNING(Debug,
                    "Statik FIRST file error {}: reader={:#x} rip={:#x} rax={:#x} "
                    "rdx={:#x} r12={:#x} r13={:#x} r14={:#x} rbp={:#x}",
                    statik_probe_names[i], reader, c.Rip, c.Rax, c.Rdx,
                    c.R12, c.R13, c.R14, c.Rbp);
        // Reader includes flags, logical position, buffer base/count and file handle.
        u64 words[20]{};
        if (ReadProbeMemory(reader, words, sizeof(words))) {
            for (unsigned j = 0; j < 20; j += 4) {
                LOG_WARNING(Debug, "Statik reader {:#x}: {:#x} {:#x} {:#x} {:#x}",
                            reader + j * 8, words[j], words[j + 1], words[j + 2], words[j + 3]);
            }
            u64 handle[8]{};
            if (ReadProbeMemory(words[19], handle, sizeof(handle))) {
                LOG_WARNING(Debug, "Statik handle {:#x}: {:#x} {:#x} {:#x} {:#x} {:#x} {:#x} {:#x} {:#x}",
                            words[19], handle[0], handle[1], handle[2], handle[3],
                            handle[4], handle[5], handle[6], handle[7]);
            }
        }
        Libraries::Kernel::WalkAllocationFrames(c.Rbp, ReadProbeMemory,
            [](unsigned depth, auto frame, auto caller) {
                LOG_WARNING(Debug, "Statik file error stack {}: frame={:#x} return={:#x}",
                            depth, frame, caller);
                if (depth < 4) {
                    u64 local[8]{};
                    if (ReadProbeMemory(frame - sizeof(local), local, sizeof(local))) {
                        LOG_WARNING(Debug, "Statik file error locals {:#x}: {:#x} {:#x} {:#x} {:#x} {:#x} {:#x} {:#x} {:#x}",
                                    frame - sizeof(local), local[0], local[1], local[2], local[3],
                                    local[4], local[5], local[6], local[7]);
                    }
                }
            });
        const auto& history = Libraries::Kernel::allocation_reads;
        const auto begin = history.count > history.records.size() ? history.count - history.records.size() : 0;
        for (auto n = begin; n < history.count; ++n) {
            const auto& r = history.records[n % history.records.size()];
            LOG_WARNING(Debug, "Statik error read {}: file={} offset={:#x} requested={:#x} returned={:#x} buffer={:#x}",
                        n, r.path, r.offset, r.requested, r.returned, r.buffer);
        }
        return true;
    }
    return false;
}
#else
void InstallStatikFileProbes(u64) {}
#endif

#if defined(_WIN32)

static LONG WINAPI SignalHandler(EXCEPTION_POINTERS* pExp) noexcept {
    const auto* signals = Signals::Instance();
    DWORD code = 0;
    PVOID address = nullptr;

    if (pExp != nullptr && pExp->ExceptionRecord != nullptr) {
        code = pExp->ExceptionRecord->ExceptionCode;
        address = pExp->ExceptionRecord->ExceptionAddress;
    }

    bool handled = false;
    switch (code) {
#if defined(ARCH_X86_64)
    case EXCEPTION_BREAKPOINT:
        handled = HandleStatikFileProbe(pExp);
        break;
#endif
    case EXCEPTION_ACCESS_VIOLATION:
        handled = signals->DispatchAccessViolation(
            pExp, reinterpret_cast<void*>(pExp->ExceptionRecord->ExceptionInformation[1]));
        break;
    case EXCEPTION_ILLEGAL_INSTRUCTION:
        handled = signals->DispatchIllegalInstruction(pExp);
        break;
    case DBG_PRINTEXCEPTION_C:
    case DBG_PRINTEXCEPTION_WIDE_C:
        // Used by OutputDebugString functions.
        return EXCEPTION_CONTINUE_EXECUTION;
    case MS_VC_EXCEPTION:
        LOG_DEBUG(Debug, "Pass MS_VC_EXCEPTION at {} to handler", address);
        return EXCEPTION_EXECUTE_HANDLER;
    default:
        break;
    }

    if (handled) {
        return EXCEPTION_CONTINUE_EXECUTION;
    }

    // Breakpoints almost certainly come from our asserts/unreachables, no need to log it again.
    if (code != EXCEPTION_BREAKPOINT) {
        LOG_CRITICAL(Debug, "Unhandled Exception code {:#x} at {}", code, address);
        // Where it came from: each caller as its module and the place in it.
        void* frames[32];
        const USHORT count = CaptureStackBackTrace(0, 32, frames, nullptr);
        for (USHORT i = 0; i < count; ++i) {
            HMODULE module = nullptr;
            char name[MAX_PATH] = "?";
            if (GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                                       GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                                   static_cast<LPCSTR>(frames[i]), &module)) {
                GetModuleFileNameA(module, name, sizeof(name));
            }
            const char* file = std::strrchr(name, '\\');
            LOG_CRITICAL(Debug, "  {} + {:#x}", file ? file + 1 : name,
                         reinterpret_cast<uintptr_t>(frames[i]) -
                             reinterpret_cast<uintptr_t>(module));
        }
        Common::Singleton<Core::Emulator>::Instance()->Shutdown();
    }

    return EXCEPTION_CONTINUE_SEARCH;
}

#else

static std::string DisassembleInstruction(void* code_address) {
    char buffer[256] = "<unable to decode>";

#ifdef ARCH_X86_64
    ZydisDecodedInstruction instruction;
    ZydisDecodedOperand operands[ZYDIS_MAX_OPERAND_COUNT];
    const auto status =
        Common::Decoder::Instance()->decodeInstruction(instruction, operands, code_address);
    if (ZYAN_SUCCESS(status)) {
        ZydisFormatter formatter;
        ZydisFormatterInit(&formatter, ZYDIS_FORMATTER_STYLE_INTEL);
        ZydisFormatterFormatInstruction(&formatter, &instruction, operands,
                                        instruction.operand_count_visible, buffer, sizeof(buffer),
                                        reinterpret_cast<u64>(code_address), ZYAN_NULL);
    }
#endif

    return buffer;
}

#ifdef SHADPS4_ENABLE_FEX_GUEST_CPU
/// Reads a word of guest memory that may not be mapped. The kernel does the copy, so a bad
/// address is an error return rather than a second fault inside the fault handler.
static bool ReadGuestWord(u64 address, u64* value) {
    static int pipe_ends[2] = {-1, -1};
    if (pipe_ends[0] < 0 && pipe(pipe_ends) != 0) {
        return false;
    }
    if (write(pipe_ends[1], reinterpret_cast<const void*>(address), sizeof(*value)) !=
        static_cast<ssize_t>(sizeof(*value))) {
        return false;
    }
    return read(pipe_ends[0], value, sizeof(*value)) == static_cast<ssize_t>(sizeof(*value));
}

/// The return addresses up the guest's call stack, found through its frame pointers.
static std::string GuestCallers(u64 frame) {
    std::string callers;
    for (int depth = 0; depth < 24 && frame != 0 && (frame & 7) == 0; ++depth) {
        u64 next = 0;
        u64 return_address = 0;
        if (!ReadGuestWord(frame, &next) || !ReadGuestWord(frame + 8, &return_address)) {
            break;
        }
        callers += fmt::format(" {:#x}", return_address);
        if (next <= frame) {
            break;
        }
        frame = next;
    }
    return callers;
}
#endif

void SignalHandler(int sig, siginfo_t* info, void* raw_context) {
    Common::ReportCrash(raw_context, sig, info);
    const auto* signals = Signals::Instance();

    auto* code_address = Common::GetRip(raw_context);

    switch (sig) {
    case SIGBUS:
    case SIGSEGV: {
#ifdef SHADPS4_ENABLE_FEX_GUEST_CPU
        if (sig == SIGBUS && ::Core::Fex::HandleGuestSignal(sig, info, raw_context)) {
            return;
        }
#endif
        const bool is_write = Common::IsWriteError(raw_context);
        if (!signals->DispatchAccessViolation(raw_context, info->si_addr)) {
            // If the guest has installed a custom signal handler, and the access violation didn't
            // come from HLE memory tracking, pass the signal on
            if (Libraries::Kernel::Handlers[Libraries::Kernel::NativeToOrbisSignal(sig)]) {
                Libraries::Kernel::SigactionHandler(sig, info,
                                                    reinterpret_cast<ucontext_t*>(raw_context));
                return;
            }
#ifdef SHADPS4_ENABLE_FEX_GUEST_CPU
            uint64_t guest_rip = 0;
            uint64_t guest_rax = 0;
            if (::Core::Fex::BachataQueryGuestRipSyscall(&guest_rip, &guest_rax)) {
                LOG_CRITICAL(Debug, "FEX guest state at fault: rip={:#x} rax={:#x}", guest_rip,
                             guest_rax);
            }
            // When the fault is inside an HLE function this tells which call it was: the first
            // arguments, and who made it.
            uint64_t gprs[16]{};
            if (::Core::Fex::BachataQueryGuestRegisters(gprs)) {
                const uint64_t rsp = gprs[4];
                uint64_t return_address = 0;
                if ((rsp & 7) == 0) {
                    ReadGuestWord(rsp, &return_address);
                }
                LOG_CRITICAL(Debug,
                             "FEX guest registers: rdi={:#x} rsi={:#x} rdx={:#x} rcx={:#x} "
                             "rsp={:#x} return address={:#x}",
                             gprs[7], gprs[6], gprs[2], gprs[1], rsp, return_address);
                LOG_CRITICAL(Debug, "FEX guest callers:{}", GuestCallers(gprs[5]));
            }
#endif
            UNREACHABLE_MSG("Unhandled access violation at code address {}: {} address {}",
                            fmt::ptr(code_address), is_write ? "Write to" : "Read from",
                            fmt::ptr(info->si_addr));
        }
        break;
    }
    case SIGILL:
        if (!signals->DispatchIllegalInstruction(raw_context)) {
            if (Libraries::Kernel::Handlers[Libraries::Kernel::NativeToOrbisSignal(sig)]) {
                Libraries::Kernel::SigactionHandler(sig, info,
                                                    reinterpret_cast<ucontext_t*>(raw_context));
                return;
            }
            UNREACHABLE_MSG("Unhandled illegal instruction at code address {}: {}",
                            fmt::ptr(code_address), DisassembleInstruction(code_address));
        }
        break;
    default:
        if (sig == SIGSLEEP) {
            // Sleep thread until signal is received again
            sigset_t sigset;
            sigemptyset(&sigset);
            sigaddset(&sigset, SIGSLEEP);
            sigwait(&sigset, &sig);
        }
        break;
    }
}

#endif

SignalDispatch::SignalDispatch() {
    Common::InitCrashReporter();
#if defined(_WIN32)
    ASSERT_MSG(handle = AddVectoredExceptionHandler(0, SignalHandler),
               "Failed to register exception handler.");
#else
    struct sigaction action{};
    action.sa_sigaction = SignalHandler;
    action.sa_flags = SA_SIGINFO | SA_ONSTACK;
    sigemptyset(&action.sa_mask);

    ASSERT_MSG(sigaction(SIGSEGV, &action, nullptr) == 0 &&
                   sigaction(SIGBUS, &action, nullptr) == 0,
               "Failed to register access violation signal handler.");
    ASSERT_MSG(sigaction(SIGILL, &action, nullptr) == 0,
               "Failed to register illegal instruction signal handler.");
    ASSERT_MSG(sigaction(SIGSLEEP, &action, nullptr) == 0,
               "Failed to register sleep signal handler.");
#endif
}

SignalDispatch::~SignalDispatch() {
#if defined(_WIN32)
    ASSERT_MSG(RemoveVectoredExceptionHandler(handle), "Failed to remove exception handler.");
#else
    struct sigaction action{};
    action.sa_handler = SIG_DFL;
    action.sa_flags = 0;
    sigemptyset(&action.sa_mask);

    ASSERT_MSG(sigaction(SIGSEGV, &action, nullptr) == 0 &&
                   sigaction(SIGBUS, &action, nullptr) == 0,
               "Failed to remove access violation signal handler.");
    ASSERT_MSG(sigaction(SIGILL, &action, nullptr) == 0,
               "Failed to remove illegal instruction signal handler.");
#endif
}

bool SignalDispatch::DispatchAccessViolation(void* context, void* fault_address) const {
    for (const auto& [handler, _] : access_violation_handlers) {
        if (handler(context, fault_address)) {
            return true;
        }
    }
    return false;
}

bool SignalDispatch::DispatchIllegalInstruction(void* context) const {
    for (const auto& [handler, _] : illegal_instruction_handlers) {
        if (handler(context)) {
            return true;
        }
    }
    return false;
}

} // namespace Core

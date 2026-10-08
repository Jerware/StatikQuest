#include <cassert>
#include <cstdio>
#include "core/one_shot_probe.h"

Core::OneShotProbe probe;
unsigned hits = 0;
LONG WINAPI Handler(EXCEPTION_POINTERS* e) {
    bool first{};
    if (!probe.Resume(e, first)) return EXCEPTION_CONTINUE_SEARCH;
    if (first) ++hits;
    return EXCEPTION_CONTINUE_EXECUTION;
}

int main() {
    // mov eax,123; ret. Test on an RX page, exactly as guest code may be mapped.
    const unsigned char code[] = {0xb8, 123, 0, 0, 0, 0xc3};
    auto* memory = VirtualAlloc(nullptr, 4096, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    assert(memory);
    std::memcpy(memory, code, sizeof(code));
    DWORD old{};
    assert(VirtualProtect(memory, 4096, PAGE_EXECUTE_READ, &old));
    const auto address = reinterpret_cast<std::uintptr_t>(memory);
    Core::OneShotProbe mismatch;
    const unsigned char wrong[] = {0x90};
    assert(!mismatch.Install(address, wrong));
    assert(!mismatch.Install(1, code));
    assert(probe.Install(address, code));
    assert(!probe.Install(address, code));
    auto* handler = AddVectoredExceptionHandler(1, Handler);
    assert(handler);
    const auto fn = reinterpret_cast<int (*)()>(memory);
    assert(fn() == 123 && hits == 1);
    assert(fn() == 123 && hits == 1);
    assert(std::memcmp(memory, code, sizeof(code)) == 0);
    MEMORY_BASIC_INFORMATION info{};
    assert(VirtualQuery(memory, &info, sizeof(info)));
    assert(info.Protect == PAGE_EXECUTE_READ);
    bool first{};
    assert(!probe.Resume(nullptr, first));
    EXCEPTION_RECORD record{};
    CONTEXT context{};
    EXCEPTION_POINTERS exception{&record, &context};
    record.ExceptionCode = EXCEPTION_BREAKPOINT;
    record.ExceptionAddress = reinterpret_cast<void*>(address + 1);
    assert(!probe.Resume(&exception, first));
    // A second thread could already have trapped at the same byte before restore.
    record.ExceptionAddress = memory;
    assert(probe.Resume(&exception, first) && !first && context.Rip == address);
    assert(RemoveVectoredExceptionHandler(handler));
    assert(VirtualFree(memory, 0, MEM_RELEASE));
    std::puts("One-shot probe tests passed: exact bytes, original instruction, RX protection, one capture.");
}

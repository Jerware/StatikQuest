#pragma once
#ifdef _WIN32
#include <algorithm>
#include <array>
#include <chrono>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <string>
#include <windows.h>

namespace Vulkan {
// One-shot CPU-visible snapshot. No GPU waits, guest writes, or unchecked reads.
// Missing pages are zero-filled in the file AND explicitly recorded in the manifest.
class GpuFailureCapture {
public:
    explicit GpuFailureCapture(const std::filesystem::path& parent, size_t budget = 128 * 1024 * 1024)
        : remaining(budget) {
        const auto stamp = std::chrono::system_clock::now().time_since_epoch().count();
        directory = parent / ("gpu_failure_" + std::to_string(stamp));
        std::error_code error;
        std::filesystem::create_directories(directory, error);
        if (!error) manifest.open(directory / "manifest.txt");
        Note("Capture build: " __DATE__ " " __TIME__);
        Note("CPU-visible snapshot only; GPU-dirty buffers may differ. No textures/readback captured.");
        Note("Per-region limit 4 MiB; total payload limit bytes=" + std::to_string(budget) +
             ". Truncation and unreadable pages are recorded.");
    }
    void Note(const std::string& text) { manifest << text << '\n'; manifest.flush(); }
    void Save(const std::string& name, const void* address, size_t requested) {
        if (!manifest) return;
        const size_t bytes = (std::min)({requested, size_t(4 * 1024 * 1024), remaining});
        const auto base = reinterpret_cast<uintptr_t>(address);
        Note(name + " address=" + std::to_string(base) + " requested=" + std::to_string(requested) +
             " captured=" + std::to_string(bytes));
        std::ofstream out(directory / (name + ".bin"), std::ios::binary);
        if (!out) { Note(name + " FILE_OPEN_FAILED"); return; }
        std::array<char, 4096> page{};
        size_t offset = 0;
        while (offset < bytes) {
            const size_t count = (std::min)(bytes - offset, page.size() - ((base + offset) & 4095));
            page.fill(0);
            SIZE_T copied = 0;
            if (!ReadProcessMemory(GetCurrentProcess(), reinterpret_cast<const void*>(base + offset),
                                   page.data(), count, &copied) || copied != count) {
                Note(name + " UNREADABLE offset=" + std::to_string(offset) + " bytes=" +
                     std::to_string(count) + " copied=" + std::to_string(copied));
            }
            out.write(page.data(), count);
            if (!out) { Note(name + " FILE_WRITE_FAILED offset=" + std::to_string(offset)); break; }
            offset += count;
        }
        remaining -= offset;
        out.close();
        if (!out) Note(name + " FILE_CLOSE_FAILED");
    }
    std::filesystem::path directory;
private:
    std::ofstream manifest;
    size_t remaining = 128 * 1024 * 1024;
};
}
#endif

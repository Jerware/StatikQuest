#include <cassert>
#include <iterator>
#include "video_core/renderer_vulkan/gpu_failure_capture.h"

int main() {
    auto* memory = static_cast<unsigned char*>(VirtualAlloc(nullptr, 8192, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE));
    assert(memory);
    for (size_t i = 0; i < 4096; ++i) memory[i] = static_cast<unsigned char>(i);
    DWORD old{};
    assert(VirtualProtect(memory + 4096, 4096, PAGE_NOACCESS, &old));
    std::filesystem::path directory;
    {
        Vulkan::GpuFailureCapture capture{std::filesystem::temp_directory_path()};
        directory = capture.directory;
        capture.Save("page_test", memory, 8192);
        capture.Note("TEST_COMPLETE");
    }
    std::ifstream payload(directory / "page_test.bin", std::ios::binary);
    const std::string bytes{std::istreambuf_iterator<char>{payload}, {}};
    assert(bytes.size() == 8192);
    for (size_t i = 0; i < 4096; ++i) assert(static_cast<unsigned char>(bytes[i]) == static_cast<unsigned char>(i));
    for (size_t i = 4096; i < 8192; ++i) assert(bytes[i] == 0);
    std::ifstream manifest(directory / "manifest.txt");
    const std::string text{std::istreambuf_iterator<char>{manifest}, {}};
    assert(text.find("UNREADABLE offset=4096") != std::string::npos);
    assert(text.find("TEST_COMPLETE") != std::string::npos);
    MEMORY_BASIC_INFORMATION info{};
    assert(VirtualQuery(memory + 4096, &info, sizeof(info)));
    assert(info.Protect == PAGE_NOACCESS);
    VirtualFree(memory, 0, MEM_RELEASE);
}

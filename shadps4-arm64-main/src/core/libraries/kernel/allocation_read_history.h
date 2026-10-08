#pragma once
#include <array>
#include <cstdint>
#include <string>

namespace Libraries::Kernel {
struct AllocationReadRecord {
    std::string path;
    std::uint64_t offset{}, requested{}, returned{}, buffer{};
    std::array<std::uint32_t, 4> prefix{};
};
// Loading and allocation occur on the same guest thread. No disk logging or
// cross-thread lock on the read path; dump this bounded history only on demand.
struct AllocationReadHistory {
    std::array<AllocationReadRecord, 32> records;
    std::uint64_t count{};
};
inline thread_local AllocationReadHistory allocation_reads;
}

// SPDX-License-Identifier: GPL-2.0-or-later

#include "log.h"

#include <cstdarg>
#include <cstdio>
#include <ctime>
#include <mutex>
#include <string>

namespace {

std::mutex g_mutex;
FILE* g_file = nullptr;

} // namespace

void SetLogFile(const char* path) {
    std::scoped_lock lock{g_mutex};
    if (g_file != nullptr) {
        std::fclose(g_file);
    }
    // "e": the emulator process must not inherit the file.
    g_file = std::fopen(path, "we");
}

void HostLog(int priority, const char* format, ...) {
    va_list args;
    va_start(args, format);
    va_list measure;
    va_copy(measure, args);
    const int length = std::vsnprintf(nullptr, 0, format, measure);
    va_end(measure);
    std::string text(length > 0 ? static_cast<size_t>(length) : 0, '\0');
    if (length > 0) {
        std::vsnprintf(text.data(), text.size() + 1, format, args);
    }
    va_end(args);

    __android_log_write(priority, LOG_TAG, text.c_str());

    std::scoped_lock lock{g_mutex};
    if (g_file == nullptr) {
        return;
    }
    timespec now{};
    clock_gettime(CLOCK_REALTIME, &now);
    tm local{};
    localtime_r(&now.tv_sec, &local);
    const char level = priority >= ANDROID_LOG_ERROR ? 'E' : priority >= ANDROID_LOG_WARN ? 'W' : 'I';
    std::fprintf(g_file, "%02d:%02d:%02d.%03ld %c %s\n", local.tm_hour, local.tm_min, local.tm_sec,
                 now.tv_nsec / 1'000'000, level, text.c_str());
    // A session can end by the app being killed.
    std::fflush(g_file);
}

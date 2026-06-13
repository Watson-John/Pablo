// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.

#include "dedup/log.h"

#include <atomic>
#include <cstdio>
#include <mutex>

namespace dedup {
namespace {
std::atomic<LogLevel> g_level{LogLevel::kInfo};
std::mutex g_mu;

const char* tag(LogLevel l) {
    switch (l) {
        case LogLevel::kDebug: return "debug";
        case LogLevel::kInfo:  return "info ";
        case LogLevel::kWarn:  return "WARN ";
        case LogLevel::kError: return "ERROR";
    }
    return "?????";
}
}  // namespace

void set_log_level(LogLevel level) { g_level.store(level, std::memory_order_relaxed); }
LogLevel log_level() { return g_level.load(std::memory_order_relaxed); }

void log_line(LogLevel level, const std::string& msg) {
    if (level < log_level()) return;
    std::lock_guard<std::mutex> lk(g_mu);
    std::fprintf(stderr, "[%s] %s\n", tag(level), msg.c_str());
}

}  // namespace dedup

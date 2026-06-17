// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// Tiny leveled logger. Thread-safe (serialized on a single mutex). No
// dependencies — intentionally minimal for a CLI tool.

#pragma once

#include <sstream>
#include <string>

namespace dedup {

enum class LogLevel { kDebug = 0, kInfo = 1, kWarn = 2, kError = 3 };

// Process-wide minimum level (default kInfo). Set from --verbose / --quiet.
void set_log_level(LogLevel level);
LogLevel log_level();

// Emit one already-formatted line at `level` (newline appended).
void log_line(LogLevel level, const std::string& msg);

namespace detail {
// Stream builder so call sites can write: LOG_INFO("scanned " << n << " files").
struct LogStream {
    LogLevel level;
    std::ostringstream os;
    explicit LogStream(LogLevel l) : level(l) {}
    ~LogStream() { log_line(level, os.str()); }
};
}  // namespace detail

}  // namespace dedup

#define DEDUP_LOG(lvl) \
    ::dedup::detail::LogStream(lvl).os
#define LOG_DEBUG(expr) do { if (::dedup::log_level() <= ::dedup::LogLevel::kDebug) DEDUP_LOG(::dedup::LogLevel::kDebug) << expr; } while (0)
#define LOG_INFO(expr)  do { if (::dedup::log_level() <= ::dedup::LogLevel::kInfo)  DEDUP_LOG(::dedup::LogLevel::kInfo)  << expr; } while (0)
#define LOG_WARN(expr)  do { if (::dedup::log_level() <= ::dedup::LogLevel::kWarn)  DEDUP_LOG(::dedup::LogLevel::kWarn)  << expr; } while (0)
#define LOG_ERROR(expr) do { DEDUP_LOG(::dedup::LogLevel::kError) << expr; } while (0)

// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// Tiny header-only logging facility. Real logging belongs to the engine via
// PHOTO_EVT_LOG events in later milestones; this is just enough to print
// during bring-up.

#pragma once

#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <string>

#include "photo_core.h"

namespace photo::log {

inline std::atomic<int> level{PHOTO_LOG_INFO};

inline void set_level(int lvl) { level.store(lvl, std::memory_order_relaxed); }

inline const char* level_tag(int lvl) {
    switch (lvl) {
        case PHOTO_LOG_TRACE: return "TRACE";
        case PHOTO_LOG_DEBUG: return "DEBUG";
        case PHOTO_LOG_INFO:  return "INFO";
        case PHOTO_LOG_WARN:  return "WARN";
        case PHOTO_LOG_ERROR: return "ERROR";
        default:              return "?";
    }
}

#define PHOTO_LOGF(lvl, ...) do {                                    \
    if ((lvl) >= ::photo::log::level.load(std::memory_order_relaxed)) { \
        std::fprintf(stderr, "[photo_core/%s] ",                     \
                     ::photo::log::level_tag(lvl));                  \
        std::fprintf(stderr, __VA_ARGS__);                           \
        std::fprintf(stderr, "\n");                                  \
    }                                                                \
} while (0)

}  // namespace photo::log

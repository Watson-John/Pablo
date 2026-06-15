// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.

#include "engine.h"

#include <filesystem>
#include <thread>

#include "util/log.h"
#include "thumb/thumb_cache.h"

namespace photo {

namespace fs = std::filesystem;

namespace {

constexpr uint64_t kDefaultMemoryBudget = 256ull * 1024 * 1024;        // 256 MiB
constexpr uint64_t kDefaultDiskBudget   = 16ull * 1024 * 1024 * 1024;  // 16 GiB

bool ensure_directory(const fs::path& p) {
    std::error_code ec;
    if (fs::exists(p, ec)) {
        return fs::is_directory(p, ec);
    }
    fs::create_directories(p, ec);
    return !ec;
}

}  // namespace

std::unique_ptr<Engine> Engine::create(const photo_config_t& cfg) {
    if (!cfg.catalog_path_utf8 || !*cfg.catalog_path_utf8) {
        PHOTO_LOGF(PHOTO_LOG_ERROR, "catalog_path_utf8 required");
        return nullptr;
    }
    if (!cfg.cache_path_utf8 || !*cfg.cache_path_utf8) {
        PHOTO_LOGF(PHOTO_LOG_ERROR, "cache_path_utf8 required");
        return nullptr;
    }

    fs::path catalog_path = fs::path(cfg.catalog_path_utf8);
    fs::path cache_path   = fs::path(cfg.cache_path_utf8);
    fs::path models_path  = cfg.models_path_utf8
                               ? fs::path(cfg.models_path_utf8)
                               : fs::path{};

    // M3 will refuse network filesystems for the catalog. M1 just ensures
    // the parent directory of the catalog and the cache directory exist.
    if (auto parent = catalog_path.parent_path(); !parent.empty()) {
        if (!ensure_directory(parent)) {
            PHOTO_LOGF(PHOTO_LOG_ERROR,
                       "catalog parent dir not writable: %s",
                       parent.string().c_str());
            return nullptr;
        }
    }
    if (!ensure_directory(cache_path)) {
        PHOTO_LOGF(PHOTO_LOG_ERROR,
                   "cache dir not writable: %s", cache_path.string().c_str());
        return nullptr;
    }

    uint64_t mem = cfg.memory_budget_bytes ? cfg.memory_budget_bytes
                                           : kDefaultMemoryBudget;
    uint64_t dsk = cfg.disk_budget_bytes ? cfg.disk_budget_bytes
                                         : kDefaultDiskBudget;

    uint32_t decode_threads = cfg.decode_threads;
    if (decode_threads == 0) {
        unsigned int hc = std::thread::hardware_concurrency();
        decode_threads = hc > 2 ? hc - 1 : 2;
    }

    if (cfg.log_level >= PHOTO_LOG_TRACE && cfg.log_level <= PHOTO_LOG_ERROR) {
        log::set_level(static_cast<int>(cfg.log_level));
    }

    return std::unique_ptr<Engine>(
        new Engine(std::move(catalog_path),
                   std::move(cache_path),
                   std::move(models_path),
                   mem, dsk, decode_threads));
}

Engine::Engine(fs::path catalog_path,
               fs::path cache_path,
               fs::path models_path,
               uint64_t memory_budget,
               uint64_t disk_budget,
               uint32_t decode_threads)
    : jobs_(decode_threads),
      thumbs_(&slots_, &events_, &jobs_),
#ifdef PHOTO_HAVE_FACES
      // Pass the path parameters by lvalue (copied) so the catalog_path_/
      // models_path_ members below can still move-from them.
      faces_(&events_, &jobs_, models_path, catalog_path),
#endif
      catalog_path_(std::move(catalog_path)),
      cache_path_(std::move(cache_path)),
      models_path_(std::move(models_path)),
      memory_budget_(memory_budget),
      disk_budget_(disk_budget) {
    PHOTO_LOGF(PHOTO_LOG_INFO,
               "engine created (cache=%s mem=%llu disk=%llu workers=%u)",
               cache_path_.string().c_str(),
               static_cast<unsigned long long>(memory_budget_),
               static_cast<unsigned long long>(disk_budget_),
               decode_threads);

    cache_ = std::make_unique<ThumbCache>(cache_path_);
    thumbs_.set_cache(cache_.get());
    PHOTO_LOGF(PHOTO_LOG_INFO, "thumb cache %s (%zu entries)",
               cache_->ok() ? "ready" : "DISABLED",
               cache_->entry_count());
}

Engine::~Engine() {
    PHOTO_LOGF(PHOTO_LOG_INFO, "engine destroyed (slots=%zu)", slots_.size());
}

}  // namespace photo

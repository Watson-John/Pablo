// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.

#include "engine.h"

#include <filesystem>
#include <thread>

#ifdef PHOTO_HAVE_SQLITE
#include <cctype>
#include <chrono>
#include <unordered_map>
#include <unordered_set>

#include "exif/exif.h"
#endif

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

    cache_ = std::make_unique<ThumbCache>(cache_path_, disk_budget_);
    thumbs_.set_cache(cache_.get());
    PHOTO_LOGF(PHOTO_LOG_INFO, "thumb cache %s (%zu entries)",
               cache_->ok() ? "ready" : "DISABLED",
               cache_->entry_count());

#ifdef PHOTO_HAVE_SQLITE
    // Open the durable asset catalog. A failure here degrades to "no catalog"
    // (import/rescan report unavailable) rather than bricking the engine.
    try {
        catalog_ = std::make_unique<catalog::Catalog>(catalog_path_.string());
        PHOTO_LOGF(PHOTO_LOG_INFO, "catalog ready (%lld assets)",
                   static_cast<long long>(catalog_->count()));
    } catch (const std::exception& e) {
        catalog_.reset();
        PHOTO_LOGF(PHOTO_LOG_ERROR, "catalog DISABLED: %s", e.what());
    }
#endif
}

Engine::~Engine() {
    PHOTO_LOGF(PHOTO_LOG_INFO, "engine destroyed (slots=%zu)", slots_.size());
}

#ifdef PHOTO_HAVE_SQLITE

namespace {

const std::unordered_set<std::string>& image_exts() {
    // Mirrors pablo/lib/data/library.dart's _kImageExts so the catalog and the
    // Dart gallery agree on what counts as an importable image.
    static const std::unordered_set<std::string> kExts = {
        ".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp"};
    return kExts;
}

std::string lower_ext(const fs::path& p) {
    std::string ext = p.extension().string();
    for (char& c : ext) c = static_cast<char>(std::tolower((unsigned char)c));
    return ext;
}

bool is_image(const fs::path& p) { return image_exts().count(lower_ext(p)) > 0; }

// "jpeg" / "png" / … from the extension; jpg is normalized to jpeg.
std::string format_of(const fs::path& p) {
    std::string ext = lower_ext(p);
    if (ext.empty()) return {};
    ext.erase(0, 1);  // drop the dot
    return ext == "jpg" ? "jpeg" : ext;
}

int64_t now_ns() {
    return std::chrono::duration_cast<std::chrono::nanoseconds>(
               std::chrono::system_clock::now().time_since_epoch())
        .count();
}

// last-write-time as ns. The epoch is the filesystem clock's, not Unix — fine
// because it is only compared against itself for change detection.
int64_t mtime_ns_of(const fs::path& p) {
    std::error_code ec;
    auto t = fs::last_write_time(p, ec);
    if (ec) return 0;
    return std::chrono::duration_cast<std::chrono::nanoseconds>(t.time_since_epoch())
        .count();
}

}  // namespace

void Engine::run_import(uint64_t request_id, std::vector<std::string> roots,
                        bool prune) {
    // Serialize import/rescan jobs (see import_mu_): the diff window between the
    // file_stats() snapshot and the upsert/prune must not race another job.
    std::lock_guard<std::mutex> import_lk(import_mu_);
    auto emit = [&](uint32_t kind, int32_t status, uint64_t done, uint64_t total) {
        photo_event_t ev{};
        ev.kind = kind;
        ev.status = status;
        ev.request_id = request_id;
        ev.aux64 = done;
        ev.aux64_b = total;
        events_.push(ev);
    };

    if (!catalog_) {
        emit(PHOTO_EVT_IMPORT_COMPLETE, PHOTO_STATUS_BAD_STATE, 0, 0);
        return;
    }

    // 1. Enumerate image files across every root (recursively), capturing each
    //    file's size + mtime during the walk. Done WITHOUT the catalog lock so a
    //    large library's walk never blocks concurrent reads (list_assets,
    //    path_for_asset) for the walk's whole duration.
    struct Scanned { fs::path path; int64_t size; int64_t mtime_ns; };
    std::vector<Scanned> files;
    std::error_code ec;
    auto add_file = [&](const fs::path& p) {
        std::error_code sec;
        const auto sz = static_cast<int64_t>(fs::file_size(p, sec));
        files.push_back({p, sec ? 0 : sz, mtime_ns_of(p)});
    };
    for (const auto& root : roots) {
        fs::path rp(root);
        if (!fs::exists(rp, ec)) continue;
        if (fs::is_regular_file(rp, ec)) {
            if (is_image(rp)) add_file(rp);
            continue;
        }
        for (fs::recursive_directory_iterator it(
                 rp, fs::directory_options::skip_permission_denied, ec),
             end;
             it != end; it.increment(ec)) {
            if (ec) { ec.clear(); continue; }
            if (it->is_regular_file(ec) && is_image(it->path())) add_file(it->path());
        }
    }

    const uint64_t total = files.size();
    const int64_t import_time = now_ns();

    // 2. Snapshot existing (path → size, mtime_ns) under the lock, briefly.
    std::unordered_map<std::string, catalog::Catalog::FileStat> existing;
    {
        std::lock_guard<std::mutex> lk(catalog_mu_);
        existing = catalog_->file_stats();
    }

    // 3. Diff (no lock): skip files whose size+mtime are unchanged — the win is
    //    skipping the expensive exif::extract on the unchanged majority. Stage
    //    the rest for upsert. Progress is reported over all files (skipped ones
    //    are instant; extracted ones carry the cost).
    struct Pending { catalog::AssetRecord rec; exif::AssetMetadata meta; };
    std::vector<Pending> pending;
    pending.reserve(files.size());
    uint64_t added = 0, updated = 0, skipped = 0, removed = 0, processed = 0;
    for (const auto& f : files) {
        const std::string path = f.path.string();
        const auto it = existing.find(path);
        const bool is_new = (it == existing.end());
        if (!is_new && it->second.size == f.size &&
            it->second.mtime_ns == f.mtime_ns) {
            ++skipped;
        } else {
            catalog::AssetRecord r;
            r.path = path;
            r.folder = f.path.parent_path().string();
            r.filename = f.path.filename().string();
            r.size = f.size;
            r.mtime_ns = f.mtime_ns;
            r.format = format_of(f.path);
            r.import_time = import_time;  // ignored by upsert on conflict
            // EXIF read (no-op without libexif): fills dimensions/orientation on
            // the asset row and the searchable asset_metadata row.
            exif::AssetMetadata meta = exif::extract(path);
            r.width = meta.width;
            r.height = meta.height;
            r.orientation = meta.orientation;
            pending.push_back({std::move(r), std::move(meta)});
            if (is_new) ++added; else ++updated;
        }
        ++processed;
        if ((processed % 64) == 0 || processed == total)
            emit(PHOTO_EVT_IMPORT_PROGRESS, PHOTO_STATUS_OK, processed, total);
    }

    // 4. Apply the staged upserts under the lock (fast — no exif here), then
    //    (rescan only) prune assets whose backing file is gone. Assets imported
    //    under a hidden folder are re-forced hidden (upsert preserves the user
    //    `hidden` field on conflict, so new/changed rows need the rule applied).
    {
        std::lock_guard<std::mutex> lk(catalog_mu_);
        const std::vector<std::string> hidden_dirs = catalog_->hidden_folders();
        auto under_hidden = [&](const std::string& path) {
            for (const auto& h : hidden_dirs) {
                if (path.size() >= h.size() && !h.empty() &&
                    path.compare(0, h.size(), h) == 0 &&
                    (path.size() == h.size() || path[h.size()] == '/' ||
                     path[h.size()] == '\\'))
                    return true;
            }
            return false;
        };
        for (auto& p : pending) {
            try {
                catalog_->upsert_asset(p.rec);
                catalog_->upsert_metadata(p.rec.id, p.meta);
                if (!hidden_dirs.empty() && under_hidden(p.rec.path))
                    catalog_->set_hidden(p.rec.id, true);
            } catch (const std::exception& e) {
                PHOTO_LOGF(PHOTO_LOG_WARN, "import: skip %s (%s)",
                           p.rec.path.c_str(), e.what());
            }
        }
        if (prune) {
            for (const auto& a : catalog_->list_assets(/*include_hidden=*/true)) {
                std::error_code pec;
                if (!fs::exists(fs::path(a.path), pec)) {
                    catalog_->remove_asset(a.id);
                    ++removed;
                }
            }
        }
    }

    // 5. Completion event carries the rescan summary so the UI can report it:
    //    aux64 = added, aux64_b = updated, _reserved[0] = skipped,
    //    _reserved[1] = removed (see photo_core.h PHOTO_EVT_IMPORT_COMPLETE).
    photo_event_t done_ev{};
    done_ev.kind = PHOTO_EVT_IMPORT_COMPLETE;
    done_ev.status = PHOTO_STATUS_OK;
    done_ev.request_id = request_id;
    done_ev.aux64 = added;
    done_ev.aux64_b = updated;
    done_ev._reserved[0] = static_cast<uint32_t>(skipped);
    done_ev._reserved[1] = static_cast<uint32_t>(removed);
    events_.push(done_ev);
}

uint64_t Engine::import_path(const std::string& path) {
    if (!catalog_) return 0;
    {
        std::lock_guard<std::mutex> lk(catalog_mu_);
        try { catalog_->add_import_root(path); } catch (...) {}
    }
    const uint64_t req = next_import_id_.fetch_add(1, std::memory_order_relaxed);
    jobs_.submit(PHOTO_PRIORITY_IDLE,
                 [this, req, path] { run_import(req, {path}, /*prune=*/false); });
    return req;
}

uint64_t Engine::rescan() {
    if (!catalog_) return 0;
    std::vector<std::string> roots;
    {
        std::lock_guard<std::mutex> lk(catalog_mu_);
        roots = catalog_->import_roots();
    }
    const uint64_t req = next_import_id_.fetch_add(1, std::memory_order_relaxed);
    jobs_.submit(PHOTO_PRIORITY_IDLE,
                 [this, req, roots] { run_import(req, roots, /*prune=*/true); });
    return req;
}

std::vector<catalog::AssetRecord> Engine::list_assets() const {
    if (!catalog_) return {};
    std::lock_guard<std::mutex> lk(catalog_mu_);
    return catalog_->list_assets(/*include_hidden=*/false);
}

std::string Engine::path_for_asset(int64_t asset_id) const {
    if (!catalog_) return {};
    std::lock_guard<std::mutex> lk(catalog_mu_);
    return catalog_->path_by_id(asset_id);
}

std::optional<exif::AssetMetadata> Engine::asset_metadata(int64_t asset_id) const {
    if (!catalog_) return std::nullopt;
    std::lock_guard<std::mutex> lk(catalog_mu_);
    return catalog_->get_metadata(asset_id);
}

std::vector<catalog::Catalog::GeoPoint> Engine::list_geotagged() const {
    if (!catalog_) return {};
    std::lock_guard<std::mutex> lk(catalog_mu_);
    return catalog_->geotagged();
}

int64_t Engine::create_album(const std::string& name) {
    if (!catalog_) return 0;
    std::lock_guard<std::mutex> lk(catalog_mu_);
    return catalog_->create_album(name, now_ns());
}

void Engine::rename_album(int64_t album_id, const std::string& name) {
    if (!catalog_) return;
    std::lock_guard<std::mutex> lk(catalog_mu_);
    catalog_->rename_album(album_id, name);
}

void Engine::delete_album(int64_t album_id) {
    if (!catalog_) return;
    std::lock_guard<std::mutex> lk(catalog_mu_);
    catalog_->delete_album(album_id);
}

void Engine::set_album_cover(int64_t album_id, int64_t cover_asset_id) {
    if (!catalog_) return;
    std::lock_guard<std::mutex> lk(catalog_mu_);
    catalog_->set_album_cover(album_id, cover_asset_id);
}

void Engine::add_to_album(int64_t album_id, int64_t asset_id) {
    if (!catalog_) return;
    std::lock_guard<std::mutex> lk(catalog_mu_);
    catalog_->add_to_album(album_id, asset_id);
}

void Engine::remove_from_album(int64_t album_id, int64_t asset_id) {
    if (!catalog_) return;
    std::lock_guard<std::mutex> lk(catalog_mu_);
    catalog_->remove_from_album(album_id, asset_id);
}

std::vector<catalog::Catalog::AlbumRecord> Engine::list_albums() const {
    if (!catalog_) return {};
    std::lock_guard<std::mutex> lk(catalog_mu_);
    return catalog_->list_albums();
}

std::vector<int64_t> Engine::album_members(int64_t album_id) const {
    if (!catalog_) return {};
    std::lock_guard<std::mutex> lk(catalog_mu_);
    return catalog_->album_members(album_id);
}

void Engine::set_starred(int64_t asset_id, bool v) {
    if (!catalog_) return;
    std::lock_guard<std::mutex> lk(catalog_mu_);
    catalog_->set_starred(asset_id, v);
}

void Engine::set_rating(int64_t asset_id, int32_t v) {
    if (!catalog_) return;
    std::lock_guard<std::mutex> lk(catalog_mu_);
    catalog_->set_rating(asset_id, v);
}

void Engine::set_caption(int64_t asset_id, const std::string& v) {
    if (!catalog_) return;
    std::lock_guard<std::mutex> lk(catalog_mu_);
    catalog_->set_caption(asset_id, v);
}

void Engine::set_hidden(int64_t asset_id, bool v) {
    if (!catalog_) return;
    std::lock_guard<std::mutex> lk(catalog_mu_);
    catalog_->set_hidden(asset_id, v);
}

void Engine::set_folder_hidden(const std::string& path, bool v) {
    if (!catalog_) return;
    std::lock_guard<std::mutex> lk(catalog_mu_);
    if (v) catalog_->add_hidden_folder(path);
    else   catalog_->remove_hidden_folder(path);
    catalog_->set_assets_hidden_under(path, v);
}

std::vector<std::string> Engine::hidden_folders() const {
    if (!catalog_) return {};
    std::lock_guard<std::mutex> lk(catalog_mu_);
    return catalog_->hidden_folders();
}

std::vector<std::string> Engine::hidden_asset_paths() const {
    if (!catalog_) return {};
    std::lock_guard<std::mutex> lk(catalog_mu_);
    return catalog_->hidden_asset_paths();
}

std::vector<int64_t> Engine::recent_assets(int limit) const {
    if (!catalog_) return {};
    std::lock_guard<std::mutex> lk(catalog_mu_);
    return catalog_->recent_assets(limit);
}

std::vector<int64_t> Engine::starred_assets() const {
    if (!catalog_) return {};
    std::lock_guard<std::mutex> lk(catalog_mu_);
    return catalog_->starred_assets();
}

catalog::Catalog::Stats Engine::catalog_stats() const {
    if (!catalog_) return {};
    std::lock_guard<std::mutex> lk(catalog_mu_);
    return catalog_->stats();
}

uint64_t Engine::compact_catalog() {
    if (!catalog_) return 0;
    const uint64_t req = next_import_id_.fetch_add(1, std::memory_order_relaxed);
    jobs_.submit(PHOTO_PRIORITY_IDLE, [this, req] {
        int32_t status = PHOTO_STATUS_OK;
        {
            std::lock_guard<std::mutex> lk(catalog_mu_);
            try {
                catalog_->compact();
            } catch (const std::exception& e) {
                PHOTO_LOGF(PHOTO_LOG_WARN, "compact: %s", e.what());
                status = PHOTO_STATUS_INTERNAL;
            }
        }
        photo_event_t ev{};
        ev.kind = PHOTO_EVT_MAINTENANCE_COMPLETE;
        ev.status = status;
        ev.request_id = req;
        events_.push(ev);
    });
    return req;
}

void Engine::compact_catalog_sync() {
    if (!catalog_) return;
    std::lock_guard<std::mutex> lk(catalog_mu_);
    catalog_->compact();
}

void Engine::catalog_checkpoint() {
    if (!catalog_) return;
    std::lock_guard<std::mutex> lk(catalog_mu_);
    catalog_->checkpoint();
}

int64_t Engine::rebase_paths(const std::string& old_prefix,
                             const std::string& new_prefix) {
    if (!catalog_) return 0;
    std::error_code ec;
    if (!fs::exists(fs::path(new_prefix), ec)) return -1;  // new root must exist
    std::lock_guard<std::mutex> lk(catalog_mu_);
    return catalog_->rebase_paths(old_prefix, new_prefix);
}

void Engine::add_tag(int64_t asset_id, const std::string& tag) {
    if (!catalog_) return;
    std::lock_guard<std::mutex> lk(catalog_mu_);
    catalog_->add_tag(asset_id, tag);
}

void Engine::remove_tag(int64_t asset_id, const std::string& tag) {
    if (!catalog_) return;
    std::lock_guard<std::mutex> lk(catalog_mu_);
    catalog_->remove_tag(asset_id, tag);
}

std::vector<std::string> Engine::tags_for_asset(int64_t asset_id) const {
    if (!catalog_) return {};
    std::lock_guard<std::mutex> lk(catalog_mu_);
    return catalog_->tags_for_asset(asset_id);
}

std::optional<catalog::AssetRecord> Engine::asset(int64_t asset_id) const {
    if (!catalog_) return std::nullopt;
    std::lock_guard<std::mutex> lk(catalog_mu_);
    return catalog_->asset_by_id(asset_id);
}

#endif  // PHOTO_HAVE_SQLITE

}  // namespace photo

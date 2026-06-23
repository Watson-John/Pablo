// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.

#include "engine.h"

#include <filesystem>
#include <thread>

#ifdef PHOTO_HAVE_SQLITE
#include <cctype>
#include <chrono>
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

    // 1. Enumerate image files across every root (recursively).
    std::vector<fs::path> files;
    std::error_code ec;
    for (const auto& root : roots) {
        fs::path rp(root);
        if (!fs::exists(rp, ec)) continue;
        if (fs::is_regular_file(rp, ec)) {
            if (is_image(rp)) files.push_back(rp);
            continue;
        }
        for (fs::recursive_directory_iterator it(
                 rp, fs::directory_options::skip_permission_denied, ec),
             end;
             it != end; it.increment(ec)) {
            if (ec) { ec.clear(); continue; }
            if (it->is_regular_file(ec) && is_image(it->path()))
                files.push_back(it->path());
        }
    }

    const uint64_t total = files.size();
    const int64_t import_time = now_ns();
    uint64_t done = 0;

    std::lock_guard<std::mutex> lk(catalog_mu_);

    // 2. Upsert every file (with its EXIF metadata); report progress every 64
    //    and at the end.
    for (const auto& f : files) {
        catalog::AssetRecord r;
        r.path = f.string();
        r.folder = f.parent_path().string();
        r.filename = f.filename().string();
        std::error_code fec;
        r.size = static_cast<int64_t>(fs::file_size(f, fec));
        r.mtime_ns = mtime_ns_of(f);
        r.format = format_of(f);
        r.import_time = import_time;
        // EXIF read (no-op without libexif): fills dimensions/orientation on the
        // asset row and the searchable asset_metadata row.
        exif::AssetMetadata meta = exif::extract(r.path);
        r.width = meta.width;
        r.height = meta.height;
        r.orientation = meta.orientation;
        try {
            catalog_->upsert_asset(r);
            catalog_->upsert_metadata(r.id, meta);
        } catch (const std::exception& e) {
            PHOTO_LOGF(PHOTO_LOG_WARN, "import: skip %s (%s)",
                       r.path.c_str(), e.what());
        }
        ++done;
        if ((done % 64) == 0 || done == total)
            emit(PHOTO_EVT_IMPORT_PROGRESS, PHOTO_STATUS_OK, done, total);
    }

    // 3. rescan only: drop assets whose backing file is gone.
    if (prune) {
        for (const auto& a : catalog_->list_assets(/*include_hidden=*/true)) {
            std::error_code pec;
            if (!fs::exists(fs::path(a.path), pec)) catalog_->remove_asset(a.id);
        }
    }

    emit(PHOTO_EVT_IMPORT_COMPLETE, PHOTO_STATUS_OK, done, total);
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

#endif  // PHOTO_HAVE_SQLITE

}  // namespace photo

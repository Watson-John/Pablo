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
#include "edit/render.h"
#ifdef PHOTO_HAVE_FACES
#include "codec/codec.h"
#endif

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

    // Render workers consult the (lock-free COW) edit map for every thumbnail.
    // Wired unconditionally; the map is simply empty without a catalog.
    thumbs_.set_edit_lookup([this](uint64_t id) {
        return edit_lookup(static_cast<int64_t>(id));
    });

#ifdef PHOTO_HAVE_SQLITE
    // Open the durable asset catalog. A failure here degrades to "no catalog"
    // (import/rescan report unavailable) rather than bricking the engine.
    try {
        catalog_ = std::make_unique<catalog::Catalog>(catalog_path_.string());
        PHOTO_LOGF(PHOTO_LOG_INFO, "catalog ready (%lld assets)",
                   static_cast<long long>(catalog_->count()));
        // Hydrate the in-memory edit map from the catalog so edited thumbnails
        // render correctly from the first request (no first-touch SQLite read).
        try {
            auto map = std::make_shared<EditMap>();
            for (auto& [id, row] : catalog_->all_edits()) {
                auto spec = std::make_shared<edit::EditSpec>(
                    edit::parse_edit_spec(row.spec));
                if (!spec->is_identity())
                    (*map)[id] = edit::EditEntry{
                        static_cast<uint32_t>(row.content_rev), std::move(spec)};
            }
            const size_t n = map->size();
            // Construction is single-threaded; no lock needed for the initial set.
            edits_ = std::shared_ptr<const EditMap>(std::move(map));
            if (n) PHOTO_LOGF(PHOTO_LOG_INFO, "hydrated %zu edited assets", n);
        } catch (const std::exception& e) {
            PHOTO_LOGF(PHOTO_LOG_WARN, "edit map hydrate failed: %s", e.what());
        }
    } catch (const std::exception& e) {
        catalog_.reset();
        PHOTO_LOGF(PHOTO_LOG_ERROR, "catalog DISABLED: %s", e.what());
    }

    // Semantic embedder: prefer the real ONNX model (siglip2 / PE-Core) if its
    // files are present under models_path_, else the always-available
    // deterministic colour/concept backend. Swapping is transparent here.
    // Construction is single-threaded; no lock needed for the initial set.
    semantic_ = make_semantic_service();
#endif
}

#ifdef PHOTO_HAVE_SQLITE
std::shared_ptr<semantic::SemanticService> Engine::make_semantic_service() const {
    auto emb = semantic::make_onnx_embedder(models_path_.string());
    const bool real = static_cast<bool>(emb);
    if (!emb) emb = semantic::make_deterministic_embedder();
    auto svc = std::make_shared<semantic::SemanticService>(std::move(emb));
    PHOTO_LOGF(PHOTO_LOG_INFO, "semantic embedder: %s model (%s, dim=%d)%s",
               real ? "ONNX" : "deterministic", svc->model_id().c_str(),
               svc->dim(),
               semantic::SemanticService::has_builtin_decoder()
                   ? "" : " [no decoder in this build → indexing skips]");
    return svc;
}

int Engine::reload_semantic() {
    // Re-probe the models dir (e.g. after the first-run download landed) and
    // swap the service in. In-flight embeds/searches hold their own shared_ptr
    // copy, so the old service (and its ONNX sessions) drains out safely. A
    // model change re-queues stale rows via pending_embedding_ids and must not
    // serve the old index → bump the sidecar generation.
    auto fresh = make_semantic_service();
    {
        std::lock_guard<std::mutex> lk(semantic_mu_);
        semantic_ = fresh;
    }
    invalidate_semantic_index();
    return fresh->dim();
}
#endif

Engine::~Engine() {
    PHOTO_LOGF(PHOTO_LOG_INFO, "engine destroyed (slots=%zu)", slots_.size());
}

// ── Edit map (general; available with or without a catalog) ────────────────

edit::EditEntry Engine::edit_lookup(int64_t asset_id) const {
    auto snap = edits_snapshot();
    if (!snap) return {};
    auto it = snap->find(asset_id);
    return it == snap->end() ? edit::EditEntry{} : it->second;
}

std::vector<int64_t> Engine::edited_asset_ids() const {
    std::vector<int64_t> out;
    auto snap = edits_snapshot();
    if (snap) {
        out.reserve(snap->size());
        for (const auto& [id, entry] : *snap) out.push_back(id);
    }
    return out;
}

void Engine::store_edit_entry(int64_t asset_id, const edit::EditEntry* entry) {
    // Copy-on-write under the lock: the rebuild must not race another writer
    // (snapshot→rebuild→swap interleaving would lose an update). The map holds
    // only the currently-edited assets, so the copy is tiny; readers block for
    // no longer than that copy, and the swapped-out map stays alive for any
    // render worker still holding a snapshot.
    std::lock_guard<std::mutex> lk(edits_mu_);
    auto next = std::make_shared<EditMap>(edits_ ? *edits_ : EditMap{});
    if (entry) (*next)[asset_id] = *entry;
    else       next->erase(asset_id);
    edits_ = std::shared_ptr<const EditMap>(std::move(next));
}

void Engine::preview_edits(uint64_t slot_id, uint64_t generation,
                           const std::string& path, uint32_t target_w,
                           uint32_t target_h, const std::string& spec_str) {
    edit::EditSpec spec = edit::parse_edit_spec(spec_str);
    jobs_.submit(PHOTO_PRIORITY_INTERACTIVE,
                 [this, slot_id, generation, path, target_w, target_h, spec] {
                     thumbs_.preview(slot_id, generation, path, target_w,
                                     target_h, spec);
                 });
}

uint64_t Engine::export_path(const std::string& src, const std::string& dst,
                             const std::string& spec_str, int quality) {
    if (src.empty() || dst.empty()) return 0;
    edit::EditSpec spec = edit::parse_edit_spec(spec_str);
    const uint64_t req = next_export_id_.fetch_add(1, std::memory_order_relaxed);
    jobs_.submit(PHOTO_PRIORITY_IDLE, [this, req, src, dst, spec, quality] {
        const bool ok = thumbs_.export_to_file(src, dst, spec, quality);
        photo_event_t ev{};
        ev.kind = PHOTO_EVT_EXPORT_COMPLETE;
        ev.status = ok ? PHOTO_STATUS_OK : PHOTO_STATUS_IO_ERROR;
        ev.request_id = req;
        events_.push(ev);
    });
    return req;
}

uint64_t Engine::export_path2(const std::string& src, const std::string& dst,
                              const std::string& spec_str,
                              const ThumbService::ExportOptions& opts) {
    if (src.empty() || dst.empty()) return 0;
    edit::EditSpec spec = edit::parse_edit_spec(spec_str);
    const uint64_t req = next_export_id_.fetch_add(1, std::memory_order_relaxed);
    jobs_.submit(PHOTO_PRIORITY_IDLE, [this, req, src, dst, spec, opts] {
        const bool ok = thumbs_.export_to_file2(src, dst, spec, opts);
        photo_event_t ev{};
        ev.kind = PHOTO_EVT_EXPORT_COMPLETE;
        ev.status = ok ? PHOTO_STATUS_OK : PHOTO_STATUS_IO_ERROR;
        ev.request_id = req;
        events_.push(ev);
    });
    return req;
}

uint64_t Engine::save_layered(const std::string& src, const std::string& dst,
                              const std::string& spec_str) {
    if (src.empty() || dst.empty()) return 0;
    edit::EditSpec spec = edit::parse_edit_spec(spec_str);
    const uint64_t req = next_export_id_.fetch_add(1, std::memory_order_relaxed);
    jobs_.submit(PHOTO_PRIORITY_IDLE, [this, req, src, dst, spec] {
        const bool ok = thumbs_.save_layered_tiff(src, dst, spec);
        photo_event_t ev{};
        ev.kind = PHOTO_EVT_EXPORT_COMPLETE;
        ev.status = ok ? PHOTO_STATUS_OK : PHOTO_STATUS_IO_ERROR;
        ev.request_id = req;
        events_.push(ev);
    });
    return req;
}

std::vector<edit::Region> Engine::detect_redeye(int64_t asset_id,
                                                const std::string& path,
                                                const std::string& spec_str) {
    std::vector<edit::Region> out;
#if defined(PHOTO_HAVE_FACES)
    // Eye landmarks come from the stored face scan (SCRFD 5-pt); the pixels come
    // from a fresh decode. Both need the faces/OpenCV build, so this whole path is
    // macOS/standalone-only — elsewhere the caller falls back to the manual brush.
    auto eyes = faces_.eye_landmarks_for_asset(static_cast<uint64_t>(asset_id));
    if (eyes.empty() || path.empty()) return out;
    cv::Mat bgr = codec::decode_bgr(path);
    if (bgr.empty()) return out;
    out = edit::auto_redeye_regions(bgr.data, bgr.cols, bgr.rows,
                                    static_cast<int>(bgr.step), eyes);
    // Landmarks (and thus the regions above) are in ORIGINAL-image space, but
    // retouch regions render in post-geometry space. When the caller's working
    // spec has geometry, map each region through it; a dab whose eye was cropped
    // out of frame is dropped rather than misplaced.
    if (!out.empty() && !spec_str.empty()) {
        const edit::EditSpec spec = edit::parse_edit_spec(spec_str);
        if (spec.has_geometry()) {
            std::vector<edit::Region> mapped;
            mapped.reserve(out.size());
            for (const auto& r : out) {
                edit::Region m;
                if (edit::map_region_through_geometry(r, bgr.cols, bgr.rows,
                                                      spec, &m))
                    mapped.push_back(m);
            }
            out = std::move(mapped);
        }
    }
#else
    (void)asset_id;
    (void)path;
    (void)spec_str;
#endif
    return out;
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

// ── Semantic search & discovery (Stage 9) ────────────────────────────────────

uint64_t Engine::embedding_scan(int64_t asset_id) {
    if (!catalog_ || !semantic_service()) return 0;
    const uint64_t req = next_import_id_.fetch_add(1, std::memory_order_relaxed);
    // Idle lane: yields to every interactive/viewport thumbnail request. The
    // Dart IndexingController additionally windows submissions and sequences
    // faces→embeddings so the two ML passes never saturate the box together.
    jobs_.submit(PHOTO_PRIORITY_IDLE, [this, req, asset_id] {
        std::string path;
        {
            std::lock_guard<std::mutex> lk(catalog_mu_);
            path = catalog_->path_by_id(asset_id);
        }
        // Heavy decode + embed runs WITHOUT the catalog lock (mirrors the face
        // scan): only the row write is serialized. A crash mid-embed leaves no
        // row, so the asset is simply re-queued on the next resume.
        // Local copy: a concurrent reload_semantic must not free the service
        // under this embed. A null copy (never expected) fails the row safely.
        const auto svc = semantic_service();
        auto rec = svc ? svc->embed_asset(asset_id, path)
                       : catalog::Catalog::EmbeddingRecord{};
        if (!svc) {
            rec.asset_id = asset_id;
            rec.status = catalog::Catalog::kEmbedFailed;
            rec.error = "no embedder";
        }
        {
            std::lock_guard<std::mutex> lk(catalog_mu_);
            try { catalog_->upsert_embedding(rec); } catch (...) {}
        }
        // A new Done row changes the search working set → drop the RAM cache.
        if (rec.status == catalog::Catalog::kEmbedDone)
            invalidate_semantic_index();
        photo_event_t ev{};
        ev.kind = PHOTO_EVT_EMBED_PROGRESS;
        ev.request_id = req;
        ev.asset_id = static_cast<uint64_t>(asset_id);
        ev.aux64 = 1;  // one asset processed
        ev.status = rec.status == catalog::Catalog::kEmbedDone    ? PHOTO_STATUS_OK
                  : rec.status == catalog::Catalog::kEmbedSkipped ? PHOTO_STATUS_UNSUPPORTED
                                                                  : PHOTO_STATUS_DECODE_ERROR;
        events_.push(ev);
    });
    return req;
}

std::vector<int64_t> Engine::pending_embedding_ids(int limit) const {
    const auto svc = semantic_service();
    if (!catalog_ || !svc) return {};
    std::lock_guard<std::mutex> lk(catalog_mu_);
    return catalog_->pending_embedding_ids(svc->model_id(),
                                           svc->model_version(), limit);
}

catalog::Catalog::EmbeddingCounts Engine::embedding_counts() const {
    if (!catalog_) return {};
    std::lock_guard<std::mutex> lk(catalog_mu_);
    return catalog_->embedding_counts();
}

void Engine::retry_failed_embeddings() {
    if (!catalog_) return;
    {
        std::lock_guard<std::mutex> lk(catalog_mu_);
        catalog_->retry_failed_embeddings();
    }
    // Failed→pending doesn't change the Done set, but this is also the natural
    // "re-sync" hook after any external catalog surgery — invalidating here is
    // cheap and keeps the cache contract simple.
    invalidate_semantic_index();
}

std::optional<catalog::Catalog::EmbeddingRecord> Engine::get_embedding(
    int64_t asset_id) const {
    if (!catalog_) return std::nullopt;
    std::lock_guard<std::mutex> lk(catalog_mu_);
    return catalog_->get_embedding(asset_id);
}

std::vector<std::pair<int64_t, int32_t>> Engine::dominant_colors() const {
    if (!catalog_) return {};
    std::lock_guard<std::mutex> lk(catalog_mu_);
    return catalog_->dominant_colors();
}

int Engine::embedding_dim() const {
    const auto svc = semantic_service();
    return svc ? svc->dim() : 0;
}

std::string Engine::embedding_model_id() const {
    const auto svc = semantic_service();
    return svc ? svc->model_id() : std::string{};
}

std::vector<float> Engine::embed_text(const std::string& query) const {
    const auto svc = semantic_service();
    return svc ? svc->embed_text(query) : std::vector<float>{};
}

void Engine::release_semantic_sessions(uint32_t mask) {
    if (const auto svc = semantic_service()) svc->release_sessions(mask);
}

void Engine::invalidate_semantic_index() {
    // Bump the generation FIRST: an in-flight search that snapshotted the DB
    // before this write sees the mismatch and declines to publish its (possibly
    // stale) rebuild. Then drop the mapping so the next search rebuilds the
    // sidecar file. The old mapping stays alive for any concurrent scan that
    // already copied the shared_ptr.
    semantic_index_gen_.fetch_add(1, std::memory_order_acq_rel);
    std::lock_guard<std::mutex> lk(semantic_index_mu_);
    sidecar_.reset();
}

std::vector<semantic::SearchHit> Engine::semantic_search(
    const std::vector<float>& query, const std::vector<int64_t>& candidates,
    size_t cap) const {
    if (!catalog_ || query.empty()) return {};
    const int dim = static_cast<int>(query.size());
    const std::string path = (cache_path_ / "semantic_index.bin").string();
    const auto svc = semantic_service();
    const uint64_t mhash =
        svc ? semantic::SidecarIndex::model_hash(svc->model_id(),
                                                 svc->model_version(), dim)
            : 0;

    std::shared_ptr<const semantic::SidecarIndex> idx;
    uint64_t built_gen = 0;
    {
        std::lock_guard<std::mutex> lk(semantic_index_mu_);
        idx = sidecar_;
        built_gen = sidecar_built_gen_;
    }
    const uint64_t gen = semantic_index_gen_.load(std::memory_order_acquire);

    // Hot path: current mapping, no embedding writes since it was built.
    if (idx && built_gen == gen && idx->dim() == dim &&
        idx->stamp_model_hash() == mhash)
        return idx->scan(query, candidates, cap);

    // Process-start adoption: an on-disk sidecar whose stamp still matches the
    // catalog avoids re-reading every BLOB. Only worth probing when we hold no
    // mapping at all (a generation bump means the file is known-stale).
    if (!idx && gen == 0) {
        auto disk = semantic::SidecarIndex::open(path);
        if (disk && disk->dim() == dim && disk->stamp_model_hash() == mhash) {
            catalog::Catalog::EmbeddingStamp st;
            {
                std::lock_guard<std::mutex> lk(catalog_mu_);
                st = catalog_->embedding_stamp();
            }
            if (st.count == disk->stamp_count() &&
                st.max_updated_ns == disk->stamp_max_updated_ns()) {
                std::lock_guard<std::mutex> lk(semantic_index_mu_);
                if (semantic_index_gen_.load(std::memory_order_acquire) == gen) {
                    sidecar_ = disk;
                    sidecar_built_gen_ = gen;
                }
                return disk->scan(query, candidates, cap);
            }
        }
    }

    // Rebuild the sidecar from the catalog (embedding writes since the last
    // build, a model switch, or a missing/stale/corrupt file).
    std::vector<catalog::Catalog::EmbeddingVec> items;
    catalog::Catalog::EmbeddingStamp st;
    {
        std::lock_guard<std::mutex> lk(catalog_mu_);
        items = catalog_->done_embeddings();
        st = catalog_->embedding_stamp();
    }
    if (semantic::SidecarIndex::write(path, items, dim, mhash, st)) {
        if (auto fresh = semantic::SidecarIndex::open(path)) {
            {
                std::lock_guard<std::mutex> lk(semantic_index_mu_);
                if (semantic_index_gen_.load(std::memory_order_acquire) == gen) {
                    sidecar_ = fresh;
                    sidecar_built_gen_ = gen;
                }
            }
            return fresh->scan(query, candidates, cap);
        }
    }
    // Disk trouble (full / unwritable cache dir): serve this query directly
    // from the rows we already read — uncached but correct.
    return semantic::cosine_rank(query, items, candidates, cap);
}

int64_t Engine::create_saved_search(const std::string& name,
                                    const std::string& query_json) {
    if (!catalog_) return 0;
    std::lock_guard<std::mutex> lk(catalog_mu_);
    return catalog_->create_saved_search(name, query_json, now_ns());
}

void Engine::delete_saved_search(int64_t id) {
    if (!catalog_) return;
    std::lock_guard<std::mutex> lk(catalog_mu_);
    catalog_->delete_saved_search(id);
}

std::vector<catalog::Catalog::SavedSearchRecord> Engine::list_saved_searches()
    const {
    if (!catalog_) return {};
    std::lock_guard<std::mutex> lk(catalog_mu_);
    return catalog_->list_saved_searches();
}

std::optional<catalog::Catalog::SavedSearchRecord> Engine::get_saved_search(
    int64_t id) const {
    if (!catalog_) return std::nullopt;
    std::lock_guard<std::mutex> lk(catalog_mu_);
    return catalog_->get_saved_search(id);
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

void Engine::set_geo(int64_t asset_id, double lat, double lon) {
    if (!catalog_) return;
    std::lock_guard<std::mutex> lk(catalog_mu_);
    catalog_->set_geo_override(asset_id, lat, lon);
}

void Engine::clear_geo(int64_t asset_id) {
    if (!catalog_) return;
    std::lock_guard<std::mutex> lk(catalog_mu_);
    catalog_->clear_geo_override(asset_id);
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

std::string Engine::get_edits(int64_t asset_id) const {
    if (!catalog_) return {};
    std::lock_guard<std::mutex> lk(catalog_mu_);
    auto row = catalog_->edit_for(asset_id);
    return row ? row->spec : std::string{};
}

uint64_t Engine::set_edits(int64_t asset_id, const std::string& spec_str) {
    if (!catalog_) return 0;
    edit::EditSpec parsed = edit::parse_edit_spec(spec_str);
    // An identity spec is a revert: clear the row (rev → 0) so the original is
    // served straight from cache, and don't fork the cache with a no-op edit.
    if (parsed.is_identity()) {
        revert_edits(asset_id);
        return 0;
    }
    // Store the canonical (re-serialized) form so the on-disk spec is normalized.
    const std::string canonical = edit::serialize_edit_spec(parsed);
    int64_t rev = 0;
    {
        std::lock_guard<std::mutex> lk(catalog_mu_);  // durable first (see R3)
        rev = catalog_->set_edit(asset_id, canonical, now_ns());
    }
    edit::EditEntry entry{static_cast<uint32_t>(rev),
                          std::make_shared<edit::EditSpec>(std::move(parsed))};
    store_edit_entry(asset_id, &entry);  // then make it visible (COW swap)
    return static_cast<uint64_t>(rev);
}

void Engine::revert_edits(int64_t asset_id) {
    if (!catalog_) return;
    {
        std::lock_guard<std::mutex> lk(catalog_mu_);
        catalog_->clear_edit(asset_id);
    }
    store_edit_entry(asset_id, nullptr);
}

uint64_t Engine::content_rev(int64_t asset_id) const {
    return edit_lookup(asset_id).content_rev;
}

#endif  // PHOTO_HAVE_SQLITE

}  // namespace photo

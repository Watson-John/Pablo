// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.

#include "dedup/server.h"

#include <cstdlib>
#include <filesystem>
#include <string>

#include <httplib.h>
#include <nlohmann/json.hpp>

#include "dedup/decode.h"
#include "dedup/log.h"

namespace dedup {
namespace fs = std::filesystem;
using nlohmann::json;

namespace {

json image_json(const ImageRecord& r, bool is_keeper) {
    return json{
        {"id", r.id},
        {"path", r.path},
        {"format", r.format},
        {"size", r.size_bytes},
        {"is_keeper", is_keeper},
    };
}

// Move `src` into the quarantine dir. Returns the destination, or empty on
// failure. NEVER deletes — a cross-device move degrades to copy-then-remove,
// and if the copy fails the original is left untouched.
std::string quarantine_move(const std::string& src_path, int64_t id,
                            const std::string& quarantine_dir) {
    std::error_code ec;
    fs::create_directories(quarantine_dir, ec);
    fs::path src(src_path);
    fs::path dst = fs::path(quarantine_dir) /
                   (std::to_string(id) + "__" + src.filename().string());

    fs::rename(src, dst, ec);
    if (!ec) return dst.string();

    ec.clear();
    fs::copy_file(src, dst, fs::copy_options::overwrite_existing, ec);
    if (ec) {
        LOG_WARN("quarantine: copy failed for " << src_path << ": " << ec.message());
        return {};
    }
    std::error_code rec;
    fs::remove(src, rec);  // best-effort; original preserved if this fails
    return dst.string();
}

}  // namespace

void serve_review(const Config& cfg, Store& store) {
    httplib::Server svr;

    // --- Static review UI ---
    if (!cfg.web_dir.empty() && fs::exists(cfg.web_dir)) {
        svr.set_mount_point("/", cfg.web_dir);
    } else {
        LOG_WARN("serve: web dir '" << cfg.web_dir << "' not found; API only");
    }

    // --- GET /api/clusters : all clusters with member metadata ---
    svr.Get("/api/clusters", [&](const httplib::Request&, httplib::Response& res) {
        auto clusters = store.load_clusters();
        auto by_id = store.all_by_id();
        json arr = json::array();
        for (const auto& c : clusters) {
            json members = json::array();
            for (int64_t id : c.members) {
                auto it = by_id.find(id);
                if (it == by_id.end()) continue;
                members.push_back(image_json(it->second, id == c.suggested_keeper));
            }
            arr.push_back({
                {"id", c.id},
                {"suggested_keeper", c.suggested_keeper},
                {"flagged_oversize", c.flagged_oversize},
                {"members", members},
            });
        }
        res.set_content(json{{"clusters", arr}}.dump(), "application/json");
    });

    // --- GET /api/image?id=N : JPEG preview (handles RAW) ---
    svr.Get("/api/image", [&](const httplib::Request& req, httplib::Response& res) {
        if (!req.has_param("id")) { res.status = 400; return; }
        const int64_t id = std::atoll(req.get_param_value("id").c_str());
        auto rec = store.image_by_id(id);
        if (!rec) { res.status = 404; return; }
        const int max_dim = req.has_param("full") ? 2048 : 512;
        auto jpeg = encode_preview_jpeg(rec->path, max_dim);
        if (!jpeg) { res.status = 415; return; }
        res.set_content(reinterpret_cast<const char*>(jpeg->data()), jpeg->size(),
                        "image/jpeg");
    });

    // --- POST /api/act : quarantine the listed image ids ---
    svr.Post("/api/act", [&](const httplib::Request& req, httplib::Response& res) {
        json body;
        try { body = json::parse(req.body); }
        catch (...) { res.status = 400; res.set_content("{\"error\":\"bad json\"}", "application/json"); return; }

        json moved = json::array();
        json errors = json::array();
        for (const auto& d : body.value("discards", json::array())) {
            const int64_t id = d.get<int64_t>();
            auto rec = store.image_by_id(id);
            if (!rec) { errors.push_back({{"id", id}, {"error", "unknown id"}}); continue; }
            std::string dest = quarantine_move(rec->path, id, cfg.quarantine_dir);
            if (dest.empty()) {
                errors.push_back({{"id", id}, {"error", "move failed"}});
            } else {
                store.record_quarantine(id, dest);
                moved.push_back({{"id", id}, {"dest", dest}});
                LOG_INFO("quarantined image " << id << " -> " << dest);
            }
        }
        res.set_content(json{{"moved", moved}, {"errors", errors}}.dump(),
                        "application/json");
    });

    svr.Get("/api/health", [&](const httplib::Request&, httplib::Response& res) {
        res.set_content("{\"ok\":true}", "application/json");
    });

    LOG_INFO("review UI: http://" << cfg.server_host << ":" << cfg.server_port
                                  << "  (Ctrl-C to stop; discards go to "
                                  << cfg.quarantine_dir << ")");
    if (!svr.listen(cfg.server_host, cfg.server_port)) {
        throw std::runtime_error("failed to bind " + cfg.server_host + ":" +
                                 std::to_string(cfg.server_port));
    }
}

}  // namespace dedup

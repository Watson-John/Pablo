// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// Stage 8: local review server (the `dedup serve` command).
//
// A cpp-httplib server bound to localhost serves the static review UI from
// `web/` and a small JSON API over the persisted clusters. The reviewer picks
// which members to discard; the server MOVES them to the quarantine directory
// (never deletes) and records the action.

#pragma once

#include "dedup/config.h"
#include "dedup/store.h"

namespace dedup {

// Blocks serving the review UI until interrupted. Binds cfg.server_host:port.
void serve_review(const Config& cfg, Store& store);

}  // namespace dedup

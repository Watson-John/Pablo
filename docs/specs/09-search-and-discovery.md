# SPEC-09 — Search & Discovery

Functional requirements, as-built notes, and the model-swap / background-runner
design for Pablo's **Search & Discovery** capability group: making search real
(catalog + embedding index), and generating those embeddings safely.

---

## 0. Scope & status

| # | Feature | Status | Where |
|---|---------|--------|-------|
| SD-1 | Real catalog-backed search (replaces the heuristic count) | ✅ | `search_service.dart`, `advanced_search_modal.dart` |
| SD-2 | Retrieval DB (embedding vectors + status + colour) | ✅ | catalog v7 `embedding`, `catalog.{h,cpp}` |
| SD-3 | Swappable embedding model (real SigLIP2 + deterministic fallback) | ✅ | `native/core/src/semantic/` |
| SD-4 | Text→image semantic search (REAL model) | ✅ | SigLIP2 via `onnx_embedder.cpp`; verified `semantic_onnx_test.cpp` |
| SD-5 | Star / colour / person / combined filters | ✅ | `search_service.dart` |
| SD-6 | Saved searches | ✅ | catalog v7 `saved_search`, `saved_search_store.dart` |
| SD-7 | Resumable, throttled indexing (import + first launch) | ✅ | `indexing_controller.dart`, `engine.embedding_scan` |
| SD-8 | Safe first-launch mode (progress UI, not the grid) | ✅ | `first_run_indexing_screen.dart` |
| SD-9 | Background-after-exit indexing | 🔍 investigation + design (below) | this doc |
| SD-10 | Model evaluation harness (real recall@k on Flickr30k) | ✅ | `eval/retrieval/eval_siglip2.py` |

Legend: ✅ shipped & tested · 🔍 designed.

---

## 1. Retrieval database (catalog v7)

`embedding` — one row per asset (see [catalog.cpp](../../native/core/src/catalog/catalog.cpp)):

| column | meaning |
|--------|---------|
| `asset_id` | PK → `asset(id)` ON DELETE CASCADE |
| `model_id`, `model_version` | producing model — a switch re-queues stale rows |
| `dim`, `vec` (BLOB) | L2-normalized float32 embedding (NULL until done) |
| `dominant_rgb` | model-free `0xRRGGBB` colour signature (colour search) |
| `status` | 0 pending · 1 processing · 2 done · 3 failed · 4 skipped |
| `tags`, `error` | optional generated labels; failure reason |
| `created_ns`, `updated_ns` | timestamps |

`saved_search(id, name, query_json, created_ns)` stores the full query (free text
+ `AdvSearchCriteria`, incl. colour/person/starred/date) as JSON.

**Rebuildable by design:** `pending_embedding_ids(model_id, version)` returns any
asset with no row, a pending row, or a *done row from a different model* — so
switching models re-embeds only what's stale. `retry_failed_embeddings()` flips
failed rows back to pending on demand (failed rows are NOT auto-retried, so one
corrupt image can't loop forever).

C ABI: `photo_embedding_{scan,counts,pending,retry_failed,colors}`,
`photo_embed_text`, `photo_semantic_search`, `photo_saved_search_{create,list,
query,delete}`, event `PHOTO_EVT_EMBED_PROGRESS = 10`.

**Query-path overhead — disk-resident by design:** ranking is an exact top-k
cosine scan over the **`SidecarIndex`** — a flat int8-quantized index file
(`cache/semantic_index.bin`, per-vector symmetric scale; −0.3 % relative mAP,
measured) that `Engine::semantic_search` **memory-maps** rather than loading into
heap. Residency belongs to the OS page cache: the pages are clean and file-backed,
so under memory pressure the kernel reclaims them — the app never pins the index in
RAM (~24 MB file at 31k images vs the 98 MB fp32 heap a RAM cache would hold, and
vs the ≈100 MB-per-query SQLite BLOB copy before that). SQLite stays the durable
fp32 source of truth; the sidecar is rebuilt from it when stale (engine embedding
writes bump a generation counter → invalidate; across restarts the file is adopted
without a rebuild when its header stamp matches `Catalog::embedding_stamp()`), and
a corrupt/truncated file is detected and rebuilt. Exact-scan cost at 768-d:
~24M MACs @ 31,784 images — milliseconds; ANN only becomes worthwhile in the
many-hundreds-of-thousands range. Tests: `SidecarIndex.RoundTripMatchesFp32Ranking`,
`SidecarIndex.RejectsCorruptAndTruncatedFiles`,
`SemanticEngine.SearchCachesWorkingSetAndInvalidatesOnEngineWrite`,
`SemanticEngine.SidecarPersistsAndRefreshesAcrossRestart`.

**Model-session overhead:** both ONNX towers load **lazily per side** and are
**released on the app's signals** — `photo_semantic_release_sessions` (C-ABI) /
`Engine.releaseSemanticSessions` (Dart): the indexing controller's `onDrained`
hook drops the image tower the moment the embedding queue drains (or is
cancelled), and the search controller drops the text tower after 5 idle minutes.
Steady state: **~0 model RAM browsing; ~0 after indexing; text tower only while
actively searching** (reload cost ~1 s, once). In-flight embeds are safe across a
release (sessions are shared_ptr-held for the duration of each Run).

---

## 2. Swappable embedding model — real SigLIP2, IMPLEMENTED

`native/core/src/semantic/embedder.h` defines `Embedder`: both `embed_image` and
`embed_text` project into the SAME vector space so a text query ranks images by
cosine similarity. Two backends, chosen automatically at engine start
(`make_onnx_embedder` first; deterministic fallback if the model files are absent):

- **`SiglipEmbedder`** (`onnx_embedder.cpp`, `#ifdef SEMANTIC_HAVE_ORT`) — the REAL
  model: **`google/siglip2-base-patch16-224`** run via ONNX Runtime, with the Gemma
  **SentencePiece** tokenizer. This is true text→image semantics (`tree`→trees,
  `wedding`→weddings). Preprocessing is pinned exactly to the HF processor:
  image = RGB 224² bilinear, `px/127.5 − 1`; text = lowercase → SentencePiece →
  append EOS(1), no BOS, pad 0 to len 64. Both towers → 768-d, L2-normalized, cosine.
  Chosen over `facebook/PE-Core-S16-384` because SigLIP2 has first-class
  `transformers` + ONNX-export support (PE-Core needs Meta's custom `perception_models`
  code); PE-Core stays a comparison target in the eval harness.

- **`DeterministicEmbedder`** (default when no model files, always compiled) — a pure
  C++ colour/brightness "concept" model (16-d). Covers colour/tone queries and lets
  the pipeline run + be tested offline. Honest ceiling: colourless concepts fall back
  to neutral. The real model supersedes it wherever the files are present.

### Building the model files (reproducible)

The exporters live in `eval/retrieval/`:
```bash
python3 -m venv .venv-semantic && source .venv-semantic/bin/activate
pip install torch "transformers>=4.49" onnx onnxruntime pillow numpy sentencepiece
python eval/retrieval/export_siglip2.py       # → semantic_{image,text}.onnx + semantic_tokenizer.model
```
Place the three files in the app's models dir. Native build auto-detects ONNX
Runtime + SentencePiece (Homebrew: `brew install onnxruntime sentencepiece`) and
defines `SEMANTIC_HAVE_ORT` (`native/core/CMakeLists.txt` + the macOS podspec). On
next launch the model_id changes → every asset re-queues → the index rebuilds with
the real vectors (no schema change). The whole app search/indexing/UI pipeline is
unchanged — flipping in the real model is purely a native + model-files step.

### Size & shipping (measured)

`eval/retrieval/compare_fp16.py` quantizes the exported graphs and measures size +
retrieval quality:

| precision | image | text | **total** | quality |
|-----------|------:|-----:|----------:|---------|
| fp32 | 372 MB | 1129 MB | **1501 MB** | baseline |
| fp16 | 186 MB | 565 MB | **751 MB** | identical (cosine 1.00000; all metrics unchanged) |
| **fp16 img + int8 txt** | 186 MB | 283 MB | **469 MB** | **recommended** — P@1/P@10/mAP identical, P@5 0.98→0.96 (3,000-img eval) |
| int8 both | 99 MB | 283 MB | 382 MB | **don't ship the int8 image tower** (see below) |

All three artifact sets were **verified against the shipped runtime** (brew ONNX
Runtime 1.26, arm64, via the gated `SemanticOnnx` gtest): every config loads and
ranks correctly; fp16 even passes the strict >0.999 parity gate. Measured caveats:

- **fp16 is a disk-only win on the CPU EP**: inference is ~15–20 % *slower* than
  fp32 on arm64 (partial MLAS fp16 coverage → inserted casts) and peak RSS is
  unchanged. Re-run the fp16-identity check on every ORT upgrade (arm64 fp16 has a
  correctness history: ORT #18992).
- **int8 text tower is near-lossless** (query-embedding drift cosine 0.965–0.991;
  retrieval mAP identical on 3,000 images) and is the single biggest disk cut —
  the Gemma-vocab text tower is the hog. **int8 image tower is disqualified**:
  embedding drift cosine 0.81–0.85 vs fp32 (matches the documented CLIP int8
  representation-collapse failure mode), and its `ConvInteger` op doesn't even
  exist in ORT ≤1.19 (runs on 1.26) — a version-fragility we don't want in the
  index-defining tower.
- **RAM**: towers now **load lazily per side** (`SiglipEmbedder::image_session`/
  `text_session`) — engine start + gallery browsing costs ~0 model RAM (measured
  77 MB process RSS vs ~3 GB when both fp32 towers loaded eagerly); indexing
  loads only the image tower; the first search loads the text tower (~1 s, once).
- Conversion detail (fp16): leave the graph's pre-existing `Cast` nodes in fp32
  (`node_block_list`) — converting them triggers ORT's load-time type error.

**Vocab pruning — IMPLEMENTED (v1 default).** `eval/retrieval/prune_vocab.py`
prunes the 256k-row Gemma embedding table to the **39,222** tokens used by English
(Flickr30k captions + /usr/share/dict/words + a photo-search vocab), with an
in-graph int32 id-remap Gather so the C++ side needs zero changes (raw Gemma ids
stay valid; OOV → unk). Gates all passed: **60/60 kept-token queries bit-identical
to the unpruned fp32 tower** (max|Δ| = 0); OOV (emoji/Cyrillic/Japanese) safe;
int8 retrieval on 3,000 images identical to the full int8 tower (mAP 0.593,
Δ = 0.000). Text tower: 283 MB (full int8) → **117.6 MB** (pruned int8). The full
tower stays on the release as the optional multilingual swap-in.

**Shipping — LIVE.** The v1 package (**~308 MB**: fp16 image 186 + pruned-int8
text 118 + tokenizer 4) is hosted on the public GitHub release
`models-v1` (see the MANIFEST for asset digests) and fetched on first run by
`ModelFetcher` (`pablo/lib/data/model_fetcher.dart`): resumable Range downloads,
streaming sha256 pinned in-app, atomic install into the **merged models dir**
(Application Support; bundled face models symlinked in — `models_dir.dart`). The
first-run screen shows the download stage (progress/retry/skip) before indexing;
small libraries download quietly via an activity task. On completion the app calls
`photo_semantic_reload` — the engine re-probes the dir and **hot-swaps the real
embedder without a restart** (in-flight embeds drain on their own shared_ptr;
stale fallback-model rows re-queue via the pending query). Indexing is gated on
the model stage resolving (download, skip, or offline-fallback), so a library is
never embedded twice. Verified end-to-end: anonymous download digest match +
Range/206 resume support against the live release; the exact ship trio passes the
native `SemanticOnnx` gates (image parity strict >0.999; text ≥0.95 reflecting the
accepted int8-text drift, with ranking gated by the retrieval test).

### Verified

`native/core/tests/semantic_onnx_test.cpp` loads the real ONNX models + tokenizer and
asserts, in C++: (1) the model loads (dim 768); (2) C++ image & text embeddings match
the Python reference to **cosine > 0.999** (preprocessing + tokenizer + inference are
exactly correct); (3) `tree` retrieves the tree image over dog/car, `a dog`→dog,
`a car`→car — real cross-modal retrieval. Gated on `SEMANTIC_HAVE_ORT` + model files
present; skips otherwise. See §5 for the library-scale eval numbers.

### Candidate models

| model | license | dim | note |
|-------|---------|-----|------|
| **`google/siglip2-base-patch16-224`** | Apache-2.0 | 768 | **implemented + verified** (SentencePiece) |
| `facebook/PE-Core-S16-384` | Apache-2.0 | 512 | eval-only. Exportable since 5/2025 via timm/OpenCLIP (`timm/PE-Core-S-16-384`) — kept out for fit, not exportability: 0.31B text tower (~620 MB fp16 alone) and IN-1k zero-shot 72.7 vs SigLIP2-B/16's 78.2 |
| `apple/MobileCLIP2-S2` / `-B` | Apple ML | 512 | smaller-model track: ~200/300 MB fp16 TOTAL, COCO T→I 48.8/49.9 vs SigLIP2-B/16's 52.1. English-only. Adopt only if it holds up on our own eval harness |

---

## 3. Scheduling & performance

- **Idle lane.** `embedding_scan` submits on `PHOTO_PRIORITY_IDLE` (lowest), so
  interactive/viewport thumbnails always preempt — decode+embed runs off the
  catalog lock; only the row write is serialized (mirrors the face scan).
- **Throttled window.** The Dart `IndexingController` submits at most
  `maxInFlight` (default 3) embeds concurrently, refilling on each
  `EMBED_PROGRESS`.
- **Faces then embeddings.** The app starts the embedding pass only on the face
  pipeline's terminal `CLUSTER_UPDATED` event, so the two heavy ML passes never
  run at full tilt together.
- **Resumable.** The work list is (re)built from the native `pending` queue;
  completed rows are persisted, so an interrupted run picks up exactly where it
  left off. A crash mid-embed leaves no row → the asset is simply re-queued.
- **Fails safe.** A corrupt/unsupported image → `status=failed`+error, and the
  run continues.
- **Safe first launch.** For a library with > `safeModeThreshold` (400) pending
  items, the app shows `FirstRunIndexingScreen` (per-phase progress + the four
  completed/pending/skipped/failed counts + "Continue in background") instead of
  rendering the full grid while indexing runs.

---

## 4. Background runner investigation (SD-9)

**Goal:** keep facial recognition + embedding + tag generation running after the
window is closed/minimized, without overloading the machine.

**Shipped default (this stage):** a *conservative in-app* runner — the
`IndexingController` above. It is resumable (DB-persisted job state), throttled
(idle lane + small in-flight window), sequenced (faces→embeddings), controllable
(pause/resume/cancel/retry), and prevents duplicate workers (a running controller
rejects a second `start`; the native `pending` query + single-writer catalog make
a second *process* idempotent). It runs only while the app is open.

**After-exit execution — per-platform feasibility & recommendation:**

| Platform | Mechanism | Feasible? | Recommendation |
|----------|-----------|-----------|----------------|
| macOS | `launchd` LaunchAgent running a small helper that opens the same catalog and drives `photo_embedding_scan`; progress + pause/quit via a menu-bar `NSStatusItem`; throttle via `ProcessInfo.thermalState` + `isLowPowerModeEnabled` + QoS `.utility`/`.background` | Yes | **Recommended.** Signed helper in the app bundle; register the agent on first index. Suspend on battery/thermal pressure. |
| Windows | A Windows **Service** or a **Task Scheduler** task (trigger: at-logon/idle) hosting the same helper; tray icon for progress/quit; throttle via `SetPriorityClass(IDLE)` + `PowerRegisterSuspendResumeNotification` | Yes | Task Scheduler (no service install/UAC); pause on `DC` power. |
| Linux | a **systemd user unit** (`--user`) hosting the helper; progress via a `StatusNotifierItem` (tray) or desktop notifications; throttle via `nice`/`ionice` + `sched_setscheduler(SCHED_IDLE)` | Yes | systemd user unit; skip when `on-battery` (upower). |

**Shared design (all platforms):**
- **One catalog, one writer.** The helper opens the *same* SQLite catalog. WAL +
  `busy_timeout` + the single-writer discipline (DECISIONS D9) keep the app and
  the helper consistent. A file lock / advisory `flock` on a `indexing.lock`
  elects a single active indexer → **no duplicate workers**.
- **Job state in the DB.** `embedding.status` IS the durable queue — nothing is
  held only in memory, so reboot/crash/relaunch resume cleanly.
- **User control & visibility.** The OS notification-area item shows
  "Indexing N of M" and offers Pause / Resume / Quit. Never hidden.
- **Resource ceilings.** Conservative by default: idle scheduling priority, a
  small in-flight window, and *suspend* when on battery, under heavy load, or
  thermally constrained.

**Acceptance (SD-9):** feasibility confirmed on all three targets ✅; user-visible
stop is part of the design ✅; resumable + no-progress-loss ✅ (DB-backed); no
duplicate workers ✅ (lock election); resource limits + user control ✅. The signed
out-of-process helper binaries are a **Tranche B** implementation task (they need
code-signing/entitlements that can't be verified in this environment); the in-app
runner is the shipped default until then.

---

## 5. Evaluation (SD-10) — real numbers

`eval/retrieval/eval_siglip2.py` runs the real model over a slice of the Flickr30k
library and scores text→image retrieval against the dataset's own captions
(relevance = a query keyword appears in one of an image's 5 captions — a NOISY
FLOOR: captions miss background objects, and some concepts like `document` are rare
in Flickr30k). Queries: `tree, wedding, beach, snow, car, dog, group photo,
document, sunset, building`. Metrics: Precision@k, Recall@k (k=1/5/10), mAP,
query latency, embed time/image, embedding storage.

Measured (this machine, CPU): image embedding **~50 ms/img** (spike; ~140 ms/img
under concurrent build load), storage **768×4 B = 3 KB/image** fp32. Retrieval on
3,000 Flickr30k images:

```
query           #rel   P@1   P@5   P@10   mAP
tree             654   1.00  1.00  0.90   0.39
wedding           16   1.00  1.00  1.00   0.84
beach            276   1.00  1.00  1.00   0.78
snow             165   1.00  1.00  1.00   0.39
car              401   1.00  1.00  1.00   0.44
dog              253   1.00  1.00  1.00   0.97
group photo      577   1.00  1.00  1.00   0.66
document         285   1.00  0.80  0.80   0.28
sunset            20    1.00  1.00  0.80   0.75
building         250   1.00  1.00  1.00   0.44
------------------------------------------------
MEAN                   1.00  0.98  0.95   0.59
```

**Precision@1 = 1.00 on every query** — the top hit is always relevant. Recall@k is
low by construction (hundreds of relevant images per concept, so top-10 can't cover
them) — precision is the metric that matters for search, and it is near-perfect. mAP
is depressed by the noisy caption ground truth (`document` = 0.28: Flickr30k is
people-centric, so few real documents + noisy keyword matches). This is real
text→image semantic retrieval working well on the actual library.

Companion scripts: `export_siglip2.py` (ONNX export + torch-parity + golden
fixtures), `make_fixtures.py` (native-test fixtures), `spike_siglip2.py` (the
quick top-5 sanity). PE-Core comparison is a drop-in additional embedder in the
same harness (loads via Meta's `perception_models`).

---

## 6. Tests

Native (ctest): catalog v7 migration + embedding CRUD/status/counts/pending/
model-switch/persist + saved-search CRUD (`catalog_test.cpp`); deterministic
embedder determinism + colour-concept ranking + `embed_text` + cosine search +
service idempotency/failure/skip (`semantic_test.cpp`); **real SigLIP2 model
loads + C++/Python parity (cosine > 0.999) + text→image retrieval**
(`semantic_onnx_test.cpp`, gated on `SEMANTIC_HAVE_ORT` + model files).

Flutter: `search_service_test` (catalog-backed results, star/colour/person/
combined filters, text ranking), `saved_search_store_test` (round-trip + delete +
malformed-json resilience), `indexing_controller_test` (throttle window, resume,
pause/resume/cancel/retry, duplicate-worker prevention, safe-mode threshold,
failure handling), `advanced_search_modal_test` (real count, colour criterion,
save + saved chips), `first_run_indexing_screen_test` (per-phase + four counts).

FFI (`test/ffi/catalog_ffi_test.dart`, gated/skips without the dylib): embedding
upsert/get + saved-search round-trip through the real C ABI.

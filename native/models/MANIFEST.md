# Pablo ML model manifest

Canonical list of ML model files Pablo ships with. Every model file in this directory must have a row in the table below. The model registry ([M6](/Users/johnwatson/.claude/plans/what-are-your-thoughts-scalable-puddle.md)) verifies SHA256, license flag, and version against this manifest at load time. **Models flagged `commercial: false` cannot be loaded unless the user explicitly opts in.**

Model files themselves are tracked via Git LFS (see [BUILD.md](../../docs/BUILD.md)).

The face model source decision is recorded in [DECISIONS.md §D2](../../docs/DECISIONS.md#d2-face-model-source--blazeface--permissively-licensed-embedder).

## Manifest schema

Each row:

| Column | Meaning |
|--------|---------|
| `model_id` | Stable identifier used by `ModelRegistry::load(model_id)`. snake_case. |
| `file` | Relative path under [native/models/](.) |
| `purpose` | Detection / embedding / etc. |
| `inputs` | Input shape and dtype |
| `outputs` | Output shape and dtype |
| `license` | SPDX identifier or explicit license name |
| `commercial` | `true` if commercially redistributable; `false` blocks ship |
| `source_url` | Upstream source for reproducibility |
| `sha256` | Verified hash (populated when model is committed via LFS) |
| `added` | Date added to manifest |

## Active models

Resolved by the M7 embedder/detector bake-off — run early as `eval/` (branch
`feat/face-ingestion`) against the real dogfood library (1,243 Picasa-labeled
faces, 12–17 people). See "Bake-off results" below; supersedes the FaceNet /
BlazeFace placeholders (kept as fallbacks).

| `model_id` | `file` | `purpose` | `inputs` | `outputs` | `license` | `commercial` | `source_url` | `sha256` | `added` |
|---|---|---|---|---|---|---|---|---|---|
| `scrfd_10g` | `scrfd_10g.onnx` | detection (bbox + 5 landmarks) | `1x3xHxW float32, RGB, (x-127.5)/128` | strides 8/16/32: score + bbox + kps | Apache 2.0 (fal re-release) | true | https://huggingface.co/fal/AuraFace-v1 | `5838f7fe053675b1c7a08b633df49e7af5495cee0493c7dcf6697200b85b5b91` | 2026-06-14 |
| `auraface` | `auraface.onnx` | 512-d face embedding | `1x3x112x112 float32, RGB, (x-127.5)/127.5` | `1x512 float32 (L2-normalize after)` | Apache 2.0 | true | https://huggingface.co/fal/AuraFace-v1 | `a7933ea5330113b01c9b60351d8f4c33003f145d8470ac5f0e52ee2effe25c60` | 2026-06-14 |
| `sface` | `sface.onnx` | 128-d embedding (lightweight fallback) | `1x3x112x112 BGR (alignCrop)` | `1x128 float32 (L2-normalize)` | Apache 2.0 | true | https://github.com/opencv/opencv_zoo | `0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79` | 2026-06-14 |
| `blazeface_short` | `blazeface_short.onnx` | detection fallback (license-safe, recall untested) | `1x3x128x128 float32, [-1,1]` | anchors + scores | Apache 2.0 | true | https://storage.googleapis.com/mediapipe-models/face_detector/blaze_face_short_range/ (ONNX) | TBD | TBD |

### Bake-off results (the M7 cluster_replay decision, run early in `eval/`)

On 878 quality-gated real faces, identity-split CV. Clustering F1 is the metric that
matters for grouping; all picks are Apache-2.0 (shippable).

| model | role | AUC | cluster F1 (+head) | note |
|---|---|---|---|---|
| **`auraface`** (R100 ArcFace) | **embedder — chosen** | 0.974 | 0.90 → **0.96** | ceiling-level commercial ArcFace; the clean 512-d D2 wanted |
| `sface` | embedder — fallback | 0.960 | 0.92 → 0.95 | 7× smaller (128-d); best CPU/speed option |
| **`scrfd_10g`** | **detector — chosen** | — | — | **97.7%** recall vs YuNet 70.7% — recovers 92% of scan misses |
| FaceNet (D2 default) | superseded | — | — | older/weaker than AuraFace; no longer the pick |

Runtime stack: `scrfd_10g` (detect) → 5-pt align → `auraface` (embed) → per-person
prototype → **agglomerative** clustering (grid-search winner, F1 0.94 ± 0.03; beat
HDBSCAN/Leiden/DBSCAN/Chinese-Whispers at this library scale). `sface` swaps in for
CPU/speed-constrained builds. License note: `scrfd_10g` ships on fal's Apache-2.0
AuraFace re-release (see D2 amendment) — InsightFace *code* is MIT; the fal pack is
the asserted commercial basis for the weights.

## Embedder candidates (pre-M7 evaluation — RESOLVED)

Decided: **`auraface`** (see the active table + bake-off above). The candidates below
were the D2-era shortlist before AuraFace/SFace were found and benchmarked.

| Candidate | License | Embedding dim | Notes | Status |
|-----------|---------|---------------|-------|--------|
| AuraFace (fal, ResNet100 ArcFace) | Apache 2.0 | 512 | Commercial-clean ArcFace; ceiling-level (AUC 0.974) on dogfood. | **Chosen.** |
| SFace (OpenCV Zoo) | Apache 2.0 | 128 | Best clustering of the candidates; 7× smaller. 128-d → schema note. | Fallback (CPU/speed). |
| FaceNet (Inception-ResNet-v1, Sandberg) | Apache 2.0 | 128 / 512 | Older; weaker than AuraFace. | Superseded. |
| OpenFace nn4.small2 | Apache 2.0 | 128 | Lower accuracy than FaceNet. | Superseded. |
| MobileFaceNet (clean re-implementation) | Verify per fork | 128 / 512 | Most forks reuse InsightFace weights → not commercial. | Not pursued. |

The A/B mechanism D2 deferred to a future `tools/cluster_replay/` was built early as
the standalone `eval/` harness (branch `feat/face-ingestion`) and run on the real
dogfood library — that is what produced the bake-off table above.

## Semantic image-embedding candidates (Stage 9 — Search & Discovery)

The semantic-search retrieval index (catalog v7 `embedding`) is produced by a
**swappable** embedder. The REAL model — **`google/siglip2-base-patch16-224`** — is
IMPLEMENTED (`native/core/src/semantic/onnx_embedder.cpp`, ONNX Runtime +
SentencePiece) and verified end-to-end (`semantic_onnx_test.cpp`: C++/Python parity
cosine > 0.999 + true `tree`/`dog`/`car` retrieval). The `deterministic-color` model
is the dependency-free fallback used when the model files are absent.

Model files are produced by `eval/retrieval/export_siglip2.py` (ONNX export) +
`eval/retrieval/prune_vocab.py` (vocab pruning) and are **hosted on the public
GitHub release** — the app downloads them on first run (`ModelFetcher`,
`pablo/lib/data/model_fetcher.dart`, pinned sha256s) into the merged models dir as
`semantic_image.onnx` / `semantic_text.onnx` / `semantic_tokenizer.model`, then
hot-swaps the embedder via `photo_semantic_reload` (no restart). Release:
**https://github.com/Watson-John/Pablo/releases/tag/models-v1**

| asset | bytes | sha256 |
|---|---|---|
| `semantic_image.fp16.onnx` (→ image tower) | 186,107,375 | `5af0a3ab1ab09fc9…0902a092` |
| `semantic_text_en.int8.onnx` (→ text tower, **v1 default**: vocab-pruned 256k→39,222 + int8; bit-identical for in-vocab English, OOV→unk) | 117,598,988 | `9ae05e04425b3c38…30a91b73` |
| `semantic_tokenizer.model` (Gemma SentencePiece, full vocab — pruning lives inside the ONNX graph) | 4,241,003 | `61a7b147390c6458…e1d4c8e2` |
| `semantic_text.int8.onnx` (optional full-vocab multilingual swap-in) | 283,060,272 | `0e1537896b1931bb…fa051ec81` |

**v1 download = ~308 MB total.** Full digests in the release's `checksums.txt`.
The native build auto-detects ONNX Runtime + SentencePiece and defines
`SEMANTIC_HAVE_ORT`. See [SPEC-09 §2](../../docs/specs/09-search-and-discovery.md).

| model | License | dim | input | tokenizer | fp32 size | status |
|-------|---------|-----|-------|-----------|-----------|--------|
| **`siglip2-base-patch16-224`** | Apache-2.0 | 768 | 224² RGB | Gemma SentencePiece | image 355 MB + text 1.1 GB + tok 4 MB | **implemented + verified** |
| `facebook/PE-Core-S16-384` | Apache-2.0 | 512 | 384² RGB | CLIP BPE | — | eval comparison target |
| `deterministic-color` (built-in) | — (Pablo) | 16 | any | word-lexicon | 0 | fallback |

**Quantization (measured + native-verified on brew ORT 1.26 arm64):** total fp32
**1501 MB** → all-fp16 **751 MB** → **recommended ship = fp16 image + int8 text =
469 MB**. Evidence: fp16 is bit-identical retrieval (cosine drift 1.00000) but a
DISK-ONLY win (CPU-EP inference ~15–20 % slower than fp32 on arm64; RSS unchanged);
int8 TEXT is near-lossless (query drift 0.965–0.991, mAP identical on 3,000 imgs) and
cuts the vocab-heavy tower 565→283 MB; int8 IMAGE is **disqualified** (embedding drift
cosine 0.81–0.85 — the documented CLIP int8 representation-collapse mode — and its
ConvInteger op needs ORT ≥1.26, absent in 1.19). Towers load LAZILY per side in
`onnx_embedder.cpp` (engine start ≈0 model RAM, measured 77 MB RSS vs ~3 GB eager).
fp16 conversion: `keep_io_types=True` + `node_block_list` = the graph's pre-existing
Cast nodes. Re-gate fp16/int8 with the `SemanticOnnx` gtest on every ORT upgrade.
Planned next cuts: Gemma vocab pruning 256k→~32k rows (−344 MB fp16, lossless for
in-vocab English; full table = optional multilingual download) and first-run download
to Application Support. `export_siglip2.py` prints sha256s for the manifest row once
the ship artifact is committed.

## Rejected models

| `model_id` | Reason rejected |
|---|---|
| `insightface_scrfd_*` (insightface zoo) | NC per InsightFace zoo. **But `scrfd_10g` ships via fal's Apache-2.0 AuraFace re-release** (now an active model) — see D2 amendment for the basis. |
| `insightface_mobilefacenet` | Non-commercial per InsightFace license. |
| `insightface_arcface_r100` | NC via InsightFace. Note: AuraFace is an Apache-2.0 ArcFace-R100 alternative (chosen). |
| `retinaface_resnet50` (InsightFace zoo variant) | Non-commercial per InsightFace license. |

## ONNX provider notes

Some providers require specific ONNX opset versions or model formats:

- **CoreML** (macOS): prefers opset 13+. BlazeFace converts cleanly. FaceNet may need opset bump on conversion.
- **WinML / DirectML** (Windows): opset 11–17 supported. Verify embedder converts; some Inception variants have op compatibility issues.
- **CPU EP** (universal baseline): supports everything.

Model conversion scripts (when needed) live in `native/models/scripts/` (created in M6 if conversion is needed).

## SHA256 verification

Run before commit:

```bash
cd native/models
sha256sum *.onnx > SHA256SUMS
# update the sha256 column in this file from SHA256SUMS
```

CI verifies file contents match the manifest on every build (added in M6).

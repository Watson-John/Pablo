# Pablo ML model manifest

Canonical list of ML model files Pablo ships with. Every model file in this directory must have a row in the table below. The model registry ([M6](/Users/johnwatson/.claude/plans/what-are-your-thoughts-scalable-puddle.md)) verifies SHA256, license flag, and version against this manifest at load time. **Models flagged `commercial: false` cannot be loaded unless the user explicitly opts in.**

Model files themselves are tracked via Git LFS (see [BUILD.md](../../BUILD.md)).

The face model source decision is recorded in [DECISIONS.md §D2](../../DECISIONS.md#d2-face-model-source--blazeface--permissively-licensed-embedder).

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
| `scrfd_10g` | `scrfd_10g_bnkps.onnx` | detection (bbox + 5 landmarks) | `1x3xHxW float32, RGB, (x-127.5)/128` | strides 8/16/32: score + bbox + kps | Apache 2.0 (fal re-release) | true | https://huggingface.co/fal/AuraFace-v1 | TBD (LFS commit) | 2026-06-14 |
| `auraface` | `auraface_glintr100.onnx` | 512-d face embedding | `1x3x112x112 float32, RGB, (x-127.5)/127.5` | `1x512 float32 (L2-normalize after)` | Apache 2.0 | true | https://huggingface.co/fal/AuraFace-v1 | TBD (LFS commit) | 2026-06-14 |
| `sface` | `face_recognition_sface_2021dec.onnx` | 128-d embedding (lightweight fallback) | `1x3x112x112 BGR (alignCrop)` | `1x128 float32 (L2-normalize)` | Apache 2.0 | true | https://github.com/opencv/opencv_zoo | TBD | 2026-06-14 |
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

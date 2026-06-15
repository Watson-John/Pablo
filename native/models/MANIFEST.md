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

| `model_id` | `file` | `purpose` | `inputs` | `outputs` | `license` | `commercial` | `source_url` | `sha256` | `added` |
|---|---|---|---|---|---|---|---|---|---|
| `blazeface_short` | `blazeface_short.onnx` | detection (short-range, ≤2m) | `1x3x128x128 float32, normalized [-1,1]` | `2016x16 anchors + 2016 scores` | Apache 2.0 | true | https://storage.googleapis.com/mediapipe-models/face_detector/blaze_face_short_range/float16/1/blaze_face_short_range.tflite (converted to ONNX) | TBD (populated on M7 commit) | TBD |
| `blazeface_full` | `blazeface_full.onnx` | detection (full-range, indoor) | `1x3x192x192 float32, normalized [-1,1]` | anchors + scores | Apache 2.0 | true | https://storage.googleapis.com/mediapipe-models/face_detector/blaze_face_full_range/ (converted to ONNX) | TBD | TBD |
| `face_embedder_v1` | TBD before M7 | 512-d face embedding | `1x3x160x160 float32` | `1x512 float32 L2-normalized` | Apache 2.0 / MIT required | true | TBD — see candidates below | TBD | TBD |

## Embedder candidates (pre-M7 evaluation)

The face embedder is the highest-impact model choice; it sets the ceiling on cluster purity. Must be Apache 2.0 / MIT / BSD compatible.

| Candidate | License | Embedding dim | Notes | Status |
|-----------|---------|---------------|-------|--------|
| FaceNet (Inception-ResNet-v1, Sandberg) | Apache 2.0 | 128 (native) or 512 (with re-projection head) | Mature, widely benchmarked. ONNX export available. 128-d would force schema change. | Default candidate. |
| OpenFace nn4.small2 | Apache 2.0 | 128 | Smaller. Lower accuracy than FaceNet. | Backup. |
| MobileFaceNet (training-data-clean re-implementation) | Verify per fork | 128 / 512 | **Most forks reuse InsightFace weights → not commercial.** Only a from-scratch retrain on commercial-clean data is acceptable. | Requires verification per source. |

**Embedder decision deadline:** before M7 task 2 starts. The cluster_replay harness from [tools/cluster_replay/](../../tools/cluster_replay/) (built in M7) will be the A/B mechanism — bake-off against a hand-labeled subset of the dogfood library.

## Rejected models

| `model_id` | Reason rejected |
|---|---|
| `insightface_scrfd_*` | Non-commercial training data per InsightFace license. See [DECISIONS.md §D2](../../docs/DECISIONS.md). |
| `insightface_mobilefacenet` | Same. |
| `insightface_arcface_r100` | Same. |
| `retinaface_resnet50` (InsightFace zoo variant) | Same. |

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

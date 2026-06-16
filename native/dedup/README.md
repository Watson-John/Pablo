# Pablo dedup — local near-duplicate photo detection

A one-time-sweep tool for finding **duplicate and near-duplicate images** across
a messy personal archive (RAW, scans, JPEGs). Standard hashing fails when the
"same" photo exists as a scanned negative, a scanned print, and an old digital
export — wildly different gamma, brightness, saturation, and contrast, sometimes
cropped. So instead of hashes we use a **learned copy-detection embedding**
([SSCD](https://github.com/facebookresearch/sscd-copy-detection)) that is
invariant to exactly those transformations.

> **Safety first.** This tool **never deletes anything.** Discards are *moved*
> to a quarantine directory and every move is recorded. Clusters are advisory
> until you act on them in the review UI.

It is a **standalone C++ project** under `native/dedup/`, deliberately separate
from the Flutter app's `photo_core` plugin so its heavy desktop-only
dependencies (OpenCV, FAISS, ONNX Runtime, LibRaw) never touch the app build.

---

## Pipeline

```
 1. enumerate     recursive walk -> (path, size, mtime, format)            [ingest.cpp]
 2. exact-dupe    XXH3-128 byte-identical + pHash trivial re-saves         [ingest.cpp]
 3. decode        LibRaw embedded thumb (RAW) / OpenCV; resize 288; sRGB   [decode.cpp]
 4. embed         SSCD via ONNX Runtime, batched, L2-normalized            [embed.cpp]
 5. index         FAISS IndexFlatIP (exact) top-k  (brute-force fallback)  [index.cpp]
 6. cluster       threshold the k-NN graph -> union-find components        [cluster.cpp]
 7. calibrate     hand-label pairs; pick threshold in the score gap        [dedup calibrate]
 8. review        local web UI; pre-selects keeper; quarantine discards    [server.cpp]
```

Embedding is the expensive stage, so results are **persisted** (`dedup.db` +
`vectors.f32`) and the sweep is **resumable** — re-running only embeds new files.

## Why these choices

- **SSCD, not CLIP/SigLIP.** SSCD is *copy-detection-specific*: it says "these
  are the same picture," not "these are both beaches." Semantic embeddings flood
  false positives here.
- **Exact flat index.** At 300k×512 floats the matrix is ~0.6 GB and an exact
  inner-product search is seconds-to-minutes with BLAS. Exactness matters near
  the duplicate threshold, where an approximate index's recall cliff would drop
  true pairs.
- **Embedded RAW thumbnails.** Full demosaicing is the worst bottleneck and
  pointless for a copy-detection signal — we pull the embedded JPEG instead.
- **The bottleneck is disk I/O + decode, not the GPU.** Decode is thread-pooled;
  the model runs comfortably on CPU.

## Dependencies

Managed by **vcpkg** (`vcpkg.json`), except ONNX Runtime.

| Dependency | Role | Required? |
|---|---|---|
| OpenCV (`+contrib`) | decode, resize, `img_hash` pHash | yes |
| xxHash | byte-identical content hash | yes |
| SQLite3 | metadata store | yes |
| yaml-cpp / nlohmann-json | config / API | yes |
| cpp-httplib | review server | yes |
| **ONNX Runtime** | SSCD inference | needed for `embed`; see below |
| FAISS | accelerated exact k-NN | optional (`faiss` feature); brute-force fallback otherwise |
| LibRaw | RAW embedded thumbnails | optional (`raw` feature); RAW skipped otherwise |

Each optional dependency is gated by a compile define (`DEDUP_HAVE_FAISS`,
`DEDUP_HAVE_ORT`, `DEDUP_HAVE_LIBRAW`) — the binary builds and runs without
them, the same optional-dependency discipline `photo_core` uses for libvips.

### ONNX Runtime (not via vcpkg)

Upstream ships official prebuilt C++ binaries that are lighter to consume and
much faster to obtain than building ORT from source. Download a release from
<https://github.com/microsoft/onnxruntime/releases>, extract it, and point CMake
at it:

```bash
export ONNXRUNTIME_ROOT=/opt/onnxruntime-linux-x64-1.20.0   # has include/ + lib/
# Windows: onnxruntime-win-x64-<ver>   macOS: onnxruntime-osx-arm64-<ver> (or -universal2)
```

Acceleration by platform, set via `embed.provider`:
- `cuda` — NVIDIA; use the `onnxruntime-gpu` build (Windows/Linux).
- `coreml` — macOS / Apple Silicon; uses the dedicated CoreML provider factory,
  so it engages on the official macOS ORT builds (Neural Engine / GPU). Falls
  back to CPU if unavailable.
- `cpu` — the portable default everywhere.

## Build

Targets **Linux, Windows, and macOS** (Apple Silicon or Intel).

```bash
# from native/dedup/
export VCPKG_ROOT=/path/to/vcpkg
export ONNXRUNTIME_ROOT=/path/to/onnxruntime-<os>-<arch>-<ver>

cmake --preset linux-release          # or windows-release / macos-release
cmake --build --preset linux-release
```

The `faiss;raw` manifest features are enabled by the presets. Drop them
(`-DVCPKG_MANIFEST_FEATURES=`) for a lean build that uses the fallbacks.

**Homebrew dev build (no vcpkg):** the CMake also finds system/Homebrew packages
directly. Install deps with `brew install opencv onnxruntime faiss libomp xxhash
yaml-cpp cpp-httplib nlohmann-json` and configure with
`-DCMAKE_PREFIX_PATH=$(brew --prefix opencv);...` plus
`-DONNXRUNTIME_ROOT=$(brew --prefix onnxruntime)`. FAISS is found via a manual
`find_library` fallback when no CMake config is present; without it, the build
uses the (slower) exact brute-force k-NN — fine for small sets, link FAISS for
the ~300k scale. On vcpkg builds, the `faiss` feature also needs `brew install
libomp` (AppleClang has no built-in OpenMP). `VCPKG_ROOT` must point at a vcpkg
checkout on macOS too (the arm64 CI runners bootstrap their own).

## Model: export SSCD to ONNX (one-time)

```bash
python tools/export_sscd_to_onnx.py \
    --checkpoint sscd_disc_mixup.torchscript.pt \
    --output models/sscd_disc_mixup.onnx
```

See the script header for getting the SSCD weights. SSCD is MIT-licensed; no
training required — the pretrained model already covers gamma/saturation/crop
invariance.

## Usage

```bash
# Sweep (resumable). Reads config.yaml; flags override fields.
./dedup scan --config config.yaml
./dedup scan --config config.yaml --roots /mnt/archive --threshold 0.82

# Sweep thresholds against already-computed embeddings (cheap; no re-embed).
./dedup calibrate --config config.yaml --from 0.70 --to 0.90 --step 0.02

# Open the review UI at http://127.0.0.1:8755
./dedup serve --config config.yaml
```

### Tuning for the machine (low-end PCs)

The SSCD embedding is the only heavy stage. Two knobs trade accuracy for speed:

```bash
# HASH-ONLY: skip SSCD entirely — no model, no GPU. ~10x faster; catches
# near-identical re-saves but NOT hard gamma/crop variants. Great first pass.
./dedup scan --config config.yaml --hash-only --algorithm blockmean --hamming 24

# Pick the perceptual hash:  phash (default) | blockmean | average | marr
./dedup scan --config config.yaml --algorithm blockmean
```

Measured on a 2k-image DISC21 subset (recall = labeled pairs co-clustered):

| Mode | Algorithm | Speed | Recall | Needs model/GPU |
|---|---|---|---|---|
| hash-only | phash-64 | ~9x | ~11% | no |
| hash-only | blockmean-256 | ~9x | ~22% | no |
| full | phash + SSCD | 1x | ~66% | yes |

So: **hash-only blockmean** for a fast, dependency-light pass on a weak PC;
**full SSCD** when you need the hard "same photo, very different pixels" cases.
A bigger perceptual hash (blockmean/marr) catches more in hash-only mode at the
cost of a larger Hamming budget.

## Calibration & pitfalls

- **Calibrate the threshold.** Hand-label ~20 known dup pairs and ~20 hard
  negatives, then set the threshold in the score gap between them. Start ~0.80.
- **Hard negatives** (burst shots, a photo series on the same backdrop) sit
  right at the threshold — the #1 false-positive source. Keep it conservative;
  optionally enable `cluster.exif_time_guard`.
- **Transitive drift.** A~B~C chaining can merge unrelated images into one
  mega-cluster. `cluster.mutual_knn` (require reciprocal neighbours) and the
  `max_cluster_size` flag guard against it.

## Layout

```
native/dedup/
  CMakeLists.txt  CMakePresets.json  vcpkg.json  config.example.yaml
  cmake/FindOnnxRuntime.cmake
  include/dedup/*.h     # stage interfaces
  src/*.cpp             # stage implementations + main.cpp (scan|serve|calibrate)
  web/                  # static review UI
  tools/export_sscd_to_onnx.py
```

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
```

For GPU, use the `-gpu` build and set `embed.provider: cuda` in the config.

## Build

```bash
# from native/dedup/
export VCPKG_ROOT=/path/to/vcpkg
export ONNXRUNTIME_ROOT=/path/to/onnxruntime-<os>-x64-<ver>

cmake --preset linux-release          # or windows-release
cmake --build --preset linux-release
```

The `faiss;raw` manifest features are enabled by the presets. Drop them
(`-DVCPKG_MANIFEST_FEATURES=`) for a lean build that uses the fallbacks.

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

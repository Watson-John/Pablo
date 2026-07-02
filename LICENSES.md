# Pablo backend — third-party license inventory

Per-library license and link-mode inventory for the Pablo native backend. This file is canonical: if a library is not in this table, the build does not depend on it. Adding a new dependency requires adding a row here, with the license verified, *before* the dependency lands in `CMakeLists.txt`.

The LGPL link policy is recorded in [DECISIONS.md §D5](docs/DECISIONS.md). Link-mode for every LGPL library must be **dynamic**. CI enforces this via grep against `add_library.*STATIC` for blacklisted names.

## Library inventory

| Library | Version | License | Commercial OK? | Link mode | Used in (milestone) | Notes |
|---------|---------|---------|----------------|-----------|---------------------|-------|
| libvips | 8.15+ | LGPL 2.1+ | Yes (dyn link) | **dynamic** | M3 | Thumbnail front door; vips_thumbnail shrink-on-load |
| libjpeg-turbo | 3.0+ | IJG + BSD-style | Yes | static or dynamic | M3 | JPEG hot path; ships inside libvips also |
| libheif | 1.18+ | LGPL 3 | Yes (dyn link) | **dynamic** | M5 | HEIC + AVIF. **Do not link HEVC encoders (x265 is GPL)** — decode only. |
| libjxl | 0.10+ | BSD 3-clause + patents grant | Yes | static or dynamic | M5 | JPEG XL reference impl |
| LibRaw | 0.21+ | LGPL 2.1 or CDDL 1.0 | Yes (dyn link) | **dynamic** | M5 | Choose LGPL variant for consistency. Embedded preview path only (D4). |
| libexif | 0.6.24+ | LGPL 2.1+ | Yes (dyn link) | **dynamic** | M5 | EXIF read only |
| FFmpeg (libavformat/libavcodec/libavutil/libswscale) | 5.0+ | LGPL 2.1+ (default build) | Yes (dyn link) | **dynamic** | §11 (Stage V3) | Video probe / poster-frame / trim remux. Optional (PHOTO_HAVE_FFMPEG). **Use the LGPL build — no GPL-only components (x264/x265 encoders); decode + stream-copy only.** |
| pugixml | 1.14+ | MIT | Yes | static | M5 | XMP/IPTC custom parser backend |
| LMDB | 0.9.31+ | OpenLDAP Public License | Yes | static | M3 | Blob cache; permissive license |
| SQLite | 3.45+ | Public domain | Yes | static (amalgamation) | M3 | Catalog; WAL mode |
| BLAKE3 | 1.5+ | CC0 or Apache 2.0 dual | Yes | static | M3 | Cache key hashing |
| GoogleTest | 1.14+ | BSD 3-clause | Yes | static (test only) | M1+ | Unit tests; not shipped |
| Google Benchmark | 1.8+ | Apache 2.0 | Yes | static (bench only) | M2+ | Perf harness; not shipped |
| ONNX Runtime | 1.18+ | MIT | Yes | **dynamic** (per-platform binaries) | M6 | Use pre-built per-OS binaries |
| USearch | 2.x | Apache 2.0 | Yes | static | M8 | HNSW vector index |
| HDBSCAN (C++ port) | TBD | Per implementation | TBD | TBD | M7 | Verify before integration; candidates: hdbscan-cpp (BSD), or port from sklearn (BSD) |
| MediaPipe BlazeFace (ONNX) | model file | Apache 2.0 | Yes | model file (no link) | M7 | Detection model |
| Permissive face embedder | TBD | Apache 2.0 / MIT required | Yes | model file (no link) | M7 | See [DECISIONS.md §D2](docs/DECISIONS.md) revisit trigger |
| Flutter SDK | 3.X | BSD 3-clause | Yes | dynamic (system) | all | UI framework |
| Dart `ffi` package | with SDK | BSD 3-clause | Yes | n/a | M2+ | |
| Dart `ffigen` | 12+ | BSD 3-clause | Yes | dev-only | M2+ | Code generator; runtime-free |

## Per-platform OS deps (not shipped, system-provided)

| Platform | Library | License | Notes |
|----------|---------|---------|-------|
| Windows | WinML / Windows Runtime | MS EULA | OS-provided; not redistributed |
| Windows | DirectML | MS EULA | OS-provided; D3D12 dep |
| macOS | CoreML | Apple SLA | OS-provided |
| macOS | Metal | Apple SLA | OS-provided |
| Linux | (none required) | n/a | CPU baseline; CUDA optional and user-installed |

## Models inventory

See [native/models/MANIFEST.md](native/models/MANIFEST.md) for per-model license, source, and SHA256.

## Explicit non-dependencies (rejected)

These were considered and rejected for licensing reasons. Do not add them without a new decision record:

| Library | Reason rejected |
|---------|-----------------|
| **Exiv2** | GPLv2; would require commercial license. Replaced by libexif + custom XMP shim (see [DECISIONS.md §D1](docs/DECISIONS.md)). |
| **x265** | GPLv2 + commercial dual-license. We only need HEIF *decode*; libheif builds without x265. |
| **InsightFace models (SCRFD, MobileFaceNet, ArcFace)** | Code MIT, weights non-commercial. Replaced by BlazeFace + permissive embedder (see [DECISIONS.md §D2](docs/DECISIONS.md)). |
| **Faiss** | License OK (MIT) but HNSW does not support removal and the project favors USearch's mutable embedded design. Not a license rejection. |
| **ExifTool** | Artistic/GPL; subprocess pattern awkward for shipped app. |

## LGPL relink obligation

For each dynamically-linked LGPL library, the Pablo installer ships:

1. The exact `.dylib` / `.dll` / `.so` file used at build time, named so the user can replace it.
2. A `RELINKING.md` in the installer payload explaining how to substitute a user-built version.

CI verifies the LGPL `.so`/`.dylib`/`.dll` files are present in the installer payload as a post-build step (added in M3 or later when packaging starts).

## License check in CI

```bash
# scripts/check_licenses.sh — run in CI
set -euo pipefail

# 1. No static linkage for LGPL libs.
LGPL_NAMES="vips heif raw exif"
for name in $LGPL_NAMES; do
  if grep -rnE "add_library\([^)]*${name}[^)]*STATIC" native packages; then
    echo "FAIL: LGPL library '$name' has STATIC linkage"
    exit 1
  fi
done

# 2. No rejected libraries.
REJECTED="exiv2 x265"
for name in $REJECTED; do
  if grep -rnEi "find_package\(\s*${name}|pkg_check_modules\([^)]*${name}|target_link_libraries\([^)]*${name}" native packages; then
    echo "FAIL: rejected library '$name' referenced"
    exit 1
  fi
done

echo "License checks passed"
```

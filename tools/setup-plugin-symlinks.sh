#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Pablo contributors.
#
# Sets up the per-developer symlinks the photo_native plugin needs to find
# the photo_core C++ sources during CocoaPods install on macOS. CocoaPods
# symlinks plugins into the app's .symlinks/ directory, which breaks logical
# resolution of relative `..` symlink targets — so we use absolute targets
# computed from each developer's checkout location.
#
# Run this after cloning the repo and after any directory move:
#     tools/setup-plugin-symlinks.sh
#
# The created symlinks are gitignored.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
mac_root="$repo_root/packages/photo_native/macos"

if [[ ! -d "$mac_root" ]]; then
    echo "error: $mac_root not found" >&2
    exit 1
fi

# 1. Directory symlink used by HEADER_SEARCH_PATHS.
ln -sfn "$repo_root/native/core" "$mac_root/_native_core"

# 2. Individual file symlinks under Classes/core/. CocoaPods's source_files
#    glob refuses to traverse directory symlinks across the .symlinks hop,
#    but individual file symlinks (with absolute targets) work.
mkdir -p "$mac_root/Classes/core"
for rel in api/c_api.cpp \
           runtime/engine.cpp \
           runtime/slot_store.cpp \
           runtime/event_ring.cpp \
           runtime/job_system.cpp \
           thumb/slot.cpp \
           thumb/thumb_service.cpp \
           thumb/thumb_cache.cpp \
           util/log.cpp \
           catalog/catalog.cpp \
           exif/exif.cpp \
           semantic/embedder.cpp \
           semantic/onnx_embedder.cpp \
           semantic/semantic_search.cpp \
           semantic/semantic_service.cpp \
           codec/codec.cpp \
           faces/detector.cpp \
           faces/align.cpp \
           faces/embed.cpp \
           faces/cluster.cpp \
           faces/prototype.cpp \
           faces/store.cpp \
           faces/face_service.cpp; do
    ln -sfn "$repo_root/native/core/src/$rel" \
            "$mac_root/Classes/core/$(basename "$rel")"
done

echo "Linked photo_core sources into $mac_root."
echo "Run 'flutter build macos' or 'flutter run -d macos' from pablo/."

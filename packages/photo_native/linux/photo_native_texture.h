// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// PhotoNativeTexture (Linux) — FlPixelBufferTexture subclass that wraps a
// native photo_core slot. copy_pixels runs on Flutter's render thread.

#ifndef PACKAGES_PHOTO_NATIVE_LINUX_PHOTO_NATIVE_TEXTURE_H_
#define PACKAGES_PHOTO_NATIVE_LINUX_PHOTO_NATIVE_TEXTURE_H_

#include <flutter_linux/flutter_linux.h>

#include <stdint.h>

#include "photo_core.h"

G_BEGIN_DECLS

#define PHOTO_TYPE_NATIVE_TEXTURE (photo_native_texture_get_type())
G_DECLARE_FINAL_TYPE(PhotoNativeTexture, photo_native_texture, PHOTO,
                     NATIVE_TEXTURE, FlPixelBufferTexture)

PhotoNativeTexture *photo_native_texture_new(uint64_t slot_id,
                                             photo_engine_t *engine);

G_END_DECLS

#endif  // PACKAGES_PHOTO_NATIVE_LINUX_PHOTO_NATIVE_TEXTURE_H_

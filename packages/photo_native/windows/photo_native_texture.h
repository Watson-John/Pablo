// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// PhotoNativeTexture (Windows) — flutter::PixelBufferTexture that wraps a
// native photo_core slot. The CopyPixelBuffer callback runs on Flutter's
// render thread; we acquire the slot's current frame, expose it as a
// FlutterDesktopPixelBuffer, and arrange release via the release_callback.

#ifndef PACKAGES_PHOTO_NATIVE_WINDOWS_PHOTO_NATIVE_TEXTURE_H_
#define PACKAGES_PHOTO_NATIVE_WINDOWS_PHOTO_NATIVE_TEXTURE_H_

#include <flutter/texture_registrar.h>

#include <cstdint>
#include <memory>
#include <mutex>

#include "photo_core.h"

namespace photo_native {

class PhotoNativeTexture {
public:
    PhotoNativeTexture(uint64_t slot_id, photo_engine_t *engine,
                       flutter::TextureRegistrar *registrar);
    ~PhotoNativeTexture();

    PhotoNativeTexture(const PhotoNativeTexture &) = delete;
    PhotoNativeTexture &operator=(const PhotoNativeTexture &) = delete;

    int64_t texture_id() const noexcept { return texture_id_; }

private:
    const FlutterDesktopPixelBuffer *Copy(size_t requested_w,
                                          size_t requested_h);

    uint64_t                   slot_id_;
    photo_engine_t            *engine_;
    flutter::TextureRegistrar *registrar_;
    int64_t                    texture_id_{-1};
    std::unique_ptr<flutter::TextureVariant> variant_;

    // Pixel buffer + last-released borrow handoff. CopyPixelBuffer runs on
    // the render thread; it sets release_ctx_ then returns the buffer. The
    // release_callback drops the borrow back into photo_slot_release.
    std::mutex                 mu_;
    FlutterDesktopPixelBuffer  buffer_{};
    void                      *pending_release_ctx_{nullptr};
};

}  // namespace photo_native

#endif  // PACKAGES_PHOTO_NATIVE_WINDOWS_PHOTO_NATIVE_TEXTURE_H_

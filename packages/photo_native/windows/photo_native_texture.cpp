// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.

#include "photo_native_texture.h"

#include <cstring>

namespace photo_native {

PhotoNativeTexture::PhotoNativeTexture(uint64_t slot_id,
                                       photo_engine_t *engine,
                                       flutter::TextureRegistrar *registrar)
    : slot_id_(slot_id), engine_(engine), registrar_(registrar) {
    variant_ = std::make_unique<flutter::TextureVariant>(
        flutter::PixelBufferTexture(
            [this](size_t requested_w, size_t requested_h)
                -> const FlutterDesktopPixelBuffer * {
                return this->Copy(requested_w, requested_h);
            }));
    texture_id_ = registrar_->RegisterTexture(variant_.get());
}

PhotoNativeTexture::~PhotoNativeTexture() {
    if (texture_id_ != -1) {
        registrar_->UnregisterTexture(texture_id_);
        texture_id_ = -1;
    }
    // Release any outstanding borrow that Flutter never returned (shouldn't
    // happen in practice since unregister blocks pending callbacks).
    std::lock_guard lk(mu_);
    if (pending_release_ctx_ != nullptr) {
        photo_slot_release(engine_, pending_release_ctx_);
        pending_release_ctx_ = nullptr;
    }
}

const FlutterDesktopPixelBuffer *PhotoNativeTexture::Copy(
    size_t /*requested_w*/, size_t /*requested_h*/) {
    photo_frame_view_t view{};
    if (!photo_slot_acquire_latest(engine_, slot_id_, &view)) {
        return nullptr;
    }

    std::lock_guard lk(mu_);

    // If Flutter still holds the previous buffer, drop our older borrow
    // first to avoid leaking. The Flutter docs say release_callback runs
    // before the next Copy; in practice we defend anyway.
    if (pending_release_ctx_ != nullptr) {
        photo_slot_release(engine_, pending_release_ctx_);
        pending_release_ctx_ = nullptr;
    }

    pending_release_ctx_ = view.release_ctx;
    buffer_.buffer = view.bgra;
    buffer_.width = view.width;
    buffer_.height = view.height;
    buffer_.release_context = this;
    buffer_.release_callback = [](void *user_data) {
        auto *self = static_cast<PhotoNativeTexture *>(user_data);
        std::lock_guard lk(self->mu_);
        if (self->pending_release_ctx_ != nullptr) {
            photo_slot_release(self->engine_, self->pending_release_ctx_);
            self->pending_release_ctx_ = nullptr;
        }
    };
    return &buffer_;
}

}  // namespace photo_native

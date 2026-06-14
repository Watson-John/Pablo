// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.

#include "photo_native_texture.h"

#include <string.h>

struct _PhotoNativeTexture {
    FlPixelBufferTexture parent_instance;

    uint64_t        slot_id;
    photo_engine_t *engine;

    // Single-cell hand-off: copy_pixels acquires a borrow into `pixels` and
    // releases the previous borrow. Flutter consumes `pixels` synchronously
    // within copy_pixels, so we keep one borrow alive at a time.
    GMutex          mu;
    void           *pending_release_ctx;
    uint8_t        *staging;
    gsize           staging_capacity;
};

G_DEFINE_TYPE(PhotoNativeTexture, photo_native_texture,
              fl_pixel_buffer_texture_get_type())

static gboolean photo_native_texture_copy_pixels(FlPixelBufferTexture *texture,
                                                  const uint8_t **out_buffer,
                                                  uint32_t *width,
                                                  uint32_t *height,
                                                  GError **error) {
    auto *self = PHOTO_NATIVE_TEXTURE(texture);

    photo_frame_view_t view;
    memset(&view, 0, sizeof(view));
    if (!photo_slot_acquire_latest(self->engine, self->slot_id, &view)) {
        if (error) {
            *error = g_error_new(g_quark_from_static_string("photo_native"), 1,
                                 "no frame available for slot %llu",
                                 (unsigned long long)self->slot_id);
        }
        return FALSE;
    }

    g_mutex_lock(&self->mu);

    // Flutter requires a tightly packed RGBA buffer pointer that stays live
    // until copy_pixels returns. We re-pack into a staging buffer if needed
    // (the source is BGRA from the engine).
    gsize needed = (gsize)view.width * view.height * 4;
    if (self->staging_capacity < needed) {
        g_free(self->staging);
        self->staging = (uint8_t *)g_malloc(needed);
        self->staging_capacity = needed;
    }

    // BGRA -> RGBA swap (Flutter expects RGBA via FlPixelBufferTexture).
    const uint8_t *src = view.bgra;
    const gsize row_bytes = (gsize)view.width * 4;
    for (uint32_t y = 0; y < view.height; ++y) {
        const uint8_t *src_row = src + (gsize)y * view.stride;
        uint8_t *dst_row = self->staging + (gsize)y * row_bytes;
        for (uint32_t x = 0; x < view.width; ++x) {
            dst_row[x * 4 + 0] = src_row[x * 4 + 2];  // R <- B
            dst_row[x * 4 + 1] = src_row[x * 4 + 1];  // G
            dst_row[x * 4 + 2] = src_row[x * 4 + 0];  // B <- R
            dst_row[x * 4 + 3] = src_row[x * 4 + 3];  // A
        }
    }

    // Release the previous borrow if any, then the current one (Flutter only
    // needs the bytes for the duration of this call since we copied above).
    if (self->pending_release_ctx != nullptr) {
        photo_slot_release(self->engine, self->pending_release_ctx);
        self->pending_release_ctx = nullptr;
    }
    photo_slot_release(self->engine, view.release_ctx);

    *out_buffer = self->staging;
    *width = view.width;
    *height = view.height;

    g_mutex_unlock(&self->mu);
    return TRUE;
}

static void photo_native_texture_dispose(GObject *object) {
    auto *self = PHOTO_NATIVE_TEXTURE(object);
    g_mutex_lock(&self->mu);
    if (self->pending_release_ctx != nullptr) {
        photo_slot_release(self->engine, self->pending_release_ctx);
        self->pending_release_ctx = nullptr;
    }
    g_free(self->staging);
    self->staging = nullptr;
    self->staging_capacity = 0;
    g_mutex_unlock(&self->mu);
    g_mutex_clear(&self->mu);
    G_OBJECT_CLASS(photo_native_texture_parent_class)->dispose(object);
}

static void photo_native_texture_class_init(PhotoNativeTextureClass *klass) {
    FL_PIXEL_BUFFER_TEXTURE_CLASS(klass)->copy_pixels =
        photo_native_texture_copy_pixels;
    G_OBJECT_CLASS(klass)->dispose = photo_native_texture_dispose;
}

static void photo_native_texture_init(PhotoNativeTexture *self) {
    g_mutex_init(&self->mu);
    self->pending_release_ctx = nullptr;
    self->staging = nullptr;
    self->staging_capacity = 0;
}

PhotoNativeTexture *photo_native_texture_new(uint64_t slot_id,
                                             photo_engine_t *engine) {
    auto *self = PHOTO_NATIVE_TEXTURE(
        g_object_new(photo_native_texture_get_type(), nullptr));
    self->slot_id = slot_id;
    self->engine = engine;
    return self;
}

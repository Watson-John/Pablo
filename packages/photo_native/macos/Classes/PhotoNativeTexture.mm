// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.

#import "PhotoNativeTexture.h"

#include <string.h>

#include "photo_core.h"

@interface PhotoNativeTexture () {
    uint64_t              _slotId;
    photo_engine_t*       _engine;
    CVPixelBufferPoolRef  _pool;
    uint32_t              _poolW;
    uint32_t              _poolH;
}
@end

@implementation PhotoNativeTexture

- (instancetype)initWithSlotId:(uint64_t)slotId engine:(photo_engine_t *)engine {
    self = [super init];
    if (self) {
        _slotId = slotId;
        _engine = engine;
        _pool = NULL;
        _poolW = 0;
        _poolH = 0;
    }
    return self;
}

- (void)dealloc {
    if (_pool != NULL) {
        CVPixelBufferPoolRelease(_pool);
        _pool = NULL;
    }
}

- (BOOL)_ensurePool:(uint32_t)w height:(uint32_t)h {
    if (_pool != NULL && _poolW == w && _poolH == h) return YES;
    if (_pool != NULL) {
        CVPixelBufferPoolRelease(_pool);
        _pool = NULL;
    }
    NSDictionary *pixelAttrs = @{
        (id)kCVPixelBufferPixelFormatTypeKey       : @(kCVPixelFormatType_32BGRA),
        (id)kCVPixelBufferWidthKey                 : @(w),
        (id)kCVPixelBufferHeightKey                : @(h),
        (id)kCVPixelBufferIOSurfacePropertiesKey   : @{},
        (id)kCVPixelBufferMetalCompatibilityKey    : @YES,
    };
    CVReturn r = CVPixelBufferPoolCreate(
        NULL, NULL, (__bridge CFDictionaryRef)pixelAttrs, &_pool);
    if (r != kCVReturnSuccess || _pool == NULL) {
        return NO;
    }
    _poolW = w;
    _poolH = h;
    return YES;
}

- (CVPixelBufferRef _Nullable)copyPixelBuffer {
    if (_engine == NULL) return NULL;

    photo_frame_view_t view;
    memset(&view, 0, sizeof(view));
    if (!photo_slot_acquire_latest(_engine, _slotId, &view)) {
        return NULL;
    }

    if (![self _ensurePool:view.width height:view.height]) {
        photo_slot_release(_engine, view.release_ctx);
        return NULL;
    }

    CVPixelBufferRef pb = NULL;
    CVReturn r = CVPixelBufferPoolCreatePixelBuffer(NULL, _pool, &pb);
    if (r != kCVReturnSuccess || pb == NULL) {
        photo_slot_release(_engine, view.release_ctx);
        return NULL;
    }

    CVPixelBufferLockBaseAddress(pb, 0);
    uint8_t *dst = (uint8_t *)CVPixelBufferGetBaseAddress(pb);
    size_t dstStride = CVPixelBufferGetBytesPerRow(pb);
    size_t srcStride = view.stride;
    if (dstStride == srcStride) {
        memcpy(dst, view.bgra, dstStride * view.height);
    } else {
        size_t rowBytes = (size_t)view.width * 4;
        for (uint32_t y = 0; y < view.height; ++y) {
            memcpy(dst + y * dstStride, view.bgra + y * srcStride, rowBytes);
        }
    }
    CVPixelBufferUnlockBaseAddress(pb, 0);

    photo_slot_release(_engine, view.release_ctx);
    return pb;  // Flutter releases.
}

@end

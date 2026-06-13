// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// PhotoNativeTexture.h — FlutterTexture implementation that wraps a native
// photo_core slot. Implements -copyPixelBuffer by acquiring the slot's
// current frame, copying into a pooled CVPixelBuffer, and releasing the
// borrow. Per FlutterTexture protocol: -copyPixelBuffer is invoked on the
// raster thread; everything in this class is written assuming that.

#import <FlutterMacOS/FlutterMacOS.h>
#import <CoreVideo/CoreVideo.h>

#include <stdint.h>

// Forward declare the C ABI engine handle without pulling photo_core.h into
// this header (kept clean for Pod's public_header_files).
typedef struct photo_engine photo_engine_t;

NS_ASSUME_NONNULL_BEGIN

@interface PhotoNativeTexture : NSObject <FlutterTexture>

@property(nonatomic, assign) int64_t textureId;

- (instancetype)initWithSlotId:(uint64_t)slotId
                        engine:(photo_engine_t *)engine NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END

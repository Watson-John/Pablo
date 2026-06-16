// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.

#import "PhotoNativePlugin.h"
#import "PhotoNativeTexture.h"

#include "photo_core.h"

@interface PhotoNativePlugin () {
    NSObject<FlutterTextureRegistry> *_textureRegistry;
    NSMutableDictionary<NSNumber *, PhotoNativeTexture *> *_texturesBySlotId;
    photo_engine_t *_engine;
}
@end

@implementation PhotoNativePlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
    FlutterMethodChannel *channel = [FlutterMethodChannel
        methodChannelWithName:@"photo_native/texture_registry"
              binaryMessenger:registrar.messenger];
    PhotoNativePlugin *instance =
        [[PhotoNativePlugin alloc] initWithRegistrar:registrar];
    [registrar addMethodCallDelegate:instance channel:channel];
}

- (instancetype)initWithRegistrar:
    (NSObject<FlutterPluginRegistrar> *)registrar {
    self = [super init];
    if (self) {
        _textureRegistry = registrar.textures;
        _texturesBySlotId = [NSMutableDictionary dictionary];
        _engine = NULL;
    }
    return self;
}

- (void)handleMethodCall:(FlutterMethodCall *)call
                  result:(FlutterResult)result {
    NSString *method = call.method;

    if ([method isEqualToString:@"attachEngine"]) {
        NSNumber *handle = call.arguments[@"engineHandle"];
        if (handle == nil) {
            result([FlutterError errorWithCode:@"BAD_ARGS"
                                       message:@"missing engineHandle"
                                       details:nil]);
            return;
        }
        _engine = (photo_engine_t *)(uintptr_t)[handle unsignedLongLongValue];
        result(nil);
        return;
    }

    if ([method isEqualToString:@"register"]) {
        if (_engine == NULL) {
            result([FlutterError errorWithCode:@"NOT_ATTACHED"
                                       message:@"attachEngine must be called first"
                                       details:nil]);
            return;
        }
        NSNumber *slotId = call.arguments[@"slotId"];
        if (slotId == nil) {
            result([FlutterError errorWithCode:@"BAD_ARGS"
                                       message:@"missing slotId"
                                       details:nil]);
            return;
        }
        uint64_t sid = [slotId unsignedLongLongValue];
        PhotoNativeTexture *tex =
            [[PhotoNativeTexture alloc] initWithSlotId:sid engine:_engine];
        int64_t textureId = [_textureRegistry registerTexture:tex];
        tex.textureId = textureId;
        _texturesBySlotId[@(sid)] = tex;
        result(@(textureId));
        return;
    }

    if ([method isEqualToString:@"markFrameAvailable"]) {
        NSNumber *slotId = call.arguments[@"slotId"];
        if (slotId != nil) {
            PhotoNativeTexture *tex =
                _texturesBySlotId[@([slotId unsignedLongLongValue])];
            if (tex) {
                [_textureRegistry textureFrameAvailable:tex.textureId];
            }
        }
        result(nil);
        return;
    }

    if ([method isEqualToString:@"unregister"]) {
        NSNumber *slotId = call.arguments[@"slotId"];
        if (slotId == nil) {
            result(nil);
            return;
        }
        uint64_t sid = [slotId unsignedLongLongValue];
        PhotoNativeTexture *tex = _texturesBySlotId[@(sid)];
        if (tex) {
            [_textureRegistry unregisterTexture:tex.textureId];
            [_texturesBySlotId removeObjectForKey:@(sid)];
        }
        result(nil);
        return;
    }

    result(FlutterMethodNotImplemented);
}

- (void)dealloc {
    // Plugin lifetime is the engine's; clearing the map drops all textures.
    [_texturesBySlotId removeAllObjects];
}

@end

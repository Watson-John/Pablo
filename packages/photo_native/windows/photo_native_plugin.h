// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.

#ifndef PACKAGES_PHOTO_NATIVE_WINDOWS_PHOTO_NATIVE_PLUGIN_H_
#define PACKAGES_PHOTO_NATIVE_WINDOWS_PHOTO_NATIVE_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <cstdint>
#include <memory>
#include <unordered_map>

#include "photo_core.h"
#include "photo_native_texture.h"

namespace photo_native {

class PhotoNativePlugin : public flutter::Plugin {
public:
    static void RegisterWithRegistrar(
        flutter::PluginRegistrarWindows *registrar);

    explicit PhotoNativePlugin(flutter::TextureRegistrar *texture_registrar);
    ~PhotoNativePlugin() override;

    PhotoNativePlugin(const PhotoNativePlugin &) = delete;
    PhotoNativePlugin &operator=(const PhotoNativePlugin &) = delete;

private:
    void HandleMethodCall(
        const flutter::MethodCall<flutter::EncodableValue> &call,
        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

    flutter::TextureRegistrar *texture_registrar_;
    photo_engine_t *engine_;
    std::unordered_map<uint64_t, std::unique_ptr<PhotoNativeTexture>> textures_;
};

}  // namespace photo_native

#endif  // PACKAGES_PHOTO_NATIVE_WINDOWS_PHOTO_NATIVE_PLUGIN_H_

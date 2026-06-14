// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.

#include "photo_native_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <cstdint>
#include <memory>
#include <string>
#include <variant>

namespace photo_native {

namespace {

template <typename T>
const T *GetArg(const flutter::EncodableMap *args, const char *key) {
    if (args == nullptr) return nullptr;
    auto it = args->find(flutter::EncodableValue(key));
    if (it == args->end()) return nullptr;
    return std::get_if<T>(&it->second);
}

}  // namespace

// static
void PhotoNativePlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
    auto channel = std::make_unique<
        flutter::MethodChannel<flutter::EncodableValue>>(
        registrar->messenger(), "photo_native/texture_registry",
        &flutter::StandardMethodCodec::GetInstance());

    auto plugin = std::make_unique<PhotoNativePlugin>(registrar->texture_registrar());

    channel->SetMethodCallHandler(
        [plugin_pointer = plugin.get()](const auto &call, auto result) {
            plugin_pointer->HandleMethodCall(call, std::move(result));
        });

    registrar->AddPlugin(std::move(plugin));
}

PhotoNativePlugin::PhotoNativePlugin(flutter::TextureRegistrar *texture_registrar)
    : texture_registrar_(texture_registrar), engine_(nullptr) {}

PhotoNativePlugin::~PhotoNativePlugin() {
    textures_.clear();
}

void PhotoNativePlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    const auto *args = std::get_if<flutter::EncodableMap>(call.arguments());

    if (call.method_name() == "attachEngine") {
        const auto *handle = GetArg<int64_t>(args, "engineHandle");
        if (handle == nullptr) {
            result->Error("BAD_ARGS", "missing engineHandle");
            return;
        }
        engine_ = reinterpret_cast<photo_engine_t *>(
            static_cast<uintptr_t>(*handle));
        result->Success();
        return;
    }

    if (call.method_name() == "register") {
        if (engine_ == nullptr) {
            result->Error("NOT_ATTACHED", "attachEngine must be called first");
            return;
        }
        const auto *slot_id_arg = GetArg<int64_t>(args, "slotId");
        if (slot_id_arg == nullptr) {
            result->Error("BAD_ARGS", "missing slotId");
            return;
        }
        uint64_t sid = static_cast<uint64_t>(*slot_id_arg);
        auto tex = std::make_unique<PhotoNativeTexture>(
            sid, engine_, texture_registrar_);
        int64_t texture_id = tex->texture_id();
        textures_[sid] = std::move(tex);
        result->Success(flutter::EncodableValue(texture_id));
        return;
    }

    if (call.method_name() == "unregister") {
        const auto *slot_id_arg = GetArg<int64_t>(args, "slotId");
        if (slot_id_arg == nullptr) {
            result->Success();
            return;
        }
        uint64_t sid = static_cast<uint64_t>(*slot_id_arg);
        textures_.erase(sid);
        result->Success();
        return;
    }

    result->NotImplemented();
}

}  // namespace photo_native

// Flutter Windows expects this C entry point to register the plugin.
extern "C" __declspec(dllexport) void PhotoNativePluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
    photo_native::PhotoNativePlugin::RegisterWithRegistrar(
        flutter::PluginRegistrarManager::GetInstance()
            ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}

// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// Public C-ABI entry point for the Flutter Windows plugin registrant
// (generated_plugin_registrant.cc does `#include
// <photo_native/photo_native_plugin.h>` and calls the function below).
//
// This header is intentionally minimal and free of private/native
// dependencies so the app target can include it. The full C++ implementation
// (the PhotoNativePlugin class) lives in the private header
// ../../photo_native_plugin.h, included only by the plugin .cpp.

#ifndef FLUTTER_PLUGIN_PHOTO_NATIVE_PLUGIN_H_
#define FLUTTER_PLUGIN_PHOTO_NATIVE_PLUGIN_H_

#include <flutter_plugin_registrar.h>

#ifdef FLUTTER_PLUGIN_IMPL
#define FLUTTER_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FLUTTER_PLUGIN_EXPORT __declspec(dllimport)
#endif

#if defined(__cplusplus)
extern "C" {
#endif

FLUTTER_PLUGIN_EXPORT void PhotoNativePluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar);

#if defined(__cplusplus)
}  // extern "C"
#endif

#endif  // FLUTTER_PLUGIN_PHOTO_NATIVE_PLUGIN_H_

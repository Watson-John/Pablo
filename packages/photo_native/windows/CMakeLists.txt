# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Pablo contributors.
#
# Flutter Windows plugin CMake. Compiled when `flutter run -d windows` is
# invoked against an app that depends on photo_native.

cmake_minimum_required(VERSION 3.14)
set(PROJECT_NAME "photo_native")
project(${PROJECT_NAME} LANGUAGES CXX)

# The Flutter Windows runner expects `${PLUGIN_NAME}` to match the binary
# name it loads. Keep it stable; Dart's load_library.dart depends on it.
set(PLUGIN_NAME "photo_native_plugin")

set(NATIVE_CORE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../native/core")

list(APPEND PLUGIN_SOURCES
  "photo_native_plugin.cpp"
  "photo_native_texture.cpp"
  # photo_core sources compiled into the plugin DLL.
  "${NATIVE_CORE_DIR}/src/api/c_api.cpp"
  "${NATIVE_CORE_DIR}/src/runtime/engine.cpp"
  "${NATIVE_CORE_DIR}/src/runtime/slot_store.cpp"
  "${NATIVE_CORE_DIR}/src/runtime/event_ring.cpp"
  "${NATIVE_CORE_DIR}/src/thumb/slot.cpp"
  "${NATIVE_CORE_DIR}/src/util/log.cpp"
)

add_library(${PLUGIN_NAME} SHARED ${PLUGIN_SOURCES})

# `apply_standard_settings` is provided by the Flutter Windows runner CMake.
apply_standard_settings(${PLUGIN_NAME})

target_compile_features(${PLUGIN_NAME} PRIVATE cxx_std_20)
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_VISIBILITY_PRESET hidden
)

target_compile_definitions(${PLUGIN_NAME} PRIVATE
  FLUTTER_PLUGIN_IMPL
  PHOTO_BUILD_STATIC=1
  _CRT_SECURE_NO_WARNINGS
  NOMINMAX
)

target_include_directories(${PLUGIN_NAME} PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}"
  "${NATIVE_CORE_DIR}/include"
  "${NATIVE_CORE_DIR}/src"
)

target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)

# No additional bundled libraries in M1.
set(photo_native_bundled_libraries "" PARENT_SCOPE)

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

# Flutter symlinks this plugin into
# <app>\windows\flutter\ephemeral\.plugin_symlinks\photo_native\, so a naive
# relative path to the out-of-tree native/core resolves against the symlink
# location and breaks (notably in CI). Resolve symlinks first so the path is
# computed from the plugin's TRUE location in the repo.
get_filename_component(_pn_real "${CMAKE_CURRENT_LIST_DIR}" REALPATH)
# Walk upward from the (symlink-resolved) plugin dir to locate the repo's
# out-of-tree native/core. Robust whether Flutter stages the plugin as a
# symlink or a copy (Windows often copies), and to varying depth.
set(NATIVE_CORE_DIR "")
set(_pn_search "${_pn_real}")
foreach(_pn_i RANGE 8)
  if(EXISTS "${_pn_search}/native/core/include/photo_core.h")
    set(NATIVE_CORE_DIR "${_pn_search}/native/core")
    break()
  endif()
  get_filename_component(_pn_search "${_pn_search}" DIRECTORY)
endforeach()
if(NOT NATIVE_CORE_DIR)
  message(FATAL_ERROR "photo_native: could not locate native/core from ${_pn_real}")
endif()

list(APPEND PLUGIN_SOURCES
  "photo_native_plugin.cpp"
  "photo_native_texture.cpp"
  # photo_core sources compiled into the plugin DLL.
  "${NATIVE_CORE_DIR}/src/api/c_api.cpp"
  "${NATIVE_CORE_DIR}/src/runtime/engine.cpp"
  "${NATIVE_CORE_DIR}/src/runtime/slot_store.cpp"
  "${NATIVE_CORE_DIR}/src/runtime/event_ring.cpp"
  "${NATIVE_CORE_DIR}/src/runtime/job_system.cpp"
  "${NATIVE_CORE_DIR}/src/thumb/slot.cpp"
  "${NATIVE_CORE_DIR}/src/thumb/thumb_service.cpp"
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

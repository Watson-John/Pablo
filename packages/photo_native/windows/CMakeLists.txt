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

# Optional libvips (vcpkg) — enables the M3 real-decode path on Windows when
# pkg-config + vips are discoverable (see CI's vcpkg setup). Absent -> the
# engine falls back to the synthetic publish, so the plugin still builds.
# libvips on Windows: the prebuilt mxe bundle ships MSVC import libs but its
# .pc files hardcode non-relocatable build-machine paths, so we bypass
# pkg-config and consume the extracted bundle directly via PHOTO_VIPS_ROOT
# (set by CI / a developer). Absent -> synthetic fallback.
set(VIPS_FOUND FALSE)
if(DEFINED ENV{PHOTO_VIPS_ROOT} AND EXISTS "$ENV{PHOTO_VIPS_ROOT}/include/vips/vips.h")
  set(VIPS_ROOT "$ENV{PHOTO_VIPS_ROOT}")
  set(VIPS_FOUND TRUE)
endif()
# CI sets PHOTO_REQUIRE_VIPS=1 to assert real decode is wired — a green build
# then proves vips linked (MSVC/Flutter hide the #pragma-message marker).
if(NOT VIPS_FOUND AND DEFINED ENV{PHOTO_REQUIRE_VIPS})
  message(FATAL_ERROR "photo_native(windows): PHOTO_REQUIRE_VIPS set but PHOTO_VIPS_ROOT/include/vips/vips.h not found")
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
  "${NATIVE_CORE_DIR}/src/thumb/thumb_cache.cpp"
  "${NATIVE_CORE_DIR}/src/util/log.cpp"
  # M5 asset catalog (SQLite) + EXIF — unify the durable catalog across every
  # desktop target. The SQLite probe below defines PHOTO_HAVE_SQLITE, lighting
  # up engine.cpp's catalog member and the catalog/album/organize C-ABI in
  # c_api.cpp. exif.cpp self-stubs when libexif is absent (Windows has none
  # wired yet), so it is always safe to compile.
  "${NATIVE_CORE_DIR}/src/catalog/catalog.cpp"
  "${NATIVE_CORE_DIR}/src/exif/exif.cpp"
  # Stage 9 — semantic search (dependency-free; ONNX backend self-stubs).
  "${NATIVE_CORE_DIR}/src/semantic/embedder.cpp"
  "${NATIVE_CORE_DIR}/src/semantic/onnx_embedder.cpp"
  "${NATIVE_CORE_DIR}/src/semantic/semantic_search.cpp"
  "${NATIVE_CORE_DIR}/src/semantic/semantic_service.cpp"
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

# Expose the plugin's public header dir to dependents — the app's generated
# generated_plugin_registrant.cc does #include <photo_native/photo_native_plugin.h>.
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)

target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)

if(VIPS_FOUND)
  target_compile_definitions(${PLUGIN_NAME} PRIVATE PHOTO_HAVE_VIPS=1)
  target_include_directories(${PLUGIN_NAME} PRIVATE
    "${VIPS_ROOT}/include"
    "${VIPS_ROOT}/include/glib-2.0"
    "${VIPS_ROOT}/lib/glib-2.0/include")
  # mxe import libs carry a 'lib' prefix; link the C libs we reference directly
  # (vips_* + g_free/g_object_unref). The libvips DLL resolves its own deps.
  target_link_libraries(${PLUGIN_NAME} PRIVATE
    "${VIPS_ROOT}/lib/libvips.lib"
    "${VIPS_ROOT}/lib/libgobject-2.0.lib"
    "${VIPS_ROOT}/lib/libglib-2.0.lib")
  message(STATUS "photo_native(windows): libvips at ${VIPS_ROOT} -> real decode")
else()
  message(STATUS "photo_native(windows): libvips not found -> synthetic decode")
endif()

# ---- Asset catalog (SQLite via vcpkg, REQUIRED) ----
# `sqlite3` is declared in the repo's vcpkg.json. The Flutter Windows build does
# not pass a CMake toolchain file, so we self-configure from VCPKG_ROOT (CI runs
# `vcpkg install sqlite3:x64-windows`) by appending the installed prefix to
# CMAKE_PREFIX_PATH — mirroring how the libvips block consumes a bundle by path.
# unofficial-sqlite3's CMake config is relocatable. exif.cpp self-stubs (no
# libexif on Windows yet -> PHOTO_HAVE_EXIF stays undefined).
if(DEFINED ENV{VCPKG_ROOT})
  list(APPEND CMAKE_PREFIX_PATH "$ENV{VCPKG_ROOT}/installed/x64-windows")
endif()
find_package(unofficial-sqlite3 CONFIG REQUIRED)
target_compile_definitions(${PLUGIN_NAME} PRIVATE PHOTO_HAVE_SQLITE=1)
target_link_libraries(${PLUGIN_NAME} PRIVATE unofficial::sqlite3::sqlite3)
message(STATUS "photo_native(windows): asset catalog ENABLED (vcpkg sqlite3)")

# Bundle the vcpkg sqlite3 DLL next to the app so the plugin resolves it at
# runtime (x64-windows is a dynamic triplet; CRT-compatible with Flutter's /MD).
set(_pn_bundled_libraries "")
if(DEFINED ENV{VCPKG_ROOT} AND EXISTS "$ENV{VCPKG_ROOT}/installed/x64-windows/bin/sqlite3.dll")
  list(APPEND _pn_bundled_libraries "$ENV{VCPKG_ROOT}/installed/x64-windows/bin/sqlite3.dll")
endif()
set(photo_native_bundled_libraries "${_pn_bundled_libraries}" PARENT_SCOPE)

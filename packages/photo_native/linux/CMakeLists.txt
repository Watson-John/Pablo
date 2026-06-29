# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Pablo contributors.
#
# Flutter Linux plugin CMake.

cmake_minimum_required(VERSION 3.14)
set(PROJECT_NAME "photo_native")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "photo_native_plugin")

# Flutter symlinks this plugin into
# <app>/linux/flutter/ephemeral/.plugin_symlinks/photo_native/, so a naive
# relative path to the out-of-tree native/core resolves against the symlink
# location and breaks (notably in CI). Resolve symlinks first so the path is
# computed from the plugin's TRUE location in the repo.
get_filename_component(_pn_real "${CMAKE_CURRENT_LIST_DIR}" REALPATH)
# Walk upward from the (symlink-resolved) plugin dir to locate the repo's
# out-of-tree native/core. Robust whether Flutter stages the plugin as a
# symlink or a copy, and to varying depth under the app tree.
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

find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK REQUIRED IMPORTED_TARGET gtk+-3.0)

# Optional libvips (apt: libvips-dev) — enables the M3 real-decode path.
# When absent, thumb_service falls back to the synthetic publish.
pkg_check_modules(VIPS IMPORTED_TARGET vips)
# CI sets PHOTO_REQUIRE_VIPS=1 to assert real decode is wired — a green build
# then proves vips linked (MSVC/Flutter hide the #pragma-message marker).
if(NOT VIPS_FOUND AND DEFINED ENV{PHOTO_REQUIRE_VIPS})
  message(FATAL_ERROR "photo_native: PHOTO_REQUIRE_VIPS set but libvips not found via pkg-config")
endif()

list(APPEND PLUGIN_SOURCES
  "photo_native_plugin.cc"
  "photo_native_texture.cc"
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
  # desktop target (the macOS podspec already compiles these). The SQLite probe
  # below defines PHOTO_HAVE_SQLITE, which lights up engine.cpp's catalog member
  # and the catalog/album/organize C-ABI in c_api.cpp. exif.cpp self-stubs when
  # libexif is absent, so it is always safe to compile.
  "${NATIVE_CORE_DIR}/src/catalog/catalog.cpp"
  "${NATIVE_CORE_DIR}/src/exif/exif.cpp"
)

add_library(${PLUGIN_NAME} SHARED ${PLUGIN_SOURCES})

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
)

target_include_directories(${PLUGIN_NAME} PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}"
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
  "${NATIVE_CORE_DIR}/include"
  "${NATIVE_CORE_DIR}/src"
)

# Expose the plugin's public header dir to dependents — the app's generated
# generated_plugin_registrant.cc does #include <photo_native/photo_native_plugin.h>.
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)

target_link_libraries(${PLUGIN_NAME} PRIVATE
  flutter
  PkgConfig::GTK
)

if(VIPS_FOUND)
  target_compile_definitions(${PLUGIN_NAME} PRIVATE PHOTO_HAVE_VIPS=1)
  target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::VIPS)
  message(STATUS "photo_native(linux): libvips ${VIPS_VERSION} -> real decode")
else()
  message(STATUS "photo_native(linux): libvips not found -> synthetic decode")
endif()

# ---- Asset catalog (SQLite, REQUIRED) + EXIF (libexif, optional) ----
# The durable catalog is a first-class cross-platform feature, so SQLite is
# REQUIRED here (apt: libsqlite3-dev) — a missing dep fails the build loudly
# rather than silently shipping a catalog-less app. exif.cpp self-stubs without
# libexif, so PHOTO_HAVE_EXIF is best-effort.
find_package(SQLite3 REQUIRED)
target_compile_definitions(${PLUGIN_NAME} PRIVATE PHOTO_HAVE_SQLITE=1)
target_link_libraries(${PLUGIN_NAME} PRIVATE SQLite::SQLite3)
message(STATUS "photo_native(linux): asset catalog ENABLED (SQLite ${SQLite3_VERSION})")

pkg_check_modules(LIBEXIF IMPORTED_TARGET libexif)
if(LIBEXIF_FOUND)
  target_compile_definitions(${PLUGIN_NAME} PRIVATE PHOTO_HAVE_EXIF=1)
  target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::LIBEXIF)
  message(STATUS "photo_native(linux): EXIF metadata ENABLED (libexif ${LIBEXIF_VERSION})")
else()
  message(STATUS "photo_native(linux): libexif absent -> EXIF metadata disabled")
endif()

set(photo_native_bundled_libraries "" PARENT_SCOPE)

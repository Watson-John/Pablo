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

list(APPEND PLUGIN_SOURCES
  "photo_native_plugin.cc"
  "photo_native_texture.cc"
  "${NATIVE_CORE_DIR}/src/api/c_api.cpp"
  "${NATIVE_CORE_DIR}/src/runtime/engine.cpp"
  "${NATIVE_CORE_DIR}/src/runtime/slot_store.cpp"
  "${NATIVE_CORE_DIR}/src/runtime/event_ring.cpp"
  "${NATIVE_CORE_DIR}/src/thumb/slot.cpp"
  "${NATIVE_CORE_DIR}/src/util/log.cpp"
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

target_link_libraries(${PLUGIN_NAME} PRIVATE
  flutter
  PkgConfig::GTK
)

set(photo_native_bundled_libraries "" PARENT_SCOPE)

# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Pablo contributors.
#
# Flutter Linux plugin CMake.

cmake_minimum_required(VERSION 3.14)
set(PROJECT_NAME "photo_native")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "photo_native_plugin")
set(NATIVE_CORE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../native/core")

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

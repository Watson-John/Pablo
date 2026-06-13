# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Pablo contributors.
#
# Pablo dedup — local near-duplicate photo detection.
#
# Standalone CMake project (NOT pulled into the Flutter app build). Heavy,
# desktop-only deps (OpenCV, FAISS, ONNX Runtime, LibRaw) live here so they
# never touch the photo_core plugin build.
#
#   cmake --preset linux-release   (or windows-release)   from this directory
#   cmake --build --preset linux-release
#
# See README.md for the model-export and run instructions.

cmake_minimum_required(VERSION 3.27)

project(pablo_dedup
    VERSION 0.1.0
    DESCRIPTION "Local near-duplicate photo detection"
    LANGUAGES CXX C
)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE RelWithDebInfo CACHE STRING "" FORCE)
endif()

# ------------------------------------------------------------------
# Dependencies
# ------------------------------------------------------------------
# Required (always present via vcpkg manifest):
find_package(OpenCV CONFIG REQUIRED COMPONENTS core imgproc imgcodecs img_hash)
find_package(xxHash CONFIG REQUIRED)
find_package(unofficial-sqlite3 CONFIG REQUIRED)
find_package(yaml-cpp CONFIG REQUIRED)
find_package(nlohmann_json CONFIG REQUIRED)
find_package(httplib CONFIG REQUIRED)
find_package(Threads REQUIRED)

# Optional acceleration / format coverage. Each is gated by a compile define so
# the binary builds and runs (with a clear runtime message) when absent — the
# same optional-dependency discipline as photo_core's PHOTO_HAVE_VIPS.
find_package(faiss CONFIG QUIET)            # vcpkg feature: faiss
find_package(OnnxRuntime QUIET)             # prebuilt; see cmake/FindOnnxRuntime.cmake
find_package(libraw CONFIG QUIET)           # vcpkg feature: raw  (LGPL — dynamic link)

# ------------------------------------------------------------------
# Library target (pipeline stages) + thin CLI / server front-ends
# ------------------------------------------------------------------
add_library(dedup_core STATIC
  src/config.cpp
  src/log.cpp
  src/ingest.cpp
  src/decode.cpp
  src/embed.cpp
  src/index.cpp
  src/cluster.cpp
  src/store.cpp
  src/pipeline.cpp
  src/server.cpp
)

target_include_directories(dedup_core PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)

target_link_libraries(dedup_core PUBLIC
  opencv_core opencv_imgproc opencv_imgcodecs opencv_img_hash
  xxHash::xxhash
  unofficial::sqlite3::sqlite3
  yaml-cpp::yaml-cpp
  nlohmann_json::nlohmann_json
  httplib::httplib
  Threads::Threads
)

# --- FAISS (exact IndexFlatIP). Fallback: blocked brute force in index.cpp ---
if(faiss_FOUND)
  target_compile_definitions(dedup_core PUBLIC DEDUP_HAVE_FAISS=1)
  target_link_libraries(dedup_core PUBLIC faiss)
  message(STATUS "pablo_dedup: FAISS found -> hardware-accelerated k-NN")
else()
  message(STATUS "pablo_dedup: FAISS absent -> blocked brute-force k-NN fallback "
                 "(enable with vcpkg feature 'faiss')")
endif()

# --- ONNX Runtime (SSCD inference). No meaningful fallback for embeddings ---
if(OnnxRuntime_FOUND)
  target_compile_definitions(dedup_core PUBLIC DEDUP_HAVE_ORT=1)
  target_link_libraries(dedup_core PUBLIC OnnxRuntime::OnnxRuntime)
  message(STATUS "pablo_dedup: ONNX Runtime ${OnnxRuntime_VERSION} -> SSCD embedding enabled")
else()
  message(WARNING "pablo_dedup: ONNX Runtime NOT found -> the 'embed' stage will "
                  "error at runtime. Set -DONNXRUNTIME_ROOT=<dist> to enable it.")
endif()

# --- LibRaw (RAW embedded thumbnails). Fallback: OpenCV-only, RAW skipped ----
if(libraw_FOUND)
  target_compile_definitions(dedup_core PUBLIC DEDUP_HAVE_LIBRAW=1)
  target_link_libraries(dedup_core PUBLIC libraw::raw)
  message(STATUS "pablo_dedup: LibRaw found -> RAW thumbnail decode enabled")
else()
  message(STATUS "pablo_dedup: LibRaw absent -> RAW files decoded via OpenCV only "
                 "(enable with vcpkg feature 'raw')")
endif()

target_compile_features(dedup_core PUBLIC cxx_std_20)

# Single CLI entry point: `dedup scan|serve|calibrate`.
add_executable(dedup src/main.cpp)
target_link_libraries(dedup PRIVATE dedup_core)

install(TARGETS dedup RUNTIME DESTINATION bin)
install(DIRECTORY web/ DESTINATION share/pablo-dedup/web)

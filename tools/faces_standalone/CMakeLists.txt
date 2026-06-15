# faces_standalone — an isolated smoke-test harness for the C++ face pipeline.
#
# Compiles the 7 face TUs + the 3 zero-dependency runtime TUs FaceService needs
# + a probe main, linking only OpenCV + ONNX Runtime + SQLite3 (Homebrew). It
# deliberately bypasses the full photo_core library (which needs libvips and the
# rest of the M1-M3 chain that isn't built yet), so the face stack can be
# compiled and RUN end-to-end on real models + images.
#
# Configure:
#   cmake -S tools/faces_standalone -B build/faces -DCMAKE_BUILD_TYPE=Release
# Build:
#   cmake --build build/faces -j
# Run (reproducible from the repo: vendored LFS models + the gitignored
# .testdata snapshot — no external drive needed):
#   ./build/faces/faces_probe native/models .testdata/full_db 15 8
#   ./build/faces/faces_probe fullres native/models .testdata/full_db/faces_fullres_local.tsv 120
#
# Regenerate the full-res local snapshot (one-time, needs the X9 Pro drive
# mounted; transcodes originals -> full-res JPEG into the gitignored .testdata):
#   ./build/faces/faces_probe snapshot .testdata/full_db/faces.tsv \
#       .testdata/full_res .testdata/full_db/faces_fullres_local.tsv 120

cmake_minimum_required(VERSION 3.27)
project(faces_standalone CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

set(CORE ${CMAKE_CURRENT_SOURCE_DIR}/../../native/core)

# --- OpenCV (Homebrew keg ships OpenCVConfig.cmake; calib3d for the warp) ---
if(APPLE AND NOT DEFINED OpenCV_DIR)
    execute_process(COMMAND brew --prefix opencv
                    OUTPUT_VARIABLE BREW_OPENCV OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
    if(EXISTS "${BREW_OPENCV}/lib/cmake/opencv4")
        list(APPEND CMAKE_PREFIX_PATH "${BREW_OPENCV}")
    endif()
endif()
find_package(OpenCV REQUIRED COMPONENTS core imgproc imgcodecs dnn calib3d)
find_package(SQLite3 REQUIRED)

# --- ONNX Runtime (Homebrew ships include+lib only, no CMake config) ---
execute_process(COMMAND brew --prefix onnxruntime
                OUTPUT_VARIABLE BREW_ORT OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
find_path(ORT_INCLUDE_DIR onnxruntime_cxx_api.h
          HINTS ${BREW_ORT}/include ${BREW_ORT}/include/onnxruntime)
find_library(ORT_LIBRARY onnxruntime HINTS ${BREW_ORT}/lib)
if(NOT ORT_INCLUDE_DIR OR NOT ORT_LIBRARY)
    message(FATAL_ERROR "ONNX Runtime not found (brew --prefix onnxruntime = ${BREW_ORT}). "
                        "Run: brew install onnxruntime")
endif()
message(STATUS "ONNX Runtime: ${ORT_LIBRARY} (include ${ORT_INCLUDE_DIR})")

add_executable(faces_probe
    main.cpp
    ${CORE}/src/faces/detector.cpp
    ${CORE}/src/faces/align.cpp
    ${CORE}/src/faces/embed.cpp
    ${CORE}/src/faces/cluster.cpp
    ${CORE}/src/faces/prototype.cpp
    ${CORE}/src/faces/store.cpp
    ${CORE}/src/faces/face_service.cpp
    ${CORE}/src/runtime/event_ring.cpp
    ${CORE}/src/runtime/job_system.cpp
    ${CORE}/src/util/log.cpp
)
target_include_directories(faces_probe PRIVATE
    ${CORE}/src ${CORE}/include ${ORT_INCLUDE_DIR} ${OpenCV_INCLUDE_DIRS})
target_compile_definitions(faces_probe PRIVATE
    PHOTO_HAVE_FACES=1 FACES_HAVE_ORT=1 FACES_HAVE_SQLITE=1)
target_link_libraries(faces_probe PRIVATE ${OpenCV_LIBS} SQLite::SQLite3 ${ORT_LIBRARY})

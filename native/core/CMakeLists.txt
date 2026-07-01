# native/core/CMakeLists.txt — the photo_core shared library.
#
# This is included by both the top-level CMakeLists.txt (for standalone dev)
# and by each platform's plugin CMake (windows/, linux/, macos/ inside
# packages/photo_native/). Keep it self-contained.

cmake_minimum_required(VERSION 3.27)

# ------------------------------------------------------------------
# Source layout
# ------------------------------------------------------------------

set(PHOTO_CORE_PUBLIC_HEADERS
    include/photo_core.h
    include/photo_core_version.h
)

set(PHOTO_CORE_SOURCES
    # M1 — minimal subset
    src/api/c_api.cpp
    src/runtime/engine.cpp
    src/runtime/slot_store.cpp
    src/runtime/event_ring.cpp
    src/thumb/slot.cpp
    src/util/log.cpp

    # M2 — request pipeline
    src/runtime/job_system.cpp
    src/thumb/thumb_service.cpp

    # M3 — on-disk thumbnail cache
    src/thumb/thumb_cache.cpp

    # Stage 7 — non-destructive edit stack (libvips/plain-C++ only; no OpenCV)
    src/edit/edit_spec.cpp
    src/edit/render.cpp
)

# Later milestones append to PHOTO_CORE_SOURCES via target_sources() calls
# wrapped in option() guards. Keeping M1's source list tight makes it easy
# to bring up the shared library before the dependency chain widens.

# ------------------------------------------------------------------
# Targets
# ------------------------------------------------------------------
#
# photo_core_objects — an internal OBJECT library holding every source,
# compiled once. The SHARED library (for distribution / the Flutter plugin)
# and the test + benchmark executables all consume it. Tests link it
# statically, which resolves the engine's internal (visibility-hidden)
# symbols that the SHARED dylib intentionally does not export — without this
# split, any test touching a non-PHOTO_API class fails to link.
#
# All dependency wiring (OpenCV, ONNX Runtime, SQLite, libvips, …) attaches to
# photo_core_objects with PUBLIC link libraries so both the dylib and the test
# exes inherit the same link closure.

add_library(photo_core_objects OBJECT
    ${PHOTO_CORE_SOURCES}
    ${PHOTO_CORE_PUBLIC_HEADERS}
)

target_include_directories(photo_core_objects
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
        $<INSTALL_INTERFACE:include>
        # src is PUBLIC so test/bench targets can include internal headers
        # (thumb/thumb_cache.h, catalog/catalog.h, …) for white-box testing.
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/src>
)

set_target_properties(photo_core_objects PROPERTIES
    POSITION_INDEPENDENT_CODE ON
    C_VISIBILITY_PRESET   hidden
    CXX_VISIBILITY_PRESET hidden
    VISIBILITY_INLINES_HIDDEN ON
)

target_compile_features(photo_core_objects PUBLIC cxx_std_20)

if(MSVC)
    target_compile_options(photo_core_objects PRIVATE
        /W4 /permissive- /Zc:__cplusplus /utf-8
    )
else()
    target_compile_options(photo_core_objects PRIVATE
        -Wall -Wextra -Wpedantic -Wno-unused-parameter
    )
endif()

# The distributable shared library is just the objects + their usage
# requirements. Linking the object library (rather than re-listing
# $<TARGET_OBJECTS>) also propagates its PUBLIC link closure to the dylib.
add_library(photo_core SHARED)
target_link_libraries(photo_core PUBLIC photo_core_objects)

set_target_properties(photo_core PROPERTIES
    OUTPUT_NAME           photo_core
    VERSION               ${PROJECT_VERSION}
    SOVERSION             1                # bumped only on PHOTO_ABI_VERSION change
)

# ------------------------------------------------------------------
# Sanitizers (attached to the objects; PUBLIC so consumers link the runtime)
# ------------------------------------------------------------------

if(PHOTO_ENABLE_ASAN OR PHOTO_ENABLE_UBSAN OR PHOTO_ENABLE_TSAN)
    set(_san_flags "")
    if(PHOTO_ENABLE_ASAN)
        list(APPEND _san_flags -fsanitize=address)
    endif()
    if(PHOTO_ENABLE_UBSAN)
        list(APPEND _san_flags -fsanitize=undefined)
    endif()
    if(PHOTO_ENABLE_TSAN)
        list(APPEND _san_flags -fsanitize=thread)
    endif()
    target_compile_options(photo_core_objects PUBLIC ${_san_flags} -fno-omit-frame-pointer)
    target_link_options   (photo_core_objects PUBLIC ${_san_flags})
endif()

# ------------------------------------------------------------------
# Dependency wiring (added per milestone, guarded by options)
# ------------------------------------------------------------------

# M3: libvips, libjpeg-turbo, LMDB, SQLite3, BLAKE3 -- added when those source
# files land. Each will use find_package + a LGPL link-mode assertion:
#
#   find_package(PkgConfig REQUIRED)
#   pkg_check_modules(VIPS REQUIRED vips)
#   target_link_libraries(photo_core PRIVATE PkgConfig::VIPS)
#   _assert_dynamic_link(VIPS)  # macro defined in cmake/lgpl_guard.cmake

# ------------------------------------------------------------------
# M6/M7: face subsystem (detect -> align -> embed -> cluster)
#
# Desktop-only. OpenCV is required for the pipeline (image ops, warp, NMS);
# ONNX Runtime is optional — without it the face sources compile but submit()s
# report unavailable (FACES_HAVE_ORT gates the real model paths, mirroring how
# thumb_service.cpp gates on PHOTO_HAVE_VIPS). Models chosen by the eval
# bake-off (scrfd_10g + auraface + agglomerative); see native/models/MANIFEST.md.
# ------------------------------------------------------------------

option(PHOTO_BUILD_FACES "Build the M6/M7 face subsystem (needs OpenCV)" ON)

if(PHOTO_BUILD_FACES)
    if(NOT "${CMAKE_CURRENT_SOURCE_DIR}/cmake" IN_LIST CMAKE_MODULE_PATH)
        list(APPEND CMAKE_MODULE_PATH ${CMAKE_CURRENT_SOURCE_DIR}/cmake)
    endif()
    # Homebrew ships OpenCVConfig.cmake but only on the keg prefix; seed it so
    # the find works out of the box on macOS without -DCMAKE_PREFIX_PATH.
    if(APPLE AND NOT DEFINED OpenCV_DIR)
        execute_process(COMMAND brew --prefix opencv
                        OUTPUT_VARIABLE _brew_opencv OUTPUT_STRIP_TRAILING_WHITESPACE
                        ERROR_QUIET RESULT_VARIABLE _brew_rc)
        if(_brew_rc EQUAL 0 AND EXISTS "${_brew_opencv}/lib/cmake/opencv4")
            list(APPEND CMAKE_PREFIX_PATH "${_brew_opencv}")
        endif()
    endif()
    # calib3d provides cv::estimateAffinePartial2D (align.cpp's 5-pt warp).
    find_package(OpenCV CONFIG QUIET COMPONENTS core imgproc imgcodecs dnn calib3d)
    if(OpenCV_FOUND)
        target_sources(photo_core_objects PRIVATE
            src/codec/codec.cpp        # full-res decode for the face pipeline (needs OpenCV)
            src/faces/detector.cpp
            src/faces/align.cpp
            src/faces/embed.cpp
            src/faces/cluster.cpp
            src/faces/prototype.cpp
            src/faces/store.cpp
            src/faces/face_service.cpp
        )
        target_compile_definitions(photo_core_objects PUBLIC PHOTO_HAVE_FACES=1)
        target_link_libraries(photo_core_objects PUBLIC ${OpenCV_LIBS})
        target_include_directories(photo_core_objects PUBLIC ${OpenCV_INCLUDE_DIRS})

        find_package(OnnxRuntime QUIET)  # cmake/FindOnnxRuntime.cmake
        if(OnnxRuntime_FOUND)
            target_compile_definitions(photo_core_objects PUBLIC FACES_HAVE_ORT=1)
            target_link_libraries(photo_core_objects PUBLIC OnnxRuntime::OnnxRuntime)
            message(STATUS "photo_core: faces ENABLED with ONNX Runtime "
                           "${OnnxRuntime_VERSION} (scrfd_10g + auraface)")
        else()
            message(STATUS "photo_core: faces compiled but ONNX Runtime absent "
                           "-> face scan reports unavailable")
        endif()

        # SQLite backs face/person persistence AND the asset catalog (M5+).
        # Prefer CMake's built-in FindSQLite3 (Homebrew/system: SQLite::SQLite3);
        # fall back to vcpkg's unofficial-sqlite3 port target.
        find_package(SQLite3 QUIET)
        if(SQLite3_FOUND)
            target_compile_definitions(photo_core_objects PUBLIC FACES_HAVE_SQLITE=1)
            target_link_libraries(photo_core_objects PUBLIC SQLite::SQLite3)
            message(STATUS "photo_core: faces persistence ENABLED (SQLite ${SQLite3_VERSION})")
        else()
            find_package(unofficial-sqlite3 CONFIG QUIET)
            if(unofficial-sqlite3_FOUND)
                target_compile_definitions(photo_core_objects PUBLIC FACES_HAVE_SQLITE=1)
                target_link_libraries(photo_core_objects PUBLIC unofficial::sqlite3::sqlite3)
                message(STATUS "photo_core: faces persistence ENABLED (SQLite, vcpkg)")
            else()
                message(STATUS "photo_core: SQLite absent -> face persistence stubbed")
            endif()
        endif()
    else()
        message(STATUS "photo_core: OpenCV not found -> face subsystem skipped")
    endif()
endif()

# ------------------------------------------------------------------
# M5: asset catalog (SQLite).
#
# The durable catalog is the keystone the import / rescan / metadata stages
# build on, so it is wired independently of the face subsystem. PHOTO_HAVE_SQLITE
# (distinct from the faces-only FACES_HAVE_SQLITE) gates catalog.cpp + the
# Engine's catalog member, so the catalog compiles whenever SQLite is present,
# with or without OpenCV.
# ------------------------------------------------------------------

option(PHOTO_BUILD_CATALOG "Build the SQLite asset catalog" ON)

if(PHOTO_BUILD_CATALOG)
    find_package(SQLite3 QUIET)
    if(NOT SQLite3_FOUND)
        find_package(unofficial-sqlite3 CONFIG QUIET)
    endif()
    if(SQLite3_FOUND OR unofficial-sqlite3_FOUND)
        if(SQLite3_FOUND)
            set(_photo_sqlite_tgt SQLite::SQLite3)
        else()
            set(_photo_sqlite_tgt unofficial::sqlite3::sqlite3)
        endif()
        target_sources(photo_core_objects PRIVATE
            src/catalog/catalog.cpp
            src/exif/exif.cpp)
        target_compile_definitions(photo_core_objects PUBLIC PHOTO_HAVE_SQLITE=1)
        target_link_libraries(photo_core_objects PUBLIC ${_photo_sqlite_tgt})
        message(STATUS "photo_core: asset catalog ENABLED (SQLite)")

        # EXIF metadata — libexif (LGPL, dynamically linked per DECISIONS D5).
        # Built alongside the catalog; metadata.cpp self-stubs without it.
        find_package(PkgConfig QUIET)
        if(PkgConfig_FOUND)
            pkg_check_modules(LIBEXIF QUIET IMPORTED_TARGET libexif)
        endif()
        if(LIBEXIF_FOUND)
            target_compile_definitions(photo_core_objects PUBLIC PHOTO_HAVE_EXIF=1)
            target_link_libraries(photo_core_objects PUBLIC PkgConfig::LIBEXIF)
            message(STATUS "photo_core: EXIF metadata ENABLED (libexif ${LIBEXIF_VERSION})")
        else()
            message(STATUS "photo_core: libexif absent -> EXIF metadata disabled")
        endif()
    else()
        message(STATUS "photo_core: SQLite absent -> asset catalog disabled")
    endif()
endif()

# ------------------------------------------------------------------
# libvips — real image decode + the non-destructive edit geometry render.
#
# Optional in the standalone/test build (the Flutter plugin builds wire libvips
# per-platform). When present it defines PHOTO_HAVE_VIPS, so thumb_service
# decodes for real and edit/render.cpp's apply_geometry compiles — which is what
# lets the edit integration tests exercise the actual geometry render. Absent, the
# core still builds (synthetic decode + geometry passthrough).
# ------------------------------------------------------------------

option(PHOTO_BUILD_VIPS "Link libvips for real decode + edit geometry render" ON)

if(PHOTO_BUILD_VIPS)
    find_package(PkgConfig QUIET)
    if(PkgConfig_FOUND)
        # Homebrew symlinks each keg's .pc into <prefix>/lib/pkgconfig.
        if(APPLE)
            execute_process(COMMAND brew --prefix
                            OUTPUT_VARIABLE _brew_prefix
                            OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
            if(_brew_prefix AND EXISTS "${_brew_prefix}/lib/pkgconfig")
                set(ENV{PKG_CONFIG_PATH}
                    "${_brew_prefix}/lib/pkgconfig:$ENV{PKG_CONFIG_PATH}")
            endif()
        endif()
        # Raw vars (not IMPORTED_TARGET): vips's .pc references a stale include
        # path that the imported target's existence-check rejects.
        pkg_check_modules(VIPS QUIET vips)
        if(VIPS_FOUND)
            target_compile_definitions(photo_core_objects PUBLIC PHOTO_HAVE_VIPS=1)
            target_include_directories(photo_core_objects PUBLIC ${VIPS_INCLUDE_DIRS})
            target_link_directories(photo_core_objects PUBLIC ${VIPS_LIBRARY_DIRS})
            target_link_libraries(photo_core_objects PUBLIC ${VIPS_LIBRARIES})
            target_compile_options(photo_core_objects PUBLIC ${VIPS_CFLAGS_OTHER})
            message(STATUS "photo_core: libvips ENABLED (${VIPS_VERSION}) "
                           "-> real decode + edit geometry render")
        else()
            message(STATUS "photo_core: libvips not found "
                           "-> synthetic decode + geometry passthrough")
        endif()
    endif()
endif()

# ------------------------------------------------------------------
# Tests + benchmarks
# ------------------------------------------------------------------

if(PHOTO_BUILD_TESTS)
    enable_testing()
    add_subdirectory(tests)
endif()

if(PHOTO_BUILD_BENCHMARKS)
    add_subdirectory(benchmarks)
endif()

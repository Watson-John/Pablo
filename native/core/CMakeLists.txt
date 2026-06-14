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
)

# Later milestones append to PHOTO_CORE_SOURCES via target_sources() calls
# wrapped in option() guards. Keeping M1's source list tight makes it easy
# to bring up the shared library before the dependency chain widens.

# ------------------------------------------------------------------
# Target
# ------------------------------------------------------------------

add_library(photo_core SHARED
    ${PHOTO_CORE_SOURCES}
    ${PHOTO_CORE_PUBLIC_HEADERS}
)

target_include_directories(photo_core
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
        $<INSTALL_INTERFACE:include>
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)

set_target_properties(photo_core PROPERTIES
    OUTPUT_NAME           photo_core
    VERSION               ${PROJECT_VERSION}
    SOVERSION             1                # bumped only on PHOTO_ABI_VERSION change
    POSITION_INDEPENDENT_CODE ON
    C_VISIBILITY_PRESET   hidden
    CXX_VISIBILITY_PRESET hidden
    VISIBILITY_INLINES_HIDDEN ON
)

target_compile_features(photo_core PUBLIC cxx_std_20)

if(MSVC)
    target_compile_options(photo_core PRIVATE
        /W4 /permissive- /Zc:__cplusplus /utf-8
    )
else()
    target_compile_options(photo_core PRIVATE
        -Wall -Wextra -Wpedantic -Wno-unused-parameter
    )
endif()

# ------------------------------------------------------------------
# Sanitizers
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
    target_compile_options(photo_core PRIVATE ${_san_flags} -fno-omit-frame-pointer)
    target_link_options   (photo_core PRIVATE ${_san_flags})
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
# Tests + benchmarks
# ------------------------------------------------------------------

if(PHOTO_BUILD_TESTS)
    enable_testing()
    add_subdirectory(tests)
endif()

if(PHOTO_BUILD_BENCHMARKS)
    add_subdirectory(benchmarks)
endif()

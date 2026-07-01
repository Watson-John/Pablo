# Unit tests for photo_core. GoogleTest, registered with CTest.
#
# Hermetic GoogleTest, built from a pinned source tag rather than
# find_package(): system GoogleTest is unreliable across dev machines
# (Homebrew's formula ships no dylibs; a stray Anaconda GTest hijacks the CMake
# search path and drags in an incompatible libpng that breaks OpenCV at load).
# A static, from-source build links straight into the test exe — no runtime
# dylib resolution — and is fully reproducible in CI.
include(FetchContent)
set(INSTALL_GTEST OFF CACHE BOOL "" FORCE)
set(BUILD_GMOCK   OFF CACHE BOOL "" FORCE)
set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)   # MSVC: match the CRT
FetchContent_Declare(
    googletest
    GIT_REPOSITORY https://github.com/google/googletest.git
    GIT_TAG        v1.15.2
    GIT_SHALLOW    TRUE
)
# Force a static GoogleTest regardless of the project's BUILD_SHARED_LIBS=ON.
set(_photo_prev_shared ${BUILD_SHARED_LIBS})
set(BUILD_SHARED_LIBS OFF)
FetchContent_MakeAvailable(googletest)
set(BUILD_SHARED_LIBS ${_photo_prev_shared})

set(PHOTO_CORE_TEST_SOURCES
    smoke_test.cpp
    thumb_cache_test.cpp
    catalog_test.cpp
    import_test.cpp
    metadata_test.cpp
    codec_test.cpp
    album_test.cpp
    organize_test.cpp
    hidden_test.cpp
    smart_test.cpp
    compact_test.cpp
    rebase_test.cpp
    # §5 Organize & metadata — full suite (see
    # docs/specs/05-organize-and-metadata-tests.md).
    organize_state_test.cpp     # star / rating / caption (catalog)
    tags_test.cpp               # keyword/tag edge cases (catalog)
    metadata_storage_test.cpp   # asset_metadata round-trip (catalog)
    exif_extract_test.cpp       # real libexif extraction vs exiftool fixture
    c_api_organize_test.cpp     # the organize/metadata C ABI surface
)

add_executable(photo_core_tests ${PHOTO_CORE_TEST_SOURCES})

# exif_extract_test loads a committed fixture baked by exiftool; hand it the
# absolute fixtures dir so the test is run-location independent.
target_compile_definitions(photo_core_tests PRIVATE
    PHOTO_TEST_FIXTURES_DIR="${CMAKE_CURRENT_SOURCE_DIR}/fixtures")

# Link the OBJECT library, not the SHARED dylib: tests do white-box checks on
# internal classes (ThumbCache, Catalog, …) whose symbols the dylib hides.
# photo_core_objects also carries the src/ include dir and dep closure (PUBLIC).
target_link_libraries(photo_core_tests
    PRIVATE
        photo_core_objects
        GTest::gtest_main
)

include(GoogleTest)
# POST_BUILD (default) bakes the test list at build time by running the exe once
# — reliable here since the test binary runs in the build tree. (PRE_TEST
# deferred discovery did not register tests with ctest in this layout.)
gtest_discover_tests(photo_core_tests)

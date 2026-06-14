# Unit tests for photo_core. GoogleTest, registered with CTest.

find_package(GTest CONFIG REQUIRED)

set(PHOTO_CORE_TEST_SOURCES
    smoke_test.cpp
    thumb_cache_test.cpp
)

add_executable(photo_core_tests ${PHOTO_CORE_TEST_SOURCES})

target_link_libraries(photo_core_tests
    PRIVATE
        photo_core
        GTest::gtest_main
)

target_include_directories(photo_core_tests
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/../src
)

include(GoogleTest)
gtest_discover_tests(photo_core_tests
    DISCOVERY_MODE PRE_TEST
)

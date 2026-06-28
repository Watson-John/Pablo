# Benchmark binaries for photo_core. Google Benchmark.
# Real benchmarks land in M2 (FFI overhead) and M3 (decode/cache latency).
# This CMakeLists exists so the directory is wired up from M1.

# Optional: the vcpkg manifest ships Google Benchmark, but a system/Homebrew
# build may lack its CMake config. Skip gracefully rather than failing the
# whole configure when PHOTO_BUILD_BENCHMARKS defaulted ON.
find_package(benchmark CONFIG QUIET)
if(NOT benchmark_FOUND)
    message(STATUS "photo_core: Google Benchmark not found -> benchmarks skipped")
    return()
endif()

# Placeholder benchmark target so the build system links Google Benchmark
# without erroring on an empty source list. Replaced in M2.
add_executable(photo_core_bench
    bench_placeholder.cpp
)

target_link_libraries(photo_core_bench
    PRIVATE
        photo_core_objects
        benchmark::benchmark
        benchmark::benchmark_main
)

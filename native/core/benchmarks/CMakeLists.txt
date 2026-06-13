# Benchmark binaries for photo_core. Google Benchmark.
# Real benchmarks land in M2 (FFI overhead) and M3 (decode/cache latency).
# This CMakeLists exists so the directory is wired up from M1.

find_package(benchmark CONFIG REQUIRED)

# Placeholder benchmark target so the build system links Google Benchmark
# without erroring on an empty source list. Replaced in M2.
add_executable(photo_core_bench
    bench_placeholder.cpp
)

target_link_libraries(photo_core_bench
    PRIVATE
        photo_core
        benchmark::benchmark
        benchmark::benchmark_main
)

target_include_directories(photo_core_bench
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/../src
)

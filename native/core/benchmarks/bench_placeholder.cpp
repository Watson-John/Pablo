// Placeholder benchmark so the directory builds cleanly from M1.
// Real benchmarks (FFI overhead, cache hit latency, decode latency) land
// in M2/M3.

#include <benchmark/benchmark.h>

#include "photo_core.h"

static void BM_AbiVersionCall(benchmark::State& state) {
    for (auto _ : state) {
        benchmark::DoNotOptimize(photo_abi_version());
    }
}
BENCHMARK(BM_AbiVersionCall);

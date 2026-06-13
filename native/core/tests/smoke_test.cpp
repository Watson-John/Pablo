// smoke_test.cpp — minimal sanity tests proving the engine builds, opens,
// and exposes the C ABI symbols correctly. Real M1 acceptance tests live in
// the scroll harness (tools/scroll_harness/); these are build-system smoke.

#include <gtest/gtest.h>

#include <filesystem>
#include <string>

#include "photo_core.h"

namespace fs = std::filesystem;

namespace {

fs::path make_tmp_dir(const char* tag) {
    auto root = fs::temp_directory_path() / ("photo_core_smoke_" + std::string(tag));
    fs::remove_all(root);
    fs::create_directories(root);
    return root;
}

}  // namespace

TEST(SmokeAbi, AbiVersionConstant) {
    EXPECT_EQ(photo_abi_version(), static_cast<uint32_t>(PHOTO_ABI_VERSION));
}

TEST(SmokeAbi, EngineVersionStringNonEmpty) {
    const char* v = photo_engine_version();
    ASSERT_NE(v, nullptr);
    EXPECT_GT(std::string(v).size(), 0u);
}

TEST(SmokeEngine, CreateDestroyDefaults) {
    auto cat = make_tmp_dir("catalog");
    auto cache = make_tmp_dir("cache");

    photo_config_t cfg{};
    auto cat_str = (cat / "pablo.db").string();
    cfg.catalog_path_utf8 = cat_str.c_str();
    cfg.cache_path_utf8 = cache.string().c_str();

    photo_engine_t* eng = photo_engine_create(&cfg);
    ASSERT_NE(eng, nullptr);
    photo_engine_destroy(eng);
}

TEST(SmokeEngine, SlotLifecycle) {
    auto cat = make_tmp_dir("slot_catalog");
    auto cache = make_tmp_dir("slot_cache");

    photo_config_t cfg{};
    auto cat_str = (cat / "pablo.db").string();
    cfg.catalog_path_utf8 = cat_str.c_str();
    cfg.cache_path_utf8 = cache.string().c_str();

    photo_engine_t* eng = photo_engine_create(&cfg);
    ASSERT_NE(eng, nullptr);

    uint64_t slot = photo_slot_create(eng, 256, 256);
    EXPECT_NE(slot, 0u);

    uint64_t prev_gen = photo_slot_bind_generation(eng, slot, 42);
    EXPECT_EQ(prev_gen, 0u);  // freshly created slot starts at gen 0

    prev_gen = photo_slot_bind_generation(eng, slot, 43);
    EXPECT_EQ(prev_gen, 42u);

    photo_slot_destroy(eng, slot);
    photo_engine_destroy(eng);
}

TEST(SmokeEvents, PollEmptyIsZero) {
    auto cat = make_tmp_dir("evt_catalog");
    auto cache = make_tmp_dir("evt_cache");

    photo_config_t cfg{};
    auto cat_str = (cat / "pablo.db").string();
    cfg.catalog_path_utf8 = cat_str.c_str();
    cfg.cache_path_utf8 = cache.string().c_str();

    photo_engine_t* eng = photo_engine_create(&cfg);
    ASSERT_NE(eng, nullptr);

    photo_event_t buf[8];
    size_t n = photo_poll_events(eng, buf, 8);
    EXPECT_EQ(n, 0u);

    photo_engine_destroy(eng);
}

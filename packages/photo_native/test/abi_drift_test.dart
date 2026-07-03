// abi_drift_test.dart — the FFI drift gate.
//
// core_api.dart hand-writes every binding (typed wrappers, struct mirrors,
// enum constants) against photo_core.h. Nothing at compile time ties those
// mirrors to the header, so a header change that isn't propagated corrupts
// memory or dispatches wrong values at runtime. This test closes the gap from
// three directions:
//
//   1. enum constants: hand-written classes vs the ffigen-generated ones
//      (bindings_generated.dart is regenerated from the header — see
//      ffigen.yaml — and committed as the reference artifact);
//   2. struct layouts: sizeOf() of every hand-mirrored Struct vs its
//      generated twin (ffigen computes layout from the real header);
//   3. the pinned ABI version vs the real dylib, when one is loadable
//      (PHOTO_CORE_LIB=<abs path>, same convention as pablo/test/ffi).
//
// The native twin of this file is the static_assert block at the bottom of
// c_api.cpp, which pins the same layouts on the C++ side.
//
// If this test fails: regenerate bindings (`dart run ffigen --config
// ffigen.yaml`), fix the hand mirrors in core_api.dart/event_pump.dart, and
// keep the c_api.cpp pins + PHOTO_ABI_VERSION in sync — all in one commit.

import 'dart:ffi';
import 'dart:io' show Platform;

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_native/src/ffi/bindings_generated.dart' as gen;
import 'package:photo_native/src/ffi/core_api.dart';
import 'package:photo_native/src/ffi/event_pump.dart';

/// The ABI generation both sides are pinned to (PHOTO_ABI_VERSION).
const int kPinnedAbiVersion = 1;

void main() {
  test('event kinds match the generated header constants', () {
    expect(PhotoEventKind.stageReady, gen.photo_event_kind_t.PHOTO_EVT_STAGE_READY);
    expect(PhotoEventKind.stageFailed, gen.photo_event_kind_t.PHOTO_EVT_STAGE_FAILED);
    expect(PhotoEventKind.importProgress,
        gen.photo_event_kind_t.PHOTO_EVT_IMPORT_PROGRESS);
    expect(PhotoEventKind.importComplete,
        gen.photo_event_kind_t.PHOTO_EVT_IMPORT_COMPLETE);
    expect(PhotoEventKind.scanProgress,
        gen.photo_event_kind_t.PHOTO_EVT_SCAN_PROGRESS);
    expect(PhotoEventKind.clusterUpdated,
        gen.photo_event_kind_t.PHOTO_EVT_CLUSTER_UPDATED);
    expect(PhotoEventKind.log, gen.photo_event_kind_t.PHOTO_EVT_LOG);
    expect(PhotoEventKind.maintenanceComplete,
        gen.photo_event_kind_t.PHOTO_EVT_MAINTENANCE_COMPLETE);
    expect(PhotoEventKind.embedProgress,
        gen.photo_event_kind_t.PHOTO_EVT_EMBED_PROGRESS);
    expect(PhotoEventKind.exportComplete,
        gen.photo_event_kind_t.PHOTO_EVT_EXPORT_COMPLETE);
  });

  test('log/stage/priority constants match the generated header constants', () {
    expect(LogLevel.trace, gen.photo_log_level_t.PHOTO_LOG_TRACE);
    expect(LogLevel.debug, gen.photo_log_level_t.PHOTO_LOG_DEBUG);
    expect(LogLevel.info, gen.photo_log_level_t.PHOTO_LOG_INFO);
    expect(LogLevel.warn, gen.photo_log_level_t.PHOTO_LOG_WARN);
    expect(LogLevel.error, gen.photo_log_level_t.PHOTO_LOG_ERROR);

    expect(Stage.placeholder32, gen.photo_stage_t.PHOTO_STAGE_PLACEHOLDER32);
    expect(Stage.thumb256, gen.photo_stage_t.PHOTO_STAGE_THUMB256);
    expect(Stage.full, gen.photo_stage_t.PHOTO_STAGE_FULL);
    expect(Stage.maskPlaceholder32, gen.PHOTO_STAGE_MASK_PLACEHOLDER32);
    expect(Stage.maskThumb256, gen.PHOTO_STAGE_MASK_THUMB256);
    expect(Stage.maskFull, gen.PHOTO_STAGE_MASK_FULL);
    expect(Stage.maskDefault, gen.PHOTO_STAGE_MASK_DEFAULT);

    expect(Priority.interactive, gen.photo_priority_t.PHOTO_PRIORITY_INTERACTIVE);
    expect(Priority.viewport, gen.photo_priority_t.PHOTO_PRIORITY_VIEWPORT);
    expect(Priority.idle, gen.photo_priority_t.PHOTO_PRIORITY_IDLE);

    expect(ExportAnchor.bottomRight, gen.PHOTO_EXPORT_ANCHOR_BR);
    expect(ExportAnchor.bottomLeft, gen.PHOTO_EXPORT_ANCHOR_BL);
    expect(ExportAnchor.topRight, gen.PHOTO_EXPORT_ANCHOR_TR);
    expect(ExportAnchor.topLeft, gen.PHOTO_EXPORT_ANCHOR_TL);
    expect(ExportAnchor.center, gen.PHOTO_EXPORT_ANCHOR_CENTER);
  });

  test('hand-mirrored struct layouts match the generated layouts', () {
    final generated = <String, int>{
      'photo_config_t': sizeOf<gen.photo_config_t>(),
      'photo_frame_view_t': sizeOf<gen.photo_frame_view_t>(),
      'photo_event_t': sizeOf<gen.photo_event_t>(),
      'photo_catalog_stats_t': sizeOf<gen.photo_catalog_stats_t>(),
      'photo_person_t': sizeOf<gen.photo_person_t>(),
      'photo_face_t': sizeOf<gen.photo_face_t>(),
      'photo_asset_t': sizeOf<gen.photo_asset_t>(),
      'photo_geopoint_t': sizeOf<gen.photo_geopoint_t>(),
      'photo_organize_t': sizeOf<gen.photo_organize_t>(),
      'photo_album_t': sizeOf<gen.photo_album_t>(),
      'photo_embed_counts_t': sizeOf<gen.photo_embed_counts_t>(),
      'photo_metadata_t': sizeOf<gen.photo_metadata_t>(),
      'photo_similar_pair_t': sizeOf<gen.photo_similar_pair_t>(),
      'photo_search_hit_t': sizeOf<gen.photo_search_hit_t>(),
      'photo_asset_color_t': sizeOf<gen.photo_asset_color_t>(),
      'photo_saved_search_t': sizeOf<gen.photo_saved_search_t>(),
      'photo_export_options_t': sizeOf<gen.photo_export_options_t>(),
      'photo_collage_cell_t': sizeOf<gen.photo_collage_cell_t>(),
    };
    final mirrored = debugNativeStructSizes();
    expect(mirrored.keys.toSet(), generated.keys.toSet(),
        reason: 'a struct mirror was added/removed on one side only');
    for (final name in generated.keys) {
      expect(mirrored[name], generated[name],
          reason: '$name: hand mirror in core_api.dart no longer matches the '
              'header layout — fields drifted');
    }
  });

  test('real dylib reports the pinned ABI version', () {
    // Same gating convention as pablo/test/ffi: point PHOTO_CORE_LIB at the
    // standalone-build dylib; skip (never fail) when it is not loadable.
    if (Platform.environment['PHOTO_CORE_LIB'] == null) {
      markTestSkipped('PHOTO_CORE_LIB not set');
      return;
    }
    final int v;
    try {
      v = Engine.abiVersion;
    } catch (e) {
      markTestSkipped('libphoto_core not loadable ($e)');
      return;
    }
    expect(v, kPinnedAbiVersion,
        reason: 'native PHOTO_ABI_VERSION moved — update kPinnedAbiVersion '
            'and both binding layers together');
  });
}

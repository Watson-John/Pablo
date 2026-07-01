// search_controller.dart — builds the app's real search runner (Stage 9).
//
// Bridges the pure [SearchService] to live app data: it projects the
// catalog-hydrated [Library] + the native embedding index into [SearchDoc]s and
// wires a semantic [TextRanker] over the native embedder. Installed into
// [PabloAppState.searchRunner] once the backend is up.
//
// Fields sourced without any per-photo FFI (cheap, bulk): star, date (from the
// scan's file mtime), dominant colour + geotag + album membership (a few bulk
// calls). Camera/EXIF-range/tag/person filters are supported by SearchService
// and unit-tested; wiring their bulk data sources into the doc projection is a
// tracked follow-up.

import 'dart:async';

import 'package:photo_native/photo_native.dart' show Engine, SearchHit;

import '../../app/app_state.dart';
import '../../backend/native_backend.dart';
import '../../data/library.dart';
import '../../data/models.dart';
import '../../utils/asset_id.dart';
import 'search_service.dart';

/// Named with a `Pablo` prefix to avoid clashing with Flutter Material's
/// `SearchController`.
class PabloSearchController {
  PabloSearchController(this._backend, {this.idleUnload = _defaultIdleUnload});
  final NativeBackend? _backend;

  /// After this long without a semantic query the text encoder's ONNX session
  /// is released (hundreds of MB reclaimed); the next search transparently
  /// reloads it (~1 s pause, once).
  static const _defaultIdleUnload = Duration(minutes: 5);
  final Duration idleUnload;
  Timer? _idleTimer;

  void _armIdleUnload() {
    _idleTimer?.cancel();
    final backend = _backend;
    if (backend == null) return;
    _idleTimer = Timer(idleUnload, () {
      backend.engine.releaseSemanticSessions(Engine.releaseTextTower);
    });
  }

  /// The function installed into [PabloAppState.searchRunner].
  List<Photo> run(String text, AdvSearchCriteria? criteria) {
    final docs = _buildDocs();
    return SearchService(ranker: _ranker).search(
      docs,
      text: text,
      criteria: criteria,
    );
  }

  /// The live result count for a query — drives the modal's real match count.
  int count(String text, AdvSearchCriteria? criteria) =>
      run(text, criteria).length;

  TextRanker? get _ranker {
    final backend = _backend;
    if (backend == null) return null;
    return (String text, List<int> ids) {
      final qv = backend.engine.embedText(text);
      _armIdleUnload(); // text tower is hot now; drop it after a quiet spell
      if (qv.isEmpty) return ids; // no embedder → keep metadata order
      final hits = backend.engine.semanticSearch(qv, candidates: ids);
      final ranked = <int>[for (final SearchHit h in hits) h.assetId];
      final seen = ranked.toSet();
      for (final id in ids) {
        if (!seen.contains(id)) ranked.add(id);
      }
      return ranked;
    };
  }

  List<SearchDoc> _buildDocs() {
    final photos = Library.instance.allPhotos;
    final engine = _backend?.engine;
    final colors = engine?.embeddingColors() ?? const <int, int>{};
    final geotagged = <int>{
      for (final g in engine?.listGeotagged() ?? const []) g.assetId,
    };
    final inAlbum = <int>{};
    if (engine != null) {
      for (final a in engine.listAlbums()) {
        inAlbum.addAll(engine.albumMembers(a.id));
      }
    }

    return [
      for (final p in photos)
        _docFor(p, colors, geotagged, inAlbum),
    ];
  }

  SearchDoc _docFor(
    Photo p,
    Map<int, int> colors,
    Set<int> geotagged,
    Set<int> inAlbum,
  ) {
    final id = assetIdFor(p.id);
    return SearchDoc(
      photo: p,
      assetId: id,
      starred: isStarredAsset(id),
      date: p.modified,
      hasLocation: geotagged.contains(id),
      inAlbum: inAlbum.contains(id),
      fileType: _extType(p.filePath),
      dominantRgb: colors[id],
    );
  }

  static String _extType(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0) return '';
    final ext = path.substring(dot + 1).toLowerCase();
    return switch (ext) {
      'jpg' || 'jpeg' => 'JPEG',
      'png' => 'PNG',
      'heic' || 'heif' => 'HEIC',
      'mp4' => 'MP4',
      'mov' => 'MOV',
      'gif' => 'GIF',
      'webp' => 'WEBP',
      _ => ext.toUpperCase(),
    };
  }
}

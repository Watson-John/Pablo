// Photo / EXIF / tag / suggestion factories.
// Verbatim port of pablo3-foundation.jsx generator logic.

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/hash.dart';
import 'mock_data.dart';
import 'models.dart';

class _PhotoPreset {
  const _PhotoPreset(this.h, this.s, this.l, this.deg, this.s2, this.l2);
  final int h;
  final int s;
  final int l;
  final int deg;
  final int s2;
  final int l2;
}

const _kPresets = <_PhotoPreset>[
  _PhotoPreset(205, 55, 65, 180, 40, 35),
  _PhotoPreset(25, 40, 60, 135, 30, 45),
  _PhotoPreset(150, 40, 45, 180, 35, 30),
  _PhotoPreset(35, 30, 65, 160, 20, 55),
  _PhotoPreset(15, 50, 50, 180, 60, 35),
  _PhotoPreset(260, 25, 55, 135, 15, 70),
  _PhotoPreset(45, 50, 55, 180, 40, 40),
  _PhotoPreset(195, 45, 55, 170, 30, 60),
  _PhotoPreset(350, 30, 55, 135, 25, 40),
  _PhotoPreset(120, 35, 50, 180, 40, 35),
  _PhotoPreset(220, 20, 45, 180, 15, 60),
  _PhotoPreset(10, 45, 50, 160, 35, 65),
];

LinearGradient _gradient(_PhotoPreset p, int hShift) {
  final c1 = HSLColor.fromAHSL(1, ((p.h + hShift) % 360).toDouble(),
          p.s / 100.0, p.l / 100.0)
      .toColor();
  final c2 = HSLColor.fromAHSL(1, ((p.h + hShift + 20) % 360).toDouble(),
          p.s2 / 100.0, p.l2 / 100.0)
      .toColor();
  // Map CSS gradient degrees → Flutter alignment.
  final radians = (p.deg - 90) * 3.1415926535 / 180.0;
  final dx = _cos(radians);
  final dy = _sin(radians);
  return LinearGradient(
    begin: Alignment(-dx, -dy),
    end: Alignment(dx, dy),
    colors: [c1, c2],
  );
}

double _cos(double a) =>
    (a == 0) ? 1 : (a == 3.141592653589793) ? -1 : math.cos(a);
double _sin(double a) => math.sin(a);

// ignore: library_prefixes
List<Photo> makePhotos(String prefix, int count, int seed) {
  return List.generate(count, (i) {
    final pi = (seed + i) % _kPresets.length;
    final p = _kPresets[pi];
    final hShift = (i * 17) % 30 - 15;
    return Photo(
      id: '$prefix-$i',
      label: 'IMG_${3000 + seed * 100 + i}.jpg',
      gradient: _gradient(p, hShift),
      starred: i % 7 == 0,
    );
  });
}

final Map<String, List<Photo>> _photoSets = (() {
  final m = <String, List<Photo>>{};
  for (int ti = 0; ti < kFolders.length; ti++) {
    final top = kFolders[ti];
    for (int fi = 0; fi < top.children.length; fi++) {
      final f = top.children[fi];
      m[f.id] = makePhotos(f.id, f.count < 30 ? f.count : 30, ti * 7 + fi * 3);
    }
  }
  for (int pi = 0; pi < kPeople.length; pi++) {
    final p = kPeople[pi];
    m[p.id] = makePhotos(p.id, p.count < 40 ? p.count : 40, pi * 2 + 1);
  }
  for (int ai = 0; ai < kAlbums.length; ai++) {
    final a = kAlbums[ai];
    m[a.id] = makePhotos(a.id, a.count, ai * 4 + 2);
  }
  for (int ti = 0; ti < kTimelineMonths.length; ti++) {
    final t = kTimelineMonths[ti];
    m[t.id] = makePhotos(t.id, t.count < 20 ? t.count : 20, ti * 5);
  }
  m['unnamed'] = makePhotos('un', 40, 7);
  return m;
})();

// ── Dataset mode (Stage 2b) ──────────────────────────────────────────────
// When PABLO_DATASET_DIR is provided, the gallery shows real image files from
// that folder so the native libvips decoder (PABLO_NATIVE_THUMBS) renders real
// thumbnails through the GPU TextureSlot seam — used to exercise the pipeline
// on the Flickr30k set.
const String kDatasetDir =
    String.fromEnvironment('PABLO_DATASET_DIR', defaultValue: '');
bool get kDatasetMode => kDatasetDir.isNotEmpty;
const int _kDatasetMax = 5000;

const LinearGradient _datasetPlaceholder = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFFEEECE6), Color(0xFFD6D1C6)],
);

List<Photo> _loadDatasetPhotos() {
  try {
    final dir = Directory(kDatasetDir);
    if (!dir.existsSync()) return const [];
    final files = dir
        .listSync(followLinks: false)
        .whereType<File>()
        .where((f) {
          final p = f.path.toLowerCase();
          return p.endsWith('.jpg') ||
              p.endsWith('.jpeg') ||
              p.endsWith('.png');
        })
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    final out = <Photo>[];
    for (final f in files) {
      if (out.length >= _kDatasetMax) break;
      final name = f.path.split(Platform.pathSeparator).last;
      out.add(Photo(
        id: f.path,
        label: name,
        gradient: _datasetPlaceholder,
        starred: false,
        filePath: f.path,
      ));
    }
    return out;
  } catch (_) {
    return const [];
  }
}

final List<Photo> _datasetPhotos =
    kDatasetMode ? _loadDatasetPhotos() : const <Photo>[];

List<Photo> photosFor(String id) {
  if (kDatasetMode && _datasetPhotos.isNotEmpty) return _datasetPhotos;
  return _photoSets[id] ?? const [];
}

// ── Suggestions per person ──
class _SuggPreset {
  const _SuggPreset(this.h, this.s, this.l, this.deg, this.s2, this.l2);
  final int h;
  final int s;
  final int l;
  final int deg;
  final int s2;
  final int l2;
}

const _kSuggPresets = <_SuggPreset>[
  _SuggPreset(25, 40, 60, 135, 30, 45),
  _SuggPreset(205, 50, 62, 160, 38, 40),
  _SuggPreset(15, 45, 55, 150, 35, 42),
  _SuggPreset(35, 32, 64, 140, 22, 52),
];

List<Suggestion> makeSuggestions(String personId, int seed) =>
    List.generate(4, (i) {
      final p = _kSuggPresets[i % 4];
      final c1 = HSLColor.fromAHSL(1, p.h.toDouble(), p.s / 100, p.l / 100).toColor();
      final c2 = HSLColor.fromAHSL(1, (p.h + 20).toDouble(), p.s2 / 100, p.l2 / 100).toColor();
      final radians = (p.deg - 90) * 3.1415926535 / 180.0;
      final dx = _cos(radians);
      final dy = _sin(radians);
      return Suggestion(
        id: 'sug-$personId-$i',
        gradient: LinearGradient(
          begin: Alignment(-dx, -dy),
          end: Alignment(dx, dy),
          colors: [c1, c2],
        ),
        confidence: i < 2 ? SuggestionConfidence.high : SuggestionConfidence.low,
        label: 'NEW_${8000 + seed * 10 + i}.jpg',
      );
    });

final Map<String, List<Suggestion>> _suggestions = {
  for (int i = 0; i < kPeople.length; i++)
    kPeople[i].id: makeSuggestions(kPeople[i].id, i * 7 + 3),
};

List<Suggestion> suggestionsFor(String personId) =>
    _suggestions[personId] ?? const [];

// ── EXIF generators ──
const _cams = [
  {'make': 'Canon', 'model': 'EOS R5', 'lens': '24-70mm f/2.8L II USM'},
  {'make': 'Sony', 'model': 'α7 IV', 'lens': '85mm f/1.4 GM'},
  {'make': 'Nikon', 'model': 'Z6 III', 'lens': '24-120mm f/4 S'},
  {'make': 'Apple', 'model': 'iPhone 15 Pro', 'lens': 'Built-in camera'},
  {'make': 'Fujifilm', 'model': 'X-T5', 'lens': '16-80mm f/4 R OIS WR'},
];
const _aper = ['f/1.4', 'f/1.8', 'f/2.0', 'f/2.8', 'f/4.0', 'f/5.6', 'f/8.0'];
const _shut = ['1/2000', '1/1000', '1/500', '1/250', '1/125', '1/60', '1/30'];
const _iso = [100, 200, 400, 800, 1600, 3200];
const _focal = [24, 35, 50, 85, 100, 135];
const _loc = [
  'Portland, OR', 'Miami Beach, FL', 'Yellowstone, WY',
  'New York, NY', 'Seattle, WA', 'San Diego, CA',
];
const _tags = [
  'vacation', 'family', 'outdoor', 'portrait', 'candid', 'birthday',
  'christmas', 'beach', 'sunset', 'kids', 'edited', 'school',
  'landscape', 'travel', 'holiday', 'nature', 'food',
];

ExifData getPhotoExif(String id) {
  final h = pabloHash(id);
  final c = _cams[h % _cams.length];
  final y = 2022 + h % 3;
  final mo = (1 + (h >> 2) % 12).toString().padLeft(2, '0');
  final d = (1 + (h >> 4) % 28).toString().padLeft(2, '0');
  final hr = (8 + (h >> 6) % 13).toString().padLeft(2, '0');
  final mn = ((h >> 8) % 60).toString().padLeft(2, '0');
  final sc = ((h >> 10) % 60).toString().padLeft(2, '0');
  const widths = [6720, 7952, 6048, 4032, 8256];
  const heights = [4480, 5304, 4024, 3024, 5504];
  return ExifData(
    camera: '${c["make"]} ${c["model"]}',
    lens: c['lens']!,
    aperture: _aper[(h >> 1) % 7],
    shutter: _shut[(h >> 3) % 7],
    iso: _iso[(h >> 5) % 6],
    focalLength: '${_focal[(h >> 7) % _focal.length]}mm',
    date: '$y-$mo-$d',
    time: '$hr:$mn:$sc',
    width: widths[h % 5],
    height: heights[h % 5],
    fileSize: '${3 + (h >> 9) % 22} MB',
    format: ['JPEG', 'JPEG', 'JPEG', 'RAW', 'HEIC'][(h >> 11) % 5],
    colorSpace: 'sRGB',
    location: h % 4 == 0 ? _loc[(h >> 13) % _loc.length] : null,
  );
}

List<String> getPhotoTags(String id) {
  final h = pabloHash(id);
  final count = 1 + h % 4;
  final tags = <String>[];
  for (int i = 0; i < count; i++) {
    final t = _tags[(h + i * 7) % _tags.length];
    if (!tags.contains(t)) tags.add(t);
  }
  return tags;
}

class TaggedPerson {
  TaggedPerson({
    required this.id,
    required this.name,
    required this.hue,
    required this.confirmed,
  });
  final String id;
  final String name;
  final int hue;
  bool confirmed;
}

List<TaggedPerson> getPhotoPeople(String id) {
  final h = pabloHash(id);
  final count = h % 4;
  final out = <TaggedPerson>[];
  final used = <String>{};
  for (int i = 0; i < count; i++) {
    final p = kPeople[(h + i * 5) % kPeople.length];
    if (used.contains(p.id)) continue;
    used.add(p.id);
    out.add(TaggedPerson(
      id: p.id,
      name: p.name,
      hue: p.hue,
      confirmed: (h >> (i + 2)) % 3 != 0,
    ));
  }
  if ((h >> 8) % 5 == 0 && out.isNotEmpty) {
    out.add(TaggedPerson(
      id: 'unk-$h',
      name: 'Unknown Person',
      hue: (h * 7) % 360,
      confirmed: false,
    ));
  }
  return out;
}


// Data models for Pablo.
//
// Photos store a precomputed `gradient` (matching the linear-gradient(...) the
// React app generates). Hue/Confidence numbers from the mockup port directly.

import 'package:flutter/material.dart';

class Person {
  const Person({
    required this.id,
    required this.name,
    required this.count,
    required this.lastDate,
    required this.hue,
    this.confirmed = true,
  });

  final String id;
  final String name;
  final int count;
  final String lastDate;
  final int hue;
  final bool confirmed;

  Person copyWith({String? name, int? hue, bool? confirmed}) => Person(
        id: id,
        name: name ?? this.name,
        count: count,
        lastDate: lastDate,
        hue: hue ?? this.hue,
        confirmed: confirmed ?? this.confirmed,
      );
}

class Album {
  const Album({
    required this.id,
    required this.name,
    required this.count,
    required this.created,
  });

  final String id;
  final String name;
  final int count;
  final String created;
}

class FolderNode {
  const FolderNode({
    required this.id,
    required this.name,
    this.count = 0,
    this.date = '',
    this.path = '',
    this.children = const [],
  });

  final String id;
  final String name;
  final int count;
  final String date;
  final String path;
  final List<FolderNode> children;

  bool get isGroup => children.isNotEmpty;
}

class TimelineNode {
  const TimelineNode({
    required this.id,
    required this.label,
    this.count = 0,
    this.children = const [],
  });

  final String id;
  final String label;
  final int count;
  final List<TimelineNode> children;

  bool get isLeaf => children.isEmpty;
}

class UnnamedFace {
  const UnnamedFace({required this.id, required this.hue, required this.count});
  final String id;
  final int hue;
  final int count;
}

class Photo {
  const Photo({
    required this.id,
    required this.label,
    required this.gradient,
    required this.starred,
    this.filePath,
  });

  final String id;
  final String label;
  final LinearGradient gradient;
  final bool starred;

  /// Absolute path to a real image file (dataset / import mode). Null for the
  /// gradient mockup. When set, PhotoThumb routes it to the native libvips
  /// decoder via the TextureSlot seam.
  final String? filePath;
}

class Suggestion {
  const Suggestion({
    required this.id,
    required this.gradient,
    required this.confidence,
    required this.label,
  });

  final String id;
  final LinearGradient gradient;
  final SuggestionConfidence confidence;
  final String label;
}

enum SuggestionConfidence { high, low }

class ExifData {
  const ExifData({
    required this.camera,
    required this.lens,
    required this.aperture,
    required this.shutter,
    required this.iso,
    required this.focalLength,
    required this.date,
    required this.time,
    required this.width,
    required this.height,
    required this.fileSize,
    required this.format,
    required this.colorSpace,
    required this.location,
  });

  final String camera;
  final String lens;
  final String aperture;
  final String shutter;
  final int iso;
  final String focalLength;
  final String date;
  final String time;
  final int width;
  final int height;
  final String fileSize;
  final String format;
  final String colorSpace;
  final String? location;
}

class MapLocation {
  const MapLocation({
    required this.id,
    required this.name,
    required this.cx,
    required this.cy,
    required this.count,
  });
  final String id;
  final String name;
  final double cx;
  final double cy;
  final int count;
}

class TaskInfo {
  TaskInfo({required this.id, required this.name, required this.percent});
  final String id;
  final String name;
  double percent;
}

enum NavSection { folders, people, albums, timeline, map, unnamed }

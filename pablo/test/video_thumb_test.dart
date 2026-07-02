// video_thumb_test.dart — §11 grid affordances: duration formatting, the video
// badge (play circle + duration pill), and the library scan accepting video
// extensions.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/data/library.dart';
import 'package:pablo/data/models.dart';
import 'package:pablo/features/gallery/photo_thumb.dart';

void main() {
  group('formatDuration', () {
    test('m:ss under an hour', () {
      expect(formatDuration(0), '0:00');
      expect(formatDuration(5000), '0:05');
      expect(formatDuration(65000), '1:05');
      expect(formatDuration(600000), '10:00');
    });
    test('h:mm:ss over an hour', () {
      expect(formatDuration(3661000), '1:01:01');
    });
    test('rounds to the nearest second', () {
      expect(formatDuration(1500), '0:02');
    });
  });

  group('isVideoPath', () {
    test('accepts video extensions case-insensitively', () {
      expect(isVideoPath('/a/b.mp4'), isTrue);
      expect(isVideoPath('/a/b.MOV'), isTrue);
      expect(isVideoPath('/a/clip.webm'), isTrue);
    });
    test('rejects images and extensionless paths', () {
      expect(isVideoPath('/a/b.jpg'), isFalse);
      expect(isVideoPath('/a/b'), isFalse);
    });
  });

  testWidgets('a video thumb shows the play circle and duration pill',
      (t) async {
    const photo = Photo(
      id: '/v/clip.mp4',
      label: 'clip.mp4',
      filePath: '/v/clip.mp4',
      isVideo: true,
      durationMs: 65000,
    );
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: PhotoThumb(
          photo: photo,
          size: 200,
          selected: false,
          inTray: false,
        ),
      ),
    ));
    await t.pump();
    // The duration pill renders the formatted length (not hovering).
    expect(find.text('1:05'), findsOneWidget);
  });

  testWidgets('a photo thumb shows no video affordances', (t) async {
    const photo = Photo(
      id: '/p/a.jpg',
      label: 'a.jpg',
      filePath: '/p/a.jpg',
    );
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: PhotoThumb(
          photo: photo,
          size: 200,
          selected: false,
          inTray: false,
        ),
      ),
    ));
    await t.pump();
    expect(find.text('0:00'), findsNothing);
  });
}

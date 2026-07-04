// Widget tests for lightbox navigation: arrow keys page next/prev (the
// onCurrentChanged callback + the "n / total" counter are the observable
// surface), Escape fires onClose, and a mouse-wheel scroll over the main image
// pages too. Hermetic: LightboxView is constructed directly over an in-memory
// photo list — with no native backend PhotoSurface renders its neutral
// fallback, and the offline PeopleController (MockFaceRepository) surfaces no
// faces, so no engine is needed.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:pablo/data/models.dart';
import 'package:pablo/data/sources/face_repository.dart';
import 'package:pablo/features/gallery/lightbox_view.dart';
import 'package:pablo/features/gallery/widgets/lightbox_image.dart';
import 'package:pablo/features/people/people_controller.dart';
import 'package:pablo/features/people/people_scope.dart';

List<Photo> _photos(int n) => [
      for (var i = 0; i < n; i++)
        Photo(id: 'p$i', label: 'p$i.jpg', filePath: '/nonexistent/p$i.jpg'),
    ];

/// Pumps a LightboxView the way pablo_app hosts it: under a PeopleScope (the
/// face-overlay lookup) inside a MaterialApp. Waits one frame so the widget's
/// post-frame focus request lands and the keyboard shortcuts are live.
Future<void> _pumpLightbox(
  WidgetTester t, {
  required List<Photo> photos,
  required String initialId,
  VoidCallback? onClose,
  ValueChanged<String>? onCurrentChanged,
}) async {
  final pc = PeopleController(const MockFaceRepository());
  addTearDown(pc.dispose);
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: PeopleScope(
        notifier: pc,
        child: LightboxView(
          photos: photos,
          initialId: initialId,
          onClose: onClose ?? () {},
          onCurrentChanged: onCurrentChanged,
        ),
      ),
    ),
  ));
  await t.pump();
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('right/left arrow keys move to next/prev photo', (t) async {
    await t.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => t.binding.setSurfaceSize(null));

    final changes = <String>[];
    await _pumpLightbox(
      t,
      photos: _photos(3),
      initialId: 'p1',
      onCurrentChanged: changes.add,
    );
    expect(find.text('2 / 3'), findsOneWidget); // opened on the middle photo

    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pumpAndSettle();
    expect(changes, ['p2']);
    expect(find.text('3 / 3'), findsOneWidget);

    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await t.pumpAndSettle();
    expect(changes, ['p2', 'p1', 'p0']);
    expect(find.text('1 / 3'), findsOneWidget);

    // At the first photo, left clamps — still showing p0.
    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await t.pumpAndSettle();
    expect(changes.last, 'p0');
    expect(find.text('1 / 3'), findsOneWidget);
  });

  testWidgets('Escape fires onClose (windowed mode)', (t) async {
    await t.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => t.binding.setSurfaceSize(null));

    var closed = 0;
    await _pumpLightbox(
      t,
      photos: _photos(2),
      initialId: 'p0',
      onClose: () => closed++,
    );

    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pump();
    expect(closed, 1);
  });

  testWidgets('mouse wheel over the main image pages next/prev', (t) async {
    await t.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => t.binding.setSurfaceSize(null));

    final changes = <String>[];
    await _pumpLightbox(
      t,
      photos: _photos(3),
      initialId: 'p0',
      onCurrentChanged: changes.add,
    );
    expect(find.text('1 / 3'), findsOneWidget);

    // Scroll down over the main image area → next photo.
    final center = t.getCenter(find.byType(LightboxImage));
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await t.sendEventToBinding(pointer.hover(center));
    await t.sendEventToBinding(pointer.scroll(const Offset(0, 120)));
    await t.pumpAndSettle();
    expect(changes, ['p1']);
    expect(find.text('2 / 3'), findsOneWidget);

    // Scroll up → previous photo.
    await t.sendEventToBinding(pointer.scroll(const Offset(0, -120)));
    await t.pumpAndSettle();
    expect(changes, ['p1', 'p0']);
    expect(find.text('1 / 3'), findsOneWidget);
  });
}

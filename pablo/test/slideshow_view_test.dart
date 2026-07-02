// slideshow_view_test.dart — the fullscreen slideshow widget: renders the
// counter, auto-advances on the interval, and Esc pops the route. PhotoSurface
// falls back to a plain surface with no backend in scope, so no engine needed.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/data/models.dart';
import 'package:pablo/features/slideshow/slideshow_view.dart';

List<Photo> _photos(int n) => [
      for (var i = 0; i < n; i++)
        Photo(id: 'p$i', label: 'p$i.jpg', filePath: '/x/p$i.jpg'),
    ];

void main() {
  testWidgets('shows the counter and auto-advances on the interval',
      (t) async {
    await t.pumpWidget(MaterialApp(
      home: SlideshowView(
        photos: _photos(3),
        interval: const Duration(seconds: 1),
      ),
    ));
    await t.pump(); // run the post-frame play()
    expect(find.text('1 / 3'), findsOneWidget);

    await t.pump(const Duration(seconds: 1)); // auto-advance
    expect(find.text('2 / 3'), findsOneWidget);

    // Unmount so the periodic/hide timers are cancelled (no pending-timer fail).
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Escape pops the slideshow route', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showSlideshow(context, photos: _photos(2)),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    expect(find.text('1 / 2'), findsOneWidget); // slideshow is up

    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.text('1 / 2'), findsNothing); // popped
    expect(find.text('go'), findsOneWidget); // back to launcher
  });
}

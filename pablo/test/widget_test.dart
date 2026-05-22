// Smoke test for the Pablo desktop shell.

import 'package:flutter_test/flutter_test.dart';

import 'package:pablo/app/pablo_app.dart';

void main() {
  testWidgets('Pablo app boots and shows title bar', (tester) async {
    await tester.pumpWidget(const PabloApp());
    await tester.pump();
    expect(find.text('Pablo'), findsWidgets);
  });
}

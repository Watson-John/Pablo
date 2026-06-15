// Verifies the People seam preserves the default (mock) app's data: with the
// MockFaceRepository, PeopleController must surface the same kPeople /
// kUnnamedFaces rows and the legacy sidebar count, and report itself offline.

import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/data/mock/mock_data.dart';
import 'package:pablo/data/sources/face_repository.dart';
import 'package:pablo/features/people/people_controller.dart';

void main() {
  group('PeopleController (mock mode)', () {
    late PeopleController controller;

    setUp(() => controller = PeopleController(const MockFaceRepository()));
    tearDown(() => controller.dispose());

    test('is not live', () {
      expect(controller.isLive, isFalse);
    });

    test('surfaces the mock people and unnamed rows unchanged', () {
      expect(controller.people(), same(kPeople));
      expect(controller.unnamedFaces(), same(kUnnamedFaces));
    });

    test('sidebar Unnamed Faces count is the legacy mockup figure', () {
      expect(controller.unnamedFaceCount(), kMockUnnamedCount);
    });

    test('peopleTotal sums person counts plus the unnamed figure', () {
      final expected =
          kPeople.fold<int>(0, (s, p) => s + p.count) + kMockUnnamedCount;
      expect(controller.peopleTotal(), expected);
    });

    test('live-only face queries are empty and mutations are no-ops', () {
      expect(controller.suggestionsForPerson(1), isEmpty);
      expect(controller.facesInCluster(1), isEmpty);
      expect(controller.facesForAsset(1), isEmpty);
      expect(controller.confirmedFacesForPerson(1), isEmpty);
      // Mutations return without throwing (repo returns 0 / no event).
      controller.approve(clusterId: 1, faceId: 1);
      controller.reject(clusterId: 1, faceId: 1);
    });

    test('native id parsing handles live ids and ignores mock ids', () {
      expect(PeopleController.nativePersonId('np42'), 42);
      expect(PeopleController.nativeClusterId('nc7'), 7);
      expect(PeopleController.nativePersonId('p1'), isNull);
    });
  });
}

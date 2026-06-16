// With the mock library stripped, the offline PeopleController surfaces no
// people or faces (the live native pipeline is the only source). This verifies
// the offline repo is empty + offline, and that the native-id parsing helpers
// still behave.

import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/data/sources/face_repository.dart';
import 'package:pablo/features/people/people_controller.dart';

void main() {
  group('PeopleController (offline mode)', () {
    late PeopleController controller;

    setUp(() => controller = PeopleController(const MockFaceRepository()));
    tearDown(() => controller.dispose());

    test('is not live', () {
      expect(controller.isLive, isFalse);
    });

    test('surfaces no people or faces without a live backend', () {
      expect(controller.people(), isEmpty);
      expect(controller.unnamedFaces(), isEmpty);
      expect(controller.unnamedFaceCount(), 0);
      expect(controller.peopleTotal(), 0);
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
      // Happy path.
      expect(PeopleController.nativePersonId('np42'), 42);
      expect(PeopleController.nativeClusterId('nc7'), 7);
      // Non-prefixed ids → null.
      expect(PeopleController.nativePersonId('p1'), isNull);
      expect(PeopleController.nativeClusterId('uf-3'), isNull);
      // Right prefix, non-numeric / empty suffix → null (not 0 or a throw).
      expect(PeopleController.nativePersonId('np'), isNull);
      expect(PeopleController.nativePersonId('npx'), isNull);
      expect(PeopleController.nativeClusterId('ncZ'), isNull);
      // Cross-prefix: a cluster id is not a person id and vice versa.
      expect(PeopleController.nativePersonId('nc7'), isNull);
      expect(PeopleController.nativeClusterId('np42'), isNull);
    });
  });
}

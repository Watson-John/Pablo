// Verifies PeopleController forwards the §7 face-editing operations (ignore,
// manual rect, assign, remove, XMP export) to the repository and notifies its
// listeners so the People UI re-queries.

import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/data/sources/face_repository.dart';
import 'package:pablo/features/people/people_controller.dart';

class _RecordingRepo extends MockFaceRepository {
  const _RecordingRepo(this.log);
  final List<String> log;

  @override
  int setFaceIgnored(int faceId, bool ignored) {
    log.add('ignore:$faceId:$ignored');
    return 0;
  }

  @override
  int addManualFace(int assetId,
      {required double x,
      required double y,
      required double w,
      required double h}) {
    log.add('manual:$assetId:$x,$y,$w,$h');
    return 777;
  }

  @override
  int assignFace(int faceId, String name) {
    log.add('assign:$faceId:$name');
    return 0;
  }

  @override
  int removeFace(int faceId) {
    log.add('remove:$faceId');
    return 0;
  }

  @override
  String? writeFaceXmp(int assetId) {
    log.add('xmp:$assetId');
    return '/photos/img.jpg.xmp';
  }
}

void main() {
  test('controller forwards face-editing ops and notifies', () {
    final log = <String>[];
    final c = PeopleController(_RecordingRepo(log));
    addTearDown(c.dispose);

    var notifications = 0;
    c.addListener(() => notifications++);

    c.setFaceIgnored(5, true);
    final id = c.addManualFace(9, x: 10, y: 20, w: 30, h: 40);
    c.assignFace(3, 'Ada Lovelace');
    c.removeFace(2);
    final xmp = c.writeFaceXmp(1);

    expect(log, [
      'ignore:5:true',
      'manual:9:10.0,20.0,30.0,40.0',
      'assign:3:Ada Lovelace',
      'remove:2',
      'xmp:1',
    ]);
    expect(id, 777);
    expect(xmp, '/photos/img.jpg.xmp');
    // ignore + manual + assign + remove each notify (writeFaceXmp does not).
    expect(notifications, 4);
  });

  test('offline mock repo makes editing ops safe no-ops', () {
    final c = PeopleController(const MockFaceRepository());
    addTearDown(c.dispose);
    expect(c.addManualFace(1, x: 0, y: 0, w: 1, h: 1), 0);
    expect(c.writeFaceXmp(1), isNull);
    // Does not throw.
    c.setFaceIgnored(1, true);
    c.assignFace(1, 'x');
    c.removeFace(1);
  });
}

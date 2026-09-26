import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixora/editor/tools/snapping.dart';

void main() {
  test('a moved box snaps its nearest edge or centre', () {
    final t = SnapTargets([0, 50, 100], [0, 50, 100]);
    // Left edge 3 px from 50: pulled onto it.
    final (shift, gx, gy) = t.snapBox(const Rect.fromLTWH(53, 20, 10, 10), 7);
    expect(shift.dx, -3);
    expect(gx, 50);
    expect(shift.dy, 0);
    expect(gy, isNull);
  });

  test('a node snaps to another node on each axis', () {
    final t = SnapTargets([], [])..addPoint(const Offset(40, 60));
    final (p, gx, gy) = t.snapPoint(const Offset(44, 90), 7);
    expect(p, const Offset(40, 90));
    expect(gx, 40);
    expect(gy, isNull);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:pixora/editor/tools/transform_tool.dart';

/// On a small layer the handles crowd together: the one picked is the
/// nearest, and each reaches at most half way to its neighbour.
void main() {
  Offset? pick(List<Offset> hs, Offset p) =>
      TransformTool.nearestHandle<Offset>(hs, p, (h) => h);

  test('nearest handle wins, reach shrinks on small boxes', () {
    // A 24 px box: corners 24 px apart.
    const box = [Offset(0, 0), Offset(24, 0), Offset(24, 24), Offset(0, 24)];
    expect(pick(box, const Offset(3, 2)), box[0]);
    expect(pick(box, const Offset(22, 21)), box[2]);
    // The middle is beyond every corner's reach: it moves the layer.
    expect(pick(box, const Offset(12, 12)), isNull);
  });

  test('big boxes keep the full reach', () {
    const box = [Offset(0, 0), Offset(300, 0), Offset(150, 0)];
    expect(pick(box, const Offset(150, 20)), box[2]);
    expect(pick(box, const Offset(150, 30)), isNull);
  });
}

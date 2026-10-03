import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pixora/document/model/layer.dart';
import 'package:pixora/document/render/brush_paint.dart';

Future<List<int>> _render(BrushStroke s) async {
  final rec = ui.PictureRecorder();
  paintBrushStroke(ui.Canvas(rec), s);
  final img = rec.endRecording().toImageSync(200, 80);
  return (await img.toByteData())!.buffer.asUint8List();
}

int _covered(List<int> px) {
  var n = 0;
  for (var i = 3; i < px.length; i += 4) {
    if (px[i] > 20) n++;
  }
  return n;
}

final _pts = [
  for (var k = 0; k <= 30; k++)
    ui.Offset(20 + 160 * k / 30, 40 + 12 * math.sin(k / 30 * 2 * math.pi)),
];

void main() {
  test('every brush paints', () async {
    for (final t in BrushType.values) {
      final px = await _render(
        BrushStroke(
          points: _pts,
          type: t,
          color: const ui.Color(0xFF2266DD),
          width: 14,
          seed: 4,
        ),
      );
      expect(_covered(px), greaterThan(200), reason: t.name);
    }
  });

  test('taper thins the ends, spacing makes dots', () async {
    int columnInk(List<int> px, int x) {
      var n = 0;
      for (var y = 0; y < 80; y++) {
        if (px[(y * 200 + x) * 4 + 3] > 40) n++;
      }
      return n;
    }

    final straight = [
      for (var k = 0; k <= 30; k++) ui.Offset(20 + 160 * k / 30, 40),
    ];
    BrushStroke s(BrushTip t) =>
        BrushStroke(points: straight, type: BrushType.round, width: 20, tip: t);
    final tapered = await _render(
      s(const BrushTip(spacing: 0.05, taperStart: 0.3, taperEnd: 0.3)),
    );
    expect(columnInk(tapered, 100), greaterThan(columnInk(tapered, 25) + 6));
    final dots = await _render(s(const BrushTip(spacing: 2)));
    // Gaps between dots along the line.
    final row = [for (var x = 20; x < 180; x++) dots[(40 * 200 + x) * 4 + 3]];
    expect(row.where((a) => a < 10).length, greaterThan(40));
  });

  test('tip settings survive JSON; dynamics are repeatable', () async {
    const tip = BrushTip(
      shape: TipShape.star,
      hardness: 0.4,
      spacing: 0.7,
      angle: 30,
      roundness: 0.6,
      followPath: true,
      sizeJitter: 0.5,
      minSize: 0.2,
      angleJitter: 0.3,
      pressureSize: true,
      taperStart: 0.1,
      taperEnd: 0.2,
      scatter: 1.2,
      count: 3,
      countJitter: 0.4,
      flow: 0.6,
      flowJitter: 0.5,
      pressureOpacity: true,
      hueJitter: 0.2,
      saturationJitter: 0.1,
      brightnessJitter: 0.3,
    );
    final s = BrushStroke(
      points: _pts,
      type: BrushType.stars,
      width: 16,
      seed: 99,
      tip: tip,
      pressures: [for (var i = 0; i < _pts.length; i++) i / _pts.length],
    );
    final back = BrushStroke.fromJson(s.toJson());
    expect(back.tip, tip);
    expect(back.pressures!.length, _pts.length);
    // Same seed, same dabs (JSON rounds pressures, so compare a stroke
    // with itself, and the round trip by coverage).
    expect(await _render(s), await _render(s));
    final a = _covered(await _render(s)), b = _covered(await _render(back));
    expect((a - b).abs(), lessThan(math.max(12, a * 0.05)));
  });
}

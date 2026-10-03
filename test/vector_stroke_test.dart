import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixora/document/model/fill.dart';
import 'package:pixora/document/model/layer.dart';
import 'package:pixora/document/render/vector_paths.dart';
import 'package:pixora/features/editor/panels/vector_panels.dart';

Future<List<int>> _render(PathLayer l) async {
  final rec = ui.PictureRecorder();
  final c = ui.Canvas(rec)..translate(60, 40);
  paintPathLayer(c, l);
  final img = rec.endRecording().toImageSync(120, 80);
  return (await img.toByteData())!.buffer.asUint8List();
}

int _ink(List<int> px) {
  var n = 0;
  for (var i = 3; i < px.length; i += 4) {
    if (px[i] > 60) n++;
  }
  return n;
}

int _alpha(List<int> px, int x, int y) => px[(y * 120 + x) * 4 + 3];

PathLayer _line({double w = 10}) => PathLayer(
  LayerProps(name: 'l'),
  contours: [
    PathContour(
      nodes: const [PathNode(Offset(-40, 0)), PathNode(Offset(40, 0))],
    ),
  ],
  strokeWidth: w,
);

void main() {
  test('every preset draws', () async {
    for (final p in vectorPresets(30)) {
      expect(_ink(await _render(p.layer)), greaterThan(40), reason: p.id);
    }
  });

  test('width profiles taper with clean round ends', () async {
    final even = await _render(_line(w: 14));
    final pointed = await _render(
      _line(w: 14).copyWith(profile: WidthProfile.taperBoth),
    );
    // Full width in the middle, thin near the ends.
    expect(_alpha(pointed, 60, 46), greaterThan(200));
    expect(_alpha(pointed, 24, 46), lessThan(_alpha(even, 24, 46)));
    // Taper in: no notch at the round, wide end.
    final taperIn = await _render(
      _line(w: 14).copyWith(profile: WidthProfile.taperStart),
    );
    expect(_alpha(taperIn, 99, 40), greaterThan(200));
  });

  test('align, joins and custom dashes', () async {
    final blob = vectorPresets(30)
        .firstWhere((p) => p.id == 'blob')
        .layer
        .copyWith(strokeWidth: 8, noFill: true);
    final centre = _ink(await _render(blob));
    final inside = _ink(
      await _render(blob.copyWith(align: StrokeAlign.inside)),
    );
    final outside = _ink(
      await _render(blob.copyWith(align: StrokeAlign.outside)),
    );
    expect(outside, greaterThan(centre));
    expect(inside, lessThan(outside));
    final dashed = await _render(
      _line(w: 6).copyWith(
        dash: DashStyle.custom,
        dashPattern: const [2, 2],
        cap: StrokeCap.butt,
      ),
    );
    final row = [for (var x = 22; x < 98; x++) _alpha(dashed, x, 40)];
    expect(row.where((a) => a < 20).length, greaterThan(20));
  });

  test('reverse moves the arrowheads; new fields survive JSON', () async {
    final arrow = _line(w: 4)
        .copyWith(endHead: ArrowHead.triangle, endHeadSize: 3);
    final before = await _render(arrow);
    final after = await _render(arrow.reversed());
    // The big head was on the right, now it is on the left.
    expect(_alpha(before, 96, 40), greaterThan(150));
    expect(_alpha(after, 24, 40), greaterThan(150));
    final l = arrow.copyWith(
      join: StrokeJoin.miter,
      miterLimit: 7,
      align: StrokeAlign.outside,
      profile: WidthProfile.bulge,
      dash: DashStyle.custom,
      dashPattern: const [4, 1, 0, 1],
      startHead: ArrowHead.stealth,
      fill: PixFill.color(const ui.Color(0xFF00FF00)),
    );
    final back = PathLayer.fromJson(l.props, l.contentToJson());
    expect(back, l);
  });
}

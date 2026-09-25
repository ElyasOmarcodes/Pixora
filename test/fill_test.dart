import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixora/core/colors/recent_colors.dart';
import 'package:pixora/document/model/fill.dart';

void main() {
  test('every gradient style round-trips through JSON', () {
    for (final k in FillKind.values.where(
      (k) => k != FillKind.solid && k != FillKind.pattern,
    )) {
      final f = PixFill.gradient(
        k,
        const [Color(0xFFFF0000), Color(0x8000FF00), Color(0xFF0000FF)],
        stops: const [0, 0.3, 1],
        angle: 30,
        scale: 1.5,
        center: const Offset(0.2, -0.4),
      );
      final back = PixFill.fromJson(f.toJson());
      expect(back.kind, k);
      expect(back.colors, f.colors);
      expect(back.stops, f.stops);
      expect(back.scale, 1.5);
      expect(back.center, const Offset(0.2, -0.4));
      if (k != FillKind.radial) expect(back.angle, 30);
    }
    // Old files (no scale / centre) still load.
    final old = PixFill.fromJson({
      'kind': 'linear',
      'colors': ['#FF000000', '#FFFFFFFF'],
    });
    expect(old.angle, 135);
    expect(old.scale, 1);
    expect(old.center, Offset.zero);
  });

  test('reverse, even stops and painting', () {
    final f = PixFill.gradient(
      FillKind.linear,
      const [Colors.red, Colors.blue],
      stops: const [0.2, 1],
    );
    final r = f.reversed();
    expect(r.colors, [Colors.blue, Colors.red]);
    expect(r.stops![0], closeTo(0, 1e-9));
    expect(r.stops![1], closeTo(0.8, 1e-9));
    expect(
      PixFill.linear(const [Colors.red, Colors.green, Colors.blue])
          .effectiveStops,
      [0, 0.5, 1],
    );
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    for (final k in FillKind.values) {
      c.drawRect(
        const Rect.fromLTWH(0, 0, 100, 50),
        PixFill.gradient(k, const [
          Colors.red,
          Colors.blue,
        ]).applyTo(Paint(), const Rect.fromLTWH(0, 0, 100, 50)),
      );
    }
    rec.endRecording().dispose();
  });

  test('recent colours: newest first, unique, at most 20', () {
    final r = RecentColors.instance;
    for (var i = 0; i < 25; i++) {
      r.addColor(Color(0xFF000000 + i));
    }
    r.addColor(const Color(0xFF000005));
    expect(r.colors.length, RecentColors.max);
    expect(r.colors.first, const Color(0xFF000005));
    expect(r.colors.where((c) => c == const Color(0xFF000005)).length, 1);
    final g = PixFill.linear(const [Colors.red, Colors.blue]);
    r
      ..addGradient(g)
      ..addGradient(PixFill.color(Colors.red))
      ..addGradient(g);
    expect(r.gradients, [g]);
  });
}

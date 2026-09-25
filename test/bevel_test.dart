import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixora/document/assets/asset_store.dart';
import 'package:pixora/document/effects/effect_registry.dart';
import 'package:pixora/document/model/document.dart';
import 'package:pixora/document/model/effect.dart';
import 'package:pixora/document/model/fill.dart';
import 'package:pixora/document/model/layer.dart';
import 'package:pixora/document/model/layer_transform.dart';
import 'package:pixora/document/render/bevel_engine.dart';
import 'package:pixora/document/render/document_renderer.dart';

/// A 60×60 canvas with an opaque square from 15 to 45.
const w = 60, h = 60;
Float32List square() {
  final a = Float32List(w * h);
  for (var y = 15; y < 45; y++) {
    for (var x = 15; x < 45; x++) {
      a[y * w + x] = 1;
    }
  }
  return a;
}

double at(Float32List m, int x, int y) => m[y * w + x];

void main() {
  test('inner bevel: lit from the upper left, flat in the middle', () {
    // Photoshop's default light: 120°, 30° altitude.
    final (hl, sh) = BevelCache.shade(
      square(),
      w,
      h,
      1,
      const BevelParams(size: 6, technique: BevelTechnique.chiselHard),
    );
    expect(at(hl, 17, 30), greaterThan(0.2)); // left edge: highlight
    expect(at(hl, 30, 17), greaterThan(0.2)); // top edge: highlight
    expect(at(sh, 42, 30), greaterThan(0.2)); // right edge: shadow
    expect(at(sh, 30, 42), greaterThan(0.2)); // bottom edge: shadow
    expect(at(hl, 30, 30), 0); // flat top of the bevel
    expect(at(sh, 30, 30), 0);
    expect(at(hl, 10, 30) + at(sh, 50, 30), 0); // nothing outside
  });

  test('direction down swaps the lit and shaded sides', () {
    final (hl, sh) = BevelCache.shade(
      square(),
      w,
      h,
      1,
      const BevelParams(size: 6, up: false),
    );
    expect(at(sh, 17, 30), greaterThan(at(hl, 17, 30)));
    expect(at(hl, 42, 30), greaterThan(at(sh, 42, 30)));
  });

  test('outer bevel paints only outside; emboss and pillow both sides', () {
    final (hl, sh) = BevelCache.shade(
      square(),
      w,
      h,
      1,
      const BevelParams(kind: BevelKind.outer, size: 6),
    );
    expect(at(hl, 30, 30) + at(sh, 30, 30), 0);
    expect(at(hl, 17, 30) + at(sh, 17, 30), 0); // inside the shape
    // Outside, the bevel slopes down away from the shape: the left side
    // faces the light, the right side turns away from it.
    expect(at(hl, 12, 30), greaterThan(0.1));
    expect(at(sh, 47, 30), greaterThan(0.1));
    for (final k in [BevelKind.emboss, BevelKind.pillow]) {
      final (h2, s2) = BevelCache.shade(
        square(),
        w,
        h,
        1,
        BevelParams(kind: k, size: 8, depth: 3),
      );
      final inside = at(h2, 17, 30) + at(s2, 17, 30);
      final outside = at(h2, 13, 30) + at(s2, 13, 30);
      expect(inside, greaterThan(0.05), reason: k.name);
      expect(outside, greaterThan(0.05), reason: k.name);
    }
  });

  test('depth, altitude and gloss contour change the shading', () {
    double edge(BevelParams p) =>
        at(BevelCache.shade(square(), w, h, 1, p).$1, 17, 30);
    final base = edge(const BevelParams(size: 6));
    expect(edge(const BevelParams(size: 6, depth: 3)), greaterThan(base));
    expect(
      edge(const BevelParams(size: 6, gloss: ContourPreset.cone)),
      isNot(closeTo(base, 1e-3)),
    );
    // Light straight above: no highlight or shadow on a symmetric bevel
    // is impossible to tell apart — both sides get the same amount.
    final (hl, _) = BevelCache.shade(
      square(),
      w,
      h,
      1,
      const BevelParams(size: 6, altitude: 90),
    );
    expect(at(hl, 17, 30), closeTo(at(hl, 42, 30), 1e-3));
  });

  test('contour and texture reshape the surface', () {
    final plain = BevelCache.shade(
      square(),
      w,
      h,
      1,
      const BevelParams(size: 10),
    ).$1;
    final ring = BevelCache.shade(
      square(),
      w,
      h,
      1,
      const BevelParams(size: 10, contour: ContourPreset.ring, contourRange: 1),
    ).$1;
    var diff = 0.0;
    for (var i = 0; i < plain.length; i++) {
      diff += (plain[i] - ring[i]).abs();
    }
    expect(diff, greaterThan(1));
    // A striped texture lights the flat middle too.
    final tex = Float32List(w * h);
    for (var i = 0; i < tex.length; i++) {
      tex[i] = (i ~/ w) % 8 < 4 ? 1 : 0;
    }
    final (hl, sh) = BevelCache.shade(
      square(),
      w,
      h,
      1,
      const BevelParams(size: 4, texture: 'stripes', textureDepth: 2),
      texture: tex,
    );
    // Stripe edges in the flat middle catch the light.
    var middle = 0.0;
    for (var y = 22; y < 38; y++) {
      middle += at(hl, 30, y) + at(sh, 30, y);
    }
    expect(middle, greaterThan(0.1));
  });

  test('contour presets stay within 0..1 and fix the ends', () {
    for (final c in ContourPreset.values) {
      for (var i = 0; i <= 20; i++) {
        final v = c.apply(i / 20);
        expect(v, inInclusiveRange(0, 1), reason: c.name);
      }
    }
    expect(ContourPreset.linear.apply(0.3), 0.3);
    expect(ContourPreset.cone.apply(0.5), 1);
  });

  test('older bevels map to Photoshop settings', () {
    final old = LayerEffect(
      type: 'bevel',
      params: const {'style': 2, 'depth': 6, 'size': 6, 'angle': 225},
    );
    final p = BevelParams.of(old);
    expect(p.kind, BevelKind.emboss);
    expect(p.size, 12);
    expect(p.angle, 135);
    final fresh = BevelParams.of(EffectRegistry.instance['bevel']!.create());
    expect(fresh.size, 5);
    expect(fresh.angle, 120);
    expect(fresh.altitude, 30);
    expect(fresh.highlightOpacity, 0.75);
  });

  test('exported images include the bevel', () async {
    final doc = PixDocument(
      name: 't',
      width: 100,
      height: 100,
      layers: [
        ShapeLayer(
          LayerProps(
            name: 's',
            transform: const LayerTransform(x: 50, y: 50),
            effects: [
              EffectRegistry.instance['bevel']!.create({
                'size': 10,
                'technique': 1,
                'highlightOpacity': 1,
                'shadowOpacity': 1,
              }),
            ],
          ),
          shape: ShapeKind.rectangle,
          width: 60,
          height: 60,
          fill: PixFill.color(const Color(0xFF808080)),
        ),
      ],
    );
    final img = await DocumentRenderer(AssetStore()).renderImage(doc);
    final ByteData data = (await img.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    ))!;
    int red(int x, int y) => data.getUint8((y * 100 + x) * 4);
    // Left inner edge lighter than the grey middle, right edge darker.
    expect(red(23, 50), greaterThan(red(50, 50) + 20));
    expect(red(77, 50), lessThan(red(50, 50) - 20));
  });
}

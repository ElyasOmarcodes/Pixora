import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixora/document/assets/asset_store.dart';
import 'package:pixora/document/effects/effect_registry.dart';
import 'package:pixora/document/model/document.dart';
import 'package:pixora/document/model/fill.dart';
import 'package:pixora/document/model/layer.dart';
import 'package:pixora/document/model/layer_transform.dart';
import 'package:pixora/document/render/blend_shader.dart';
import 'package:pixora/document/render/document_renderer.dart';

/// A black square with a white half, 100×100 on a 100×100 canvas.
Future<(Color Function(int, int), int)> render(
  String type, [
  Map<String, Object> p = const {},
  int size = 100,
  bool smooth = false,
]) async {
  final doc = PixDocument(
    name: 't',
    width: size.toDouble(),
    height: size.toDouble(),
    layers: [
      ShapeLayer(
        LayerProps(
          name: 's',
          transform: LayerTransform(x: size / 2, y: size / 2),
          effects: [
            if (type != 'none') EffectRegistry.instance[type]!.create(p),
          ],
        ),
        shape: ShapeKind.rectangle,
        width: size.toDouble(),
        height: size.toDouble(),
        fill: smooth
            ? PixFill.gradient(FillKind.linear, const [
                Color(0xFF000000),
                Color(0xFFFFFFFF),
              ], angle: 0)
            : PixFill.gradient(
                FillKind.linear,
                const [Color(0xFF000000), Color(0xFF000000), Color(0xFFFFFFFF)],
                stops: const [0, 0.5, 0.5],
                angle: 0,
              ),
      ),
    ],
  );
  final sw = Stopwatch()..start();
  final img = await DocumentRenderer(AssetStore()).renderImage(doc);
  final ms = sw.elapsedMilliseconds;
  final data = (await img.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  ))!;
  return (
    (int x, int y) {
      final i = (y * size + x) * 4;
      return Color.fromARGB(
        data.getUint8(i + 3),
        data.getUint8(i),
        data.getUint8(i + 1),
        data.getUint8(i + 2),
      );
    },
    ms,
  );
}

double lum(Color c) => (c.r + c.g + c.b) / 3;

void main() {
  setUpAll(BlendShader.load);

  test('unsharp mask raises contrast at the edge', () async {
    final (px, _) = await render('unsharpMask', {'amount': 300, 'radius': 3});
    // Just inside the white side it overshoots to white, the black side
    // stays black (clamped), far away nothing changes.
    expect(lum(px(52, 50)), greaterThan(0.95));
    expect(lum(px(47, 50)), lessThan(0.05));
    expect(lum(px(80, 50)), closeTo(1, 0.02));
  });

  test('high pass is grey away from edges', () async {
    final (px, _) = await render('highPass', {'radius': 4});
    expect(lum(px(15, 50)), closeTo(0.5, 0.03));
    expect(lum(px(85, 50)), closeTo(0.5, 0.03));
    expect(lum(px(52, 50)), greaterThan(0.6));
    expect(lum(px(47, 50)), lessThan(0.4));
  });

  test('emboss lights one side of the edge', () async {
    final (px, _) = await render('emboss', {
      'angle': 0,
      'height': 3,
      'amount': 100,
    });
    expect(lum(px(15, 50)), closeTo(0.5, 0.03));
    expect((lum(px(50, 50)) - 0.5).abs(), greaterThan(0.2));
  });

  test('mosaic makes flat cells', () async {
    final (px, _) = await render('mosaic', {'cell': 10});
    expect(px(61, 51), px(68, 58));
  });

  test('maximum grows light areas, minimum dark ones', () async {
    final (mx, _) = await render('maximum', {'radius': 5});
    final (mn, _) = await render('minimum', {'radius': 5});
    expect(lum(mx(47, 50)), greaterThan(0.9)); // white spread left
    expect(lum(mn(53, 50)), lessThan(0.1)); // black spread right
  });

  test('offset wraps the pixels around', () async {
    final (px, _) = await render('offset', {'dx': 50, 'dy': 0});
    expect(lum(px(20, 50)), greaterThan(0.9)); // white came round
    expect(lum(px(80, 50)), lessThan(0.1));
  });

  test('distortions move pixels', () async {
    final (base, _) = await render('none', const {}, 100, true);
    for (final (t, p) in [
      ('twirl', {'angle': 180}),
      ('pinch', {'amount': 80}),
      ('spherize', {'amount': 100}),
      ('ripple', {'amount': 60, 'size': 20}),
    ]) {
      final (px, _) = await render(t, p, 100, true);
      var changed = 0;
      for (var y = 5; y < 95; y += 3) {
        for (var x = 5; x < 95; x += 3) {
          if ((lum(px(x, y)) - lum(base(x, y))).abs() > 0.04) changed++;
        }
      }
      expect(changed, greaterThan(40), reason: t);
    }
  });

  test('filters stay fast on a 1000 px layer', () async {
    for (final (t, p) in [
      ('unsharpMask', {'amount': 150, 'radius': 4}),
      ('highPass', {'radius': 8}),
      ('emboss', <String, Object>{}),
      ('mosaic', {'cell': 20}),
      ('maximum', {'radius': 6}),
      ('twirl', {'angle': 120}),
      ('ripple', {'amount': 20, 'size': 10}),
    ]) {
      await render(t, p, 1000); // warm up
      final (_, ms) = await render(t, p, 1000);
      // ignore: avoid_print
      print('$t: $ms ms');
      expect(ms, lessThan(1500), reason: t);
    }
  });
}

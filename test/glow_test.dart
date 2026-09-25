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
import 'package:pixora/document/render/document_renderer.dart';
import 'package:pixora/document/render/glow_engine.dart';

/// A black 40×40 square centred on a 100×100 canvas (spans 30..70).
Future<Color Function(int, int)> render(List<LayerEffect> effects) async {
  final doc = PixDocument(
    name: 't',
    width: 100,
    height: 100,
    layers: [
      ShapeLayer(
        LayerProps(
          name: 's',
          effects: effects,
          transform: const LayerTransform(x: 50, y: 50),
        ),
        shape: ShapeKind.rectangle,
        width: 40,
        height: 40,
        fill: PixFill.color(const Color(0xFF000000)),
      ),
    ],
  );
  final img = await DocumentRenderer(AssetStore()).renderImage(doc);
  final ByteData data = (await img.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  ))!;
  return (int x, int y) {
    final i = (y * 100 + x) * 4;
    return Color.fromARGB(
      data.getUint8(i + 3),
      data.getUint8(i),
      data.getUint8(i + 1),
      data.getUint8(i + 2),
    );
  };
}

LayerEffect glow([Map<String, Object> p = const {}, bool inner = false]) =>
    EffectRegistry.instance[inner ? 'innerGlow' : 'glow']!.create({
      'opacity': 1,
      'color': 0xFFFFFFFF,
      'blend': 0,
      ...p,
    });

void main() {
  test('Photoshop defaults: screen, 75%, light yellow, 5 px, range 50', () {
    final p = GlowParams.of(EffectRegistry.instance['glow']!.create());
    expect(p.blend.name, 'screen');
    expect(p.opacity, 0.75);
    expect(p.size, 5);
    expect(p.range, 0.5);
    expect(p.fast, isTrue);
  });

  test('older glows keep their look', () {
    final p = GlowParams.of(
      LayerEffect(type: 'glow', params: {'blur': 10, 'opacity': 0.5}),
    );
    expect(p.blend.name, 'normal');
    expect(p.size, 15);
    expect(p.range, 1);
  });

  test('outer glow fades over its size; range tightens the ramp', () async {
    final soft = await render([
      glow({'size': 12, 'range': 100}),
    ]);
    final tight = await render([
      glow({'size': 12, 'range': 50}),
    ]);
    expect(soft(28, 50).a, greaterThan(0.2));
    expect(soft(20, 50).a, lessThan(soft(28, 50).a));
    expect(soft(14, 50).a, lessThan(0.05));
    // Range 50%: alpha doubled (clamped), so stronger at the same spot.
    expect(tight(26, 50).a, greaterThan(soft(26, 50).a + 0.1));
  });

  test('precise glow: linear falloff with the exact distance', () async {
    final px = await render([
      glow({'size': 20, 'range': 100, 'technique': 1}),
    ]);
    expect(px(20, 50).a, closeTo(0.5, 0.1)); // 10 px of 20
    expect(px(25, 50).a, closeTo(0.75, 0.1));
    // Round corners: diagonal distance.
    expect(px(23, 23).a, closeTo(1 - 9.9 / 20, 0.12));
  });

  test('spread makes a solid band up to spread × size', () async {
    final px = await render([
      glow({'size': 20, 'spread': 50, 'range': 100}),
    ]);
    expect(px(25, 50).a, greaterThan(0.9)); // 5 px out, inside the spread
    expect(px(12, 50).a, lessThan(0.3));
  });

  test('inner glow: from the edge, or from the centre', () async {
    final edge = await render([
      glow({'size': 10, 'range': 100}, true),
    ]);
    expect(edge(31, 50).r, greaterThan(0.25));
    expect(edge(50, 50).r, lessThan(0.05));
    expect(edge(20, 50).a, 0);
    final centre = await render([
      glow({'size': 10, 'range': 100, 'source': 1}, true),
    ]);
    expect(centre(50, 50).r, greaterThan(0.9));
    expect(centre(31, 50).r, lessThan(0.8));
    final precise = await render([
      glow({'size': 10, 'range': 100, 'technique': 1}, true),
    ]);
    expect(precise(31, 50).r, greaterThan(0.75));
    expect(precise(36, 50).r, closeTo(0.4, 0.12));
    expect(precise(50, 50).r, lessThan(0.05));
  });

  test('contour and noise run in the glow engine', () async {
    final linear = await render([
      glow({'size': 16, 'range': 100}),
    ]);
    final ring = await render([
      glow({'size': 16, 'range': 100, 'contour': 5}), // Ring
    ]);
    // Ring contour peaks where the glow is half strength (at the edge).
    expect(ring(29, 50).a, greaterThan(linear(29, 50).a + 0.2));
    expect(ring(18, 50).a, lessThan(0.2));
    final noisy = await render([
      glow({'size': 16, 'range': 100, 'noise': 100}),
    ]);
    final values = {
      for (var x = 16; x < 29; x++) (noisy(x, 40).a * 255).round(),
    };
    expect(values.contains(0) || values.contains(255), isTrue);
  });

  test('drop shadow spread and inner shadow choke', () async {
    final plain = await render([
      EffectRegistry.instance['shadow']!.create({
        'dx': 0,
        'dy': 0,
        'blur': 12,
        'opacity': 1,
        'color': 0xFFFF0000,
      }),
    ]);
    final spread = await render([
      EffectRegistry.instance['shadow']!.create({
        'dx': 0,
        'dy': 0,
        'blur': 12,
        'opacity': 1,
        'color': 0xFFFF0000,
        'spread': 60,
      }),
    ]);
    // Spread: the shadow stays solid further out.
    expect(spread(24, 50).a, greaterThan(plain(24, 50).a + 0.2));
    expect(spread(24, 50).r, greaterThan(0.9));

    final choke = await render([
      EffectRegistry.instance['innerShadow']!.create({
        'distance': 0,
        'blur': 12,
        'opacity': 1,
        'color': 0xFFFFFFFF,
        'spread': 60,
        'blend': 0,
      }),
    ]);
    expect(choke(34, 50).r, greaterThan(0.9));
    expect(choke(50, 50).r, lessThan(0.1));
    expect(choke(20, 50).a, 0);
  });
}

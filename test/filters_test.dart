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
import 'package:pixora/document/model/mask.dart';
import 'package:pixora/document/render/document_renderer.dart';

const grey = Color(0xFF808080);

/// A grey 40×40 square centred on a 100×100 canvas (spans 30..70).
Future<Color Function(int, int)> render(
  List<LayerEffect> effects, {
  List<MaskStroke> mask = const [],
  bool maskHidesEffects = false,
}) async {
  final doc = PixDocument(
    name: 't',
    width: 100,
    height: 100,
    layers: [
      ShapeLayer(
        LayerProps(
          name: 's',
          effects: effects,
          mask: mask,
          maskHidesEffects: maskHidesEffects,
          transform: const LayerTransform(x: 50, y: 50),
        ),
        shape: ShapeKind.rectangle,
        width: 40,
        height: 40,
        fill: PixFill.color(grey),
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

LayerEffect fx(String type, [Map<String, Object> p = const {}]) =>
    EffectRegistry.instance[type]!.create(p);

void main() {
  test('gaussian blur softens the edge both ways', () async {
    final px = await render([
      fx('gaussianBlur', {'radius': 4}),
    ]);
    expect(px(50, 50).a, closeTo(1, 0.02));
    expect(px(30, 50).a, closeTo(0.5, 0.15));
    expect(px(25, 50).a, greaterThan(0.02));
    expect(px(25, 50).a, lessThan(0.3));
  });

  test('motion blur spreads along its angle only', () async {
    final px = await render([
      fx('motionBlur', {'angle': 0, 'distance': 20}),
    ]);
    // Horizontal: a linear ramp over 20 px around the left edge.
    expect(px(30, 50).a, closeTo(0.5, 0.1));
    expect(px(25, 50).a, closeTo(0.25, 0.1));
    expect(px(35, 50).a, closeTo(0.75, 0.1));
    expect(px(50, 50).a, closeTo(1, 0.02));
    // Vertical edges stay sharp.
    expect(px(50, 28).a, lessThan(0.05));
    expect(px(50, 32).a, greaterThan(0.95));
  });

  test('box blur is a linear ramp', () async {
    final px = await render([
      fx('boxBlur', {'radius': 5}),
    ]);
    expect(px(30, 50).a, closeTo(0.5, 0.1));
    expect(px(27, 50).a, closeTo(0.23, 0.1));
    expect(px(50, 50).a, closeTo(1, 0.02));
  });

  test('add noise changes colours, keeps alpha', () async {
    final px = await render([
      fx('addNoise', {'amount': 50, 'mono': 1}),
    ]);
    final values = <int>{};
    for (var x = 32; x < 68; x++) {
      final c = px(x, 50);
      expect(c.a, 1);
      expect((c.r - c.g).abs(), lessThan(0.01)); // monochromatic
      values.add((c.r * 255).round());
    }
    expect(values.length, greaterThan(10));
    // Mean stays near the original grey (noise is signed).
    var sum = 0.0, n = 0;
    for (var y = 32; y < 68; y++) {
      for (var x = 32; x < 68; x++) {
        sum += px(x, y).r;
        n++;
      }
    }
    expect(sum / n, closeTo(0x80 / 255, 0.04));
    expect(px(20, 50).a, 0);
  });

  test('salt & pepper adds white and black specks', () async {
    final px = await render([
      fx('saltPepper', {'density': 30}),
    ]);
    var white = 0, black = 0;
    for (var y = 32; y < 68; y++) {
      for (var x = 32; x < 68; x++) {
        final c = px(x, y);
        if (c.r > 0.95) white++;
        if (c.r < 0.05) black++;
      }
    }
    expect(white, greaterThan(50));
    expect(black, greaterThan(50));
    expect(px(20, 50).a, 0);
  });

  test('filters run before the mask; styles follow the masked shape', () async {
    // Mask hides the right half.
    final mask = [
      MaskStroke(
        mode: MaskMode.hide,
        shape: MaskShape.area,
        points: const [
          Offset(0, -100),
          Offset(100, -100),
          Offset(100, 100),
          Offset(0, 100),
        ],
      ),
    ];
    final px = await render([
      fx('gaussianBlur', {'radius': 4}),
    ], mask: mask);
    // Masked edge is sharp: the blur happened before the mask.
    expect(px(48, 50).a, greaterThan(0.9));
    expect(px(52, 50).a, lessThan(0.05));

    final glow = await render([
      fx('shadow', {'dx': 10, 'dy': 0, 'blur': 0, 'opacity': 1}),
    ], mask: mask);
    // Shadow of the masked shape ends at x = 60.
    expect(glow(58, 50).a, greaterThan(0.9));
    expect(glow(62, 50).a, lessThan(0.05));

    final hidden = await render(
      [
        fx('shadow', {'dx': -10, 'dy': 0, 'blur': 0, 'opacity': 1}),
      ],
      mask: mask,
      maskHidesEffects: true,
    );
    // Layer Mask Hides Effects: the shadow of the whole square, then
    // masked — nothing right of x = 50.
    expect(hidden(45, 50).a, greaterThan(0.9));
    expect(hidden(55, 50).a, lessThan(0.05));
  });

  test('satin darkens inside the shape only', () async {
    final px = await render([
      fx('satin', {'invert': 0, 'opacity': 1, 'distance': 20, 'size': 0}),
    ]);
    // Near the edges the offset copies differ → satin colour (black).
    expect(px(33, 50).r, lessThan(0.3));
    // Middle: both copies cover → no satin (not inverted).
    expect(px(50, 50).r, closeTo(0x80 / 255, 0.03));
    expect(px(25, 50).a, 0);
  });

  test('radial, tilt-shift and grain render', () async {
    final spin = await render([
      fx('radialBlur', {'amount': 40}),
    ]);
    // Corners of the square blur along circles around the centre.
    expect(spin(31, 31).a, lessThan(0.9));
    expect(spin(50, 50).a, closeTo(1, 0.02));
    final zoom = await render([
      fx('radialBlur', {'amount': 40, 'method': 1}),
    ]);
    expect(zoom(28, 50).a, greaterThan(0.02));
    expect(zoom(50, 50).a, closeTo(1, 0.02));
    final tilt = await render([
      fx('tiltShift', {'blur': 6, 'focus': 0.1, 'transition': 0.05}),
    ]);
    // Sharp in the middle band, blurred at the top edge.
    expect(tilt(30, 50).a, greaterThan(0.95));
    expect(tilt(50, 29).a, greaterThan(0.1));
    final grain = await render([
      fx('filmGrain', {'amount': 60}),
    ]);
    final values = {
      for (var x = 32; x < 68; x++) (grain(x, 50).r * 255).round(),
    };
    expect(values.length, greaterThan(5));
  });

  test(
    'filter blending options: opacity mixes with the unfiltered pixels',
    () async {
      final half = await render([
        fx('gaussianBlur', {'radius': 4, 'opacity': 0.5}),
      ]);
      // Half sharp edge, half blurred: in between.
      expect(half(28, 50).a, greaterThan(0.02));
      expect(half(28, 50).a, lessThan(0.3));
      expect(half(31, 50).a, greaterThan(0.6));
    },
  );
}

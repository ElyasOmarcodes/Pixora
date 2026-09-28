import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixora/document/assets/asset_store.dart';
import 'package:pixora/document/model/blend.dart';
import 'package:pixora/document/model/document.dart';
import 'package:pixora/document/model/fill.dart';
import 'package:pixora/document/model/layer.dart';
import 'package:pixora/document/model/layer_transform.dart';
import 'package:pixora/document/render/blend_shader.dart';
import 'package:pixora/document/render/document_renderer.dart';

/// Renders [top] (mode [m]) over [bottom] and returns the centre pixel.
Future<Color> blendPixel(Color bottom, Color top, PixBlendMode m) async {
  ShapeLayer rect(Color c, {PixBlendMode mode = PixBlendMode.normal}) =>
      ShapeLayer(
        LayerProps(
          name: 'r',
          blendMode: mode,
          transform: const LayerTransform(x: 20, y: 20),
        ),
        shape: ShapeKind.rectangle,
        width: 40,
        height: 40,
        fill: PixFill.color(c),
      );
  final doc = PixDocument(
    name: 't',
    width: 40,
    height: 40,
    layers: [
      rect(bottom),
      rect(top, mode: m),
    ],
  );
  final img = await DocumentRenderer(AssetStore()).renderImage(doc);
  final data = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  const i = (20 * 40 + 20) * 4;
  return Color.fromARGB(
    data.getUint8(i + 3),
    data.getUint8(i),
    data.getUint8(i + 1),
    data.getUint8(i + 2),
  );
}

Color grey(double v) => Color.fromARGB(
  255,
  (v * 255).round(),
  (v * 255).round(),
  (v * 255).round(),
);

void main() {
  setUpAll(BlendShader.load);

  test('shader is available', () {
    expect(BlendShader.program, isNotNull);
  });

  test('Photoshop formulas', () async {
    Future<double> r(double b, double s, PixBlendMode m) async =>
        (await blendPixel(grey(b), grey(s), m)).r;
    expect(await r(0.5, 0.6, PixBlendMode.linearBurn), closeTo(0.1, 0.02));
    expect(await r(0.5, 0.3, PixBlendMode.subtract), closeTo(0.2, 0.02));
    expect(await r(0.4, 0.8, PixBlendMode.divide), closeTo(0.5, 0.02));
    expect(await r(0.3, 0.7, PixBlendMode.linearLight), closeTo(0.7, 0.02));
    expect(await r(0.6, 0.2, PixBlendMode.pinLight), closeTo(0.4, 0.02));
    expect(await r(0.6, 0.6, PixBlendMode.hardMix), closeTo(1, 0.02));
    expect(await r(0.3, 0.3, PixBlendMode.hardMix), closeTo(0, 0.02));
    // Vivid light, s > 0.5: colour dodge with 2(s−0.5).
    expect(await r(0.4, 0.75, PixBlendMode.vividLight), closeTo(0.8, 0.02));
    // Photoshop's Soft Light on a dark backdrop: b + (2s−1)(√b − b).
    const b = 0.1, s = 0.9;
    const ps = b + (2 * s - 1) * (0.31623 - b);
    expect(await r(b, s, PixBlendMode.softLight), closeTo(ps, 0.02));
  });

  test('GPU modes match Photoshop', () async {
    Future<double> r(double b, double s, PixBlendMode m) async =>
        (await blendPixel(grey(b), grey(s), m)).r;
    expect(await r(0.5, 0.6, PixBlendMode.multiply), closeTo(0.3, 0.02));
    expect(await r(0.5, 0.6, PixBlendMode.screen), closeTo(0.8, 0.02));
    expect(await r(0.3, 0.6, PixBlendMode.overlay), closeTo(0.36, 0.02));
    expect(await r(0.3, 0.6, PixBlendMode.colorDodge), closeTo(0.75, 0.02));
    expect(await r(0.7, 0.6, PixBlendMode.colorBurn), closeTo(0.5, 0.02));
    expect(await r(0.3, 0.6, PixBlendMode.hardLight), closeTo(0.44, 0.02));
    expect(await r(0.3, 0.6, PixBlendMode.exclusion), closeTo(0.54, 0.02));
    expect(await r(0.3, 0.6, PixBlendMode.difference), closeTo(0.3, 0.02));
    expect(await r(0.3, 0.6, PixBlendMode.linearDodge), closeTo(0.9, 0.02));
  });

  test('dissolve scatters whole pixels', () async {
    final doc = PixDocument(
      name: 't',
      width: 40,
      height: 40,
      background: PixFill.white,
      layers: [
        ShapeLayer(
          LayerProps(
            name: 'r',
            opacity: 0.5,
            blendMode: PixBlendMode.dissolve,
            transform: const LayerTransform(x: 20, y: 20),
          ),
          shape: ShapeKind.rectangle,
          width: 40,
          height: 40,
          fill: PixFill.color(const Color(0xFFFF0000)),
        ),
      ],
    );
    final img = await DocumentRenderer(AssetStore()).renderImage(doc);
    final data = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    var red = 0, white = 0;
    for (var i = 0; i < 40 * 40; i++) {
      final g = data.getUint8(i * 4 + 1);
      if (g < 10) red++;
      if (g > 245) white++;
    }
    expect(red + white, greaterThan(1500)); // no pink mixes
    expect(red, inInclusiveRange(500, 1100));
  });

  test('darker / lighter colour pick a whole colour', () async {
    const a = Color(0xFF2040C0), c = Color(0xFFC0A020);
    final d = await blendPixel(a, c, PixBlendMode.darkerColor);
    final l = await blendPixel(a, c, PixBlendMode.lighterColor);
    expect(d.toARGB32(), a.toARGB32());
    expect(l.toARGB32(), c.toARGB32());
  });
}

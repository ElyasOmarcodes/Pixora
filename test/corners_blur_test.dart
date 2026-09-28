import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixora/document/assets/asset_store.dart';
import 'package:pixora/document/effects/effect_registry.dart';
import 'package:pixora/document/model/document.dart';
import 'package:pixora/document/model/fill.dart';
import 'package:pixora/document/model/layer.dart';
import 'package:pixora/document/model/layer_transform.dart';
import 'package:pixora/document/render/document_renderer.dart';
import 'package:pixora/document/render/shape_paths.dart';

ShapeLayer shape(ShapeKind k, {double r = 0, Map<String, double>? p}) =>
    ShapeLayer(
      LayerProps(name: 's'),
      shape: k,
      width: 100,
      height: 100,
      cornerRadius: r,
      params: p ?? const {},
      fill: PixFill.color(const Color(0xFF000000)),
    );

void main() {
  test('rectangle corners can each have their own radius', () {
    final s = shape(
      ShapeKind.rectangle,
      r: 30,
      p: {'cornerLink': 0, 'c0': 0},
    );
    final path = buildShapePath(s);
    // Top-left stays sharp, bottom-right is rounded.
    expect(path.contains(const Offset(-49, -49)), isTrue);
    expect(path.contains(const Offset(49, 49)), isFalse);
  });

  test('every cornered shape takes a corner radius', () {
    for (final k in [
      ShapeKind.triangle,
      ShapeKind.star,
      ShapeKind.polygon,
      ShapeKind.diamond,
      ShapeKind.parallelogram,
      ShapeKind.trapezoid,
      ShapeKind.cross,
      ShapeKind.blockArrow,
      ShapeKind.chevron,
    ]) {
      final sharp = shape(k);
      final corners = shapeCorners(sharp)!;
      final tip = corners.first;
      final mid = (corners[1] + corners.last) / 2;
      final round = shape(k, r: 12);
      // A rounded corner no longer reaches the sharp tip.
      final inward = tip + (mid - tip) / (mid - tip).distance * 0.8;
      expect(buildShapePath(sharp).contains(inward), isTrue, reason: '$k');
      expect(buildShapePath(round).contains(inward), isFalse, reason: '$k');
    }
  });

  test('diamond, square, elliptical and conic gradients render', () async {
    for (final kind in [
      FillKind.diamond,
      FillKind.square,
      FillKind.elliptical,
      FillKind.conic,
    ]) {
      final doc = PixDocument(
        name: 't',
        width: 100,
        height: 100,
        layers: [
          ShapeLayer(
            LayerProps(
              name: 's',
              transform: const LayerTransform(x: 50, y: 50),
            ),
            shape: ShapeKind.rectangle,
            width: 100,
            height: 100,
            fill: PixFill.gradient(kind, const [
              Color(0xFFFF0000),
              Color(0xFF0000FF),
            ], angle: 0),
          ),
        ],
      );
      final img = await DocumentRenderer(AssetStore()).renderImage(doc);
      final data = (await img.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      ))!;
      int red(int x, int y) => data.getUint8((y * 100 + x) * 4);
      int blue(int x, int y) => data.getUint8((y * 100 + x) * 4 + 2);
      if (kind == FillKind.conic) {
        // Red along the start angle, blue half a turn away.
        expect(red(95, 50), greaterThan(200), reason: '$kind');
        expect(blue(5, 50), greaterThan(200), reason: '$kind');
      } else {
        expect(red(50, 50), greaterThan(200), reason: '$kind centre');
        expect(blue(1, 1), greaterThan(150), reason: '$kind corner');
      }
    }
  });

  test('a blurred photo keeps solid edges (Photoshop)', () async {
    final rec = ui.PictureRecorder();
    Canvas(rec).drawColor(const Color(0xFF808080), BlendMode.src);
    final photo = await rec.endRecording().toImage(100, 100);
    final png = await photo.toByteData(format: ui.ImageByteFormat.png);
    final store = AssetStore();
    final id = store.add(png!.buffer.asUint8List());
    await store.decode(id);
    final doc = PixDocument(
      name: 't',
      width: 100,
      height: 100,
      layers: [
        RasterLayer(
          LayerProps(
            name: 'photo',
            transform: const LayerTransform(x: 50, y: 50),
            effects: [
              EffectRegistry.instance['gaussianBlur']!.create({'radius': 8}),
            ],
          ),
          assetId: id,
          width: 100,
          height: 100,
        ),
      ],
    );
    final img = await DocumentRenderer(store).renderImage(doc);
    final data = (await img.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    ))!;
    int alpha(int x, int y) => data.getUint8((y * 100 + x) * 4 + 3);
    expect(alpha(0, 50), 255);
    expect(alpha(50, 0), 255);
    expect(alpha(99, 99), 255);
  });
}

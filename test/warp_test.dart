import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixora/document/assets/asset_store.dart';
import 'package:pixora/document/model/document.dart';
import 'package:pixora/document/model/fill.dart';
import 'package:pixora/document/model/layer.dart';
import 'package:pixora/document/model/layer_transform.dart';
import 'package:pixora/document/model/warp.dart';
import 'package:pixora/document/render/document_renderer.dart';
import 'package:pixora/editor/tools/warp_tool.dart';

List<Offset> grid() => [
  for (var i = 0; i < 4; i++)
    for (var j = 0; j < 4; j++) Offset(j / 3, i / 3),
];

Future<int Function(int, int)> alphaOf(Layer layer) async {
  final doc = PixDocument(name: 't', width: 100, height: 100, layers: [layer]);
  final img = await DocumentRenderer(AssetStore()).renderImage(doc);
  final data = (await img.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  ))!;
  return (int x, int y) => data.getUint8((y * 100 + x) * 4 + 3);
}

ShapeLayer square() => ShapeLayer(
  LayerProps(name: 's', transform: const LayerTransform(x: 50, y: 50)),
  shape: ShapeKind.rectangle,
  width: 60,
  height: 60,
  fill: PixFill.color(const Color(0xFF000000)),
);

void main() {
  test('homography maps the unit square onto the corners', () {
    final g = WarpGeometry(const [
      Offset(0.1, 0),
      Offset(0.9, 0.2),
      Offset(1, 1),
      Offset(0, 0.8),
    ], grid());
    expect(g.map(0, 0).dx, closeTo(0.1, 1e-9));
    expect(g.map(1, 0).dy, closeTo(0.2, 1e-9));
    expect(g.map(1, 1).dx, closeTo(1, 1e-9));
    expect(g.map(0, 1).dy, closeTo(0.8, 1e-9));
    final p = g.project(const Offset(0.3, 0.6));
    final back = g.unproject(p);
    expect(back.dx, closeTo(0.3, 1e-9));
    expect(back.dy, closeTo(0.6, 1e-9));
  });

  test('distort moves the layer pixels with the corners', () async {
    final before = await alphaOf(square());
    expect(before(22, 22), 255);
    // Pull the top-left corner in towards the middle.
    final g = WarpGeometry(const [
      Offset(0.35, 0.35),
      Offset(1, 0),
      Offset(1, 1),
      Offset(0, 1),
    ], grid());
    final after = await alphaOf(withWarp(square(), g, WarpMode.distort));
    expect(after(22, 22), lessThan(10)); // the corner moved away
    expect(after(76, 76), 255); // the far corner stayed
  });

  test('a mesh warp bends the layer outline', () async {
    final mesh = grid();
    // Push the top edge's inner points up, out of the box.
    mesh[1] = mesh[1] + const Offset(0, -0.5);
    mesh[2] = mesh[2] + const Offset(0, -0.5);
    final g = WarpGeometry([...WarpGeometry.baseCorners], mesh);
    final a = await alphaOf(withWarp(square(), g, WarpMode.warp));
    expect(a(50, 14), greaterThan(200)); // above the old top edge (20)
  });
}

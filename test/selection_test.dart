import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixora/document/model/document.dart';
import 'package:pixora/document/model/layer.dart';
import 'package:pixora/document/model/mask.dart';
import 'package:pixora/editor/editor_controller.dart';
import 'package:pixora/editor/selection/pixel_selection.dart';
import 'package:pixora/editor/selection/selection_controller.dart';

/// A 10×10 selection (scale 1) with the given cells set.
PixelSelection sel(bool Function(int x, int y) f) {
  final d = Uint8List(100);
  for (var y = 0; y < 10; y++) {
    for (var x = 0; x < 10; x++) {
      if (f(x, y)) d[y * 10 + x] = 255;
    }
  }
  return PixelSelection(10, 10, 1, d);
}

/// Left half red, right half blue, one blue speck inside the red half.
Uint8List twoColours() {
  final px = Uint8List(400);
  for (var y = 0; y < 10; y++) {
    for (var x = 0; x < 10; x++) {
      final i = (y * 10 + x) * 4;
      final blue = x >= 5 || (x == 1 && y == 1);
      px[i] = blue ? 0 : 250;
      px[i + 1] = 0;
      px[i + 2] = blue ? 240 : 10;
      px[i + 3] = 255;
    }
  }
  return px;
}

int count(PixelSelection s) => s.data.where((v) => v >= 128).length;

void main() {
  test('empty grid scales big canvases down', () {
    final s = PixelSelection.empty(4000, 2000);
    expect(s.width, PixelSelection.maxSide);
    expect(s.height, 800);
    expect(s.isEmpty, isTrue);
    expect(PixelSelection.empty(800, 600).scale, 1);
  });

  test('new / add / subtract / intersect', () {
    final a = sel((x, y) => x < 6);
    final b = sel((x, y) => x >= 4);
    expect(count(a.combine(b, SelectionMode.replace)), 60);
    expect(count(a.combine(b, SelectionMode.add)), 100);
    expect(count(a.combine(b, SelectionMode.subtract)), 40);
    expect(count(a.combine(b, SelectionMode.intersect)), 20);
    expect(count(a.inverted()), 40);
    expect(count(a.all()), 100);
  });

  test('bounds of the selected cells', () {
    final s = sel((x, y) => x >= 2 && x < 5 && y >= 3 && y < 9);
    expect(s.bounds, const Rect.fromLTRB(2, 3, 5, 9));
    expect(sel((x, y) => false).bounds, isNull);
  });

  test('magic wand: contiguous vs global', () {
    final px = twoColours();
    final base = PixelSelection(10, 10, 1, Uint8List(100));
    final near = base.magicWand(px, const Offset(7.5, 5.5));
    expect(count(near), 50); // the right half only
    final all = base.magicWand(px, const Offset(7.5, 5.5), contiguous: false);
    expect(count(all), 51); // plus the speck
    final red = base.magicWand(px, const Offset(0.5, 0.5));
    expect(count(red), 49);
    expect(red.coverageAt(const Offset(1.5, 1.5)), 0);
  });

  test('colour range and luminance', () {
    final px = twoColours();
    final base = PixelSelection(10, 10, 1, Uint8List(100));
    expect(count(base.colorRange(px, const Color(0xFF0000F0))), 51);
    // Blue is darker than red.
    final dark = base.luminanceRange(px, from: 0, to: 0.1, softness: 0.01);
    expect(count(dark), 51);
  });

  test('expand, contract, feather and smooth', () {
    final dot = sel((x, y) => x == 5 && y == 5);
    expect(count(dot.expanded(1)), 9);
    expect(count(dot.expanded(2)), 25);
    final block = sel((x, y) => x >= 2 && x < 8 && y >= 2 && y < 8);
    expect(count(block.expanded(-1)), 16);
    final soft = block.feathered(2);
    expect(soft.data[5 * 10 + 5], greaterThan(200));
    expect(soft.data[2 * 10 + 2], inInclusiveRange(1, 254));
    expect(count(sel((x, y) => x == 5 && y == 5).smoothed(2)), 0);
  });

  test('outline follows the edge', () {
    final s = sel((x, y) => x >= 2 && x < 5 && y >= 3 && y < 9);
    final b = s.outline().getBounds();
    expect(b, const Rect.fromLTRB(2, 3, 5, 9));
  });

  test('controller combines with modes and has its own undo', () {
    final c = SelectionController();
    addTearDown(c.dispose);
    c.combine(sel((x, y) => x < 5));
    c.mode = SelectionMode.add;
    c.combine(sel((x, y) => y < 5));
    expect(count(c.current!), 75);
    c.mode = SelectionMode.subtract;
    c.combine(sel((x, y) => true));
    expect(c.hasSelection, isFalse);
    c.undo();
    expect(count(c.current!), 75);
    c.undo();
    expect(count(c.current!), 50);
    c.redo();
    expect(count(c.current!), 75);
    // Subtracting from nothing stays nothing.
    c.deselect();
    c.combine(sel((x, y) => true));
    expect(c.hasSelection, isFalse);
  });

  test('bitmap mask strokes round-trip through JSON', () {
    final s = MaskStroke(
      mode: MaskMode.hide,
      shape: MaskShape.image,
      points: const [Offset(-50, -40), Offset(50, 40)],
      assetId: 'as_mask',
    );
    final back = MaskStroke.fromJson(s.toJson());
    expect(back, s);
    expect(back.assetId, 'as_mask');
  });

  testWidgets('selection actions edit the document', (tester) async {
    final e = EditorController(
      document: PixDocument(name: 'T', width: 200, height: 100),
    );
    final shape = e.addShape(ShapeKind.rectangle);
    e.fitToCanvas([shape.id], cover: true);
    // Left half of the canvas.
    final left = PixelSelection.empty(200, 100);
    final half = PixelSelection(
      left.width,
      left.height,
      left.scale,
      Uint8List.fromList([
        for (var y = 0; y < left.height; y++)
          for (var x = 0; x < left.width; x++) x < left.width / 2 ? 255 : 0,
      ]),
    );

    final copy = await tester.runAsync(
      () => e.copySelectionToLayer(half, name: 'Sel'),
    );
    expect(copy, isNotNull);
    expect(e.document.layers.length, 2);
    expect(copy!.width, 100);
    expect(copy.height, 100);
    expect(copy.props.transform.x, 50);

    await tester.runAsync(() => e.maskFromSelection(shape.id, half));
    final masked = e.document.layerById(shape.id)!;
    expect(masked.props.mask.single.shape, MaskShape.image);
    expect(
      e.document.referencedAssets,
      contains(masked.props.mask.single.assetId),
    );

    await tester.runAsync(
      () => e.copySelectionToLayer(half, sourceId: shape.id, cut: true),
    );
    expect(e.document.layerById(shape.id)!.props.mask.length, 2);
    expect(e.document.layers.length, 3);

    expect(e.cropToSelection(half), isTrue);
    expect(e.document.width, 100);
    expect(e.document.height, 100);
    e.undo();
    expect(e.document.width, 200);
  });
}

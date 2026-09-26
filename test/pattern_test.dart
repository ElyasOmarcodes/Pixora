import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixora/core/patterns/pattern_library.dart';
import 'package:pixora/document/assets/asset_store.dart';
import 'package:pixora/document/model/document.dart';
import 'package:pixora/document/model/fill.dart';
import 'package:pixora/document/model/layer.dart';
import 'package:pixora/document/model/layer_transform.dart';
import 'package:pixora/document/model/patterns.dart';
import 'package:pixora/document/render/document_renderer.dart';
import 'package:pixora/editor/editor_controller.dart';
import 'package:pixora/ui/widgets/pattern_maker.dart';

Future<Color Function(int, int)> render(PixDocument doc, AssetStore a) async {
  final img = await DocumentRenderer(a).renderImage(doc);
  final w = img.width;
  final ByteData data = (await img.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  ))!;
  return (int x, int y) {
    final i = (y * w + x) * 4;
    return Color.fromARGB(
      data.getUint8(i + 3),
      data.getUint8(i),
      data.getUint8(i + 1),
      data.getUint8(i + 2),
    );
  };
}

PixDocument squareWith(PixFill fill) => PixDocument(
  name: 't',
  width: 96,
  height: 96,
  layers: [
    ShapeLayer(
      LayerProps(name: 's', transform: const LayerTransform(x: 48, y: 48)),
      shape: ShapeKind.rectangle,
      width: 96,
      height: 96,
      fill: fill,
    ),
  ],
);

Future<Uint8List> redBlueTile() async {
  final rec = ui.PictureRecorder();
  Canvas(rec)
    ..drawRect(const Rect.fromLTWH(0, 0, 8, 16), Paint()..color = Colors.red)
    ..drawRect(const Rect.fromLTWH(8, 0, 8, 16), Paint()..color = Colors.blue);
  final img = await rec.endRecording().toImage(16, 16);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

void main() {
  test('pattern fills round-trip through JSON', () {
    final f = PixFill.pattern(
      'honeycomb',
      fg: const Color(0xFFFF0000),
      bg: const Color(0xFFFFFFFF),
      angle: 30,
      scale: 2,
      center: const Offset(0.25, -0.5),
      mirror: true,
    );
    final back = PixFill.fromJson(f.toJson());
    expect(back, f);
    expect(back.isPattern, isTrue);
    expect(back.isGradient, isFalse);
    expect(back.hasShader, isTrue);
  });

  test('every built-in pattern draws a tile', () {
    for (final id in Patterns.builtins) {
      final t = Patterns.tile(id, fg: Colors.black, bg: Colors.white);
      expect(t, isNotNull, reason: id);
      expect(t!.width, Patterns.tileSize.toInt());
    }
    final m = Patterns.tile('dots', mirror: true)!;
    expect(m.width, Patterns.tileSize.toInt() * 2);
  });

  test('built-in pattern paints both colours', () async {
    // Checker at 1:1: 24px squares, black top-left, white next to it.
    final at = await render(
      squareWith(
        PixFill.pattern('checker', fg: Colors.black, bg: Colors.white),
      ),
      AssetStore(),
    );
    expect(at(10, 10), Colors.black);
    expect(at(34, 10), Colors.white);
    expect(at(34, 34), Colors.black);
  });

  test(
    'image pattern repeats and its asset is kept with the project',
    () async {
      final e = EditorController(
        document: PixDocument(name: 't', width: 96, height: 96),
      );
      final bytes = await redBlueTile();
      final assetId = e.assets.add(bytes, id: 'pat_test');
      await e.assets.decode(assetId);
      final doc = squareWith(
        PixFill.pattern(Patterns.forAsset(assetId), scale: 2),
      );
      expect(doc.referencedAssets, contains('pat_test'));
      final at = await render(doc, e.assets);
      // 16px tile at 2× = 32px: red 0..16, blue 16..32, red again at 32.
      expect(at(5, 5).r, greaterThan(0.9));
      expect(at(24, 5).b, greaterThan(0.9));
      expect(at(40, 5).r, greaterThan(0.9));
      e.dispose();
    },
  );

  test('pattern library hashes content and fits tiles', () async {
    final a = PatternLibrary.contentHash(Uint8List.fromList([1, 2, 3]));
    final b = PatternLibrary.contentHash(Uint8List.fromList([1, 2, 4]));
    expect(a, isNot(b));
    final big = await redBlueTile();
    final fitted = await PatternLibrary.fitPng(big, 8);
    final codec = await ui.instantiateImageCodec(fitted);
    final f = await codec.getNextFrame();
    expect(f.image.width, 8);
  });

  Future<double> inkCover(ui.Image img) async {
    final d = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    var ink = 0;
    for (var i = 0; i < img.width * img.height; i++) {
      if (d.getUint8(i * 4 + 3) > 128) ink++;
    }
    return ink / (img.width * img.height);
  }

  test('element size grows the dots, not the tile', () async {
    final small = Patterns.tile('dots', detail: 0.5)!;
    final big = Patterns.tile('dots', detail: 2)!;
    expect(small.width, big.width);
    expect(await inkCover(big), greaterThan(await inkCover(small) * 4));
    final f = PixFill.pattern('dots', detail: 1.7, tint: true);
    final back = PixFill.fromJson(f.toJson());
    expect(back.detail, 1.7);
    expect(back.tint, isTrue);
  });

  test(
    'pattern maker lays motifs out in a grid, bricks or half-drops',
    () async {
      final rec = ui.PictureRecorder();
      Canvas(rec).drawRect(
        const Rect.fromLTWH(0, 0, 20, 10),
        Paint()..color = const Color(0xFF000000),
      );
      final src = rec.endRecording().toImageSync(20, 10);
      final grid = buildPatternTile(src, const PatternMakerOptions(spacing: 1));
      expect(grid.width, 40);
      expect(grid.height, 20);
      expect(await inkCover(grid), closeTo(0.25, 0.03));
      final brick = buildPatternTile(
        src,
        const PatternMakerOptions(
          spacing: 1,
          arrangement: PatternArrangement.brick,
        ),
      );
      expect(brick.height, 40);
      final drop = buildPatternTile(
        src,
        const PatternMakerOptions(arrangement: PatternArrangement.halfDrop),
      );
      expect(drop.width, 40);
      final mirrored = buildPatternTile(
        src,
        const PatternMakerOptions(mirror: true),
      );
      expect(mirrored.width, 40);
      // Stencil: dark pixels become (white) ink.
      final stencil = buildPatternTile(
        src,
        const PatternMakerOptions(recolor: true),
      );
      expect(await inkCover(stencil), closeTo(1, 0.02));
    },
  );
}

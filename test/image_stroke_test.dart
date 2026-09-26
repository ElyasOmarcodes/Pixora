import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixora/document/assets/asset_store.dart';
import 'package:pixora/document/model/document.dart';
import 'package:pixora/document/model/fill.dart';
import 'package:pixora/document/model/layer.dart';
import 'package:pixora/document/model/layer_stroke.dart';
import 'package:pixora/document/model/layer_transform.dart';
import 'package:pixora/document/render/document_renderer.dart';

void main() {
  test('an image layer takes a stroke around its pixels', () async {
    // A 200 px grey photo fitted to 40 canvas px (scale 0.2).
    final rec = ui.PictureRecorder();
    Canvas(rec).drawColor(const Color(0xFF808080), BlendMode.src);
    final photo = await rec.endRecording().toImage(200, 200);
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
            transform: const LayerTransform(
              x: 50,
              y: 50,
              scaleX: 0.2,
              scaleY: 0.2,
            ),
            // 4 canvas px outside = 20 of the photo's own pixels.
            stroke: LayerStroke(
              size: 20,
              position: StrokePosition.outside,
              fill: PixFill.color(const Color(0xFFFF0000)),
            ),
          ),
          assetId: id,
          width: 200,
          height: 200,
        ),
      ],
    );
    final img = await DocumentRenderer(store).renderImage(doc);
    final data = (await img.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    ))!;
    Color px(int x, int y) {
      final i = (y * 100 + x) * 4;
      return Color.fromARGB(
        data.getUint8(i + 3),
        data.getUint8(i),
        data.getUint8(i + 1),
        data.getUint8(i + 2),
      );
    }

    expect(px(28, 50).r, greaterThan(0.9)); // stroke
    expect(px(28, 50).g, lessThan(0.1));
    expect(px(50, 50).r, closeTo(0x80 / 255, 0.03)); // the photo
    expect(px(23, 50).a, lessThan(0.05)); // beyond the stroke
  });
}

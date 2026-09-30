import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pixora/document/assets/asset_store.dart';
import 'package:pixora/document/model/document.dart';
import 'package:pixora/document/model/fill.dart';
import 'package:pixora/document/model/layer.dart';
import 'package:pixora/document/model/layer_transform.dart';
import 'package:pixora/document/render/document_renderer.dart';
import 'package:pixora/document/render/layer_cache.dart';

/// Zoomed far in, curved text stays as sharp as flat text: its bitmap is
/// made for the part in view at screen resolution, not enlarged from a
/// whole-text bitmap capped at 4096 px (which blurred into steps).
void main() {
  test('curved text is sharp at 8x zoom', () async {
    final r = DocumentRenderer(
      AssetStore(),
      cache: LayerRasterCache(),
      pixelScale: 8,
    );
    final doc = PixDocument(
      name: 'd',
      width: 1080,
      height: 1080,
      background: PixFill.color(const ui.Color(0xFFFFFFFF)),
      layers: [
        TextLayer(
          LayerProps(
            id: 't',
            name: 't',
            transform: const LayerTransform(x: 540, y: 540),
          ),
          text: 'سکابل سلام',
          fontSize: 260,
          curve: 120,
          fill: PixFill.color(const ui.Color(0xFF111111)),
        ),
      ],
    );
    for (final at in [const ui.Offset(560, 150), const ui.Offset(190, 190)]) {
      late ui.Image img;
      // A few frames, as on screen (the layer cache decides on the way).
      for (var f = 0; f < 3; f++) {
        final rec = ui.PictureRecorder();
        final c = ui.Canvas(rec, const ui.Rect.fromLTWH(0, 0, 500, 500))
          ..clipRect(const ui.Rect.fromLTWH(0, 0, 500, 500))
          ..scale(8)
          ..translate(-at.dx, -at.dy);
        r.paint(c, doc);
        img = rec.endRecording().toImageSync(500, 500);
      }
      final px = (await img.toByteData())!.buffer.asUint8List();
      var soft = 0, dark = 0;
      for (var i = 0; i < px.length; i += 4) {
        final v = px[i + 1];
        if (v > 40 && v < 215) soft++;
        if (v <= 40) dark++;
      }
      expect(dark, greaterThan(20000), reason: 'text in view at $at');
      // Blurred edges were ~6000–7000 in-between pixels; sharp ~350–600.
      expect(soft, lessThan(1500), reason: 'edge sharpness at $at');
    }
  });
}

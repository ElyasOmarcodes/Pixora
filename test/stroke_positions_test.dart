import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pixora/document/assets/asset_store.dart';
import 'package:pixora/document/model/document.dart';
import 'package:pixora/document/model/fill.dart';
import 'package:pixora/document/model/layer.dart';
import 'package:pixora/document/model/layer_stroke.dart';
import 'package:pixora/document/model/layer_transform.dart';
import 'package:pixora/document/render/document_renderer.dart';

/// Inside and centre strokes on photos must ring the edge, never fill the
/// picture (Impeller dropped colour filters on Lighten / Darken draws,
/// which emptied the shrunk shape). Run with `--enable-impeller` too.
void main() {
  Future<Uint8List> png(void Function(ui.Canvas c) paint) async {
    final rec = ui.PictureRecorder();
    paint(ui.Canvas(rec));
    final im = rec.endRecording().toImageSync(200, 200);
    final data = await im.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  for (final round in [false, true]) {
    test(
      '${round ? 'round' : 'square'} photo: stroke rings the edge',
      () async {
        final bytes = await png((c) {
          final p = ui.Paint()..color = const ui.Color(0xFF2266AA);
          round
              ? c.drawCircle(const ui.Offset(100, 100), 100, p)
              : c.drawRect(const ui.Rect.fromLTWH(0, 0, 200, 200), p);
        });
        final store = AssetStore()..addAll({'a': bytes});
        await store.decode('a');
        for (final pos in StrokePosition.values) {
          final doc = PixDocument(
            name: 'x',
            width: 300,
            height: 300,
            background: PixFill.color(const ui.Color(0xFFFFFFFF)),
            layers: [
              RasterLayer(
                LayerProps(
                  id: 'r',
                  name: 'r',
                  transform: const LayerTransform(x: 150, y: 150),
                  stroke: LayerStroke(
                    size: 12,
                    position: pos,
                    fill: PixFill.color(const ui.Color(0xFFFF0000)),
                  ),
                ),
                assetId: 'a',
                width: 200,
                height: 200,
              ),
            ],
          );
          final img = await DocumentRenderer(store).renderImage(doc);
          final px = (await img.toByteData())!.buffer.asUint8List();
          List<int> at(int x, int y) {
            final i = (y * 300 + x) * 4;
            return px.sublist(i, i + 3);
          }

          // The middle keeps the photo.
          expect(at(150, 150), [0x22, 0x66, 0xAA], reason: '$pos centre');
          expect(at(120, 150), [0x22, 0x66, 0xAA], reason: '$pos inner');
          // Just inside the edge: stroke for centre / inside.
          final edge = at(53, 150);
          if (pos == StrokePosition.outside) {
            expect(edge, [0x22, 0x66, 0xAA], reason: '$pos edge');
            expect(at(45, 150), [255, 0, 0], reason: '$pos outside');
          } else {
            expect(edge, [255, 0, 0], reason: '$pos edge');
          }
        }
      },
    );
  }
}

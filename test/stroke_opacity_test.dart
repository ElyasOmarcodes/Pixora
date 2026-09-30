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
import 'package:pixora/document/render/layer_cache.dart';

Future<Uint8List> _png(ui.Image i) async =>
    (await i.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();

Future<Uint8List> _rgba(ui.Image i) async =>
    (await i.toByteData())!.buffer.asUint8List();

void main() {
  test('a faded layer with a stroke exports as it shows on screen', () async {
    // A white card with a soft, faint shadow around it.
    final rec = ui.PictureRecorder();
    final c = ui.Canvas(rec);
    c.drawRRect(
      ui.RRect.fromLTRBR(20, 20, 180, 180, const ui.Radius.circular(16)),
      ui.Paint()
        ..color = const ui.Color(0x33000000)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 8),
    );
    c.drawRRect(
      ui.RRect.fromLTRBR(24, 24, 176, 176, const ui.Radius.circular(16)),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
    final card = rec.endRecording().toImageSync(200, 200);
    final store = AssetStore()..addAll({'card': await _png(card)});
    await store.decode('card');
    final doc = PixDocument(
      name: 'x',
      width: 400,
      height: 400,
      background: PixFill.color(const ui.Color(0xFF4B0101)),
      layers: [
        RasterLayer(
          LayerProps(
            id: 'card',
            name: 'card',
            opacity: 0.7,
            transform: const LayerTransform(
              x: 200,
              y: 200,
              scaleX: 1.5,
              scaleY: 1.5,
            ),
            stroke: LayerStroke(
              size: 10,
              position: StrokePosition.center,
              fill: PixFill.color(const ui.Color(0xFFFFFFFF)),
            ),
          ),
          assetId: 'card',
          width: 200,
          height: 200,
        ),
      ],
    );
    final export = await _rgba(
      await DocumentRenderer(store, pixelScale: 1).renderImage(doc),
    );
    final r = DocumentRenderer(store, cache: LayerRasterCache(), pixelScale: 1);
    final pr = ui.PictureRecorder();
    r.paint(ui.Canvas(pr), doc);
    final screen = await _rgba(pr.endRecording().toImageSync(400, 400));
    var worst = 0, sum = 0;
    for (var i = 0; i < export.length; i++) {
      final d = (export[i] - screen[i]).abs();
      sum += d;
      if (d > worst) worst = d;
    }
    // Resampling at edges only: no systematic difference.
    expect(sum / export.length, lessThan(0.8));
    expect(worst, lessThan(90));
  });
}

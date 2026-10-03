import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pixora/document/assets/asset_store.dart';
import 'package:pixora/document/model/document.dart';
import 'package:pixora/document/model/fill.dart';
import 'package:pixora/document/model/layer.dart';
import 'package:pixora/document/model/layer_transform.dart';
import 'package:pixora/document/render/document_renderer.dart';
import 'package:pixora/features/editor/widgets/pasteboard.dart';

/// Layers moved off the canvas show on the pasteboard (faded) but are
/// never part of the picture or its export.
void main() {
  final doc = PixDocument(
    name: 'd',
    width: 100,
    height: 100,
    background: PixFill.color(const ui.Color(0xFFFFFFFF)),
    layers: [
      ShapeLayer(
        LayerProps(name: 's', transform: const LayerTransform(x: 100, y: 50)),
        shape: ShapeKind.rectangle,
        width: 80,
        height: 40,
        fill: PixFill.color(const ui.Color(0xFFFF0000)),
      ),
    ],
  );

  Future<List<int>> at(void Function(ui.Canvas c) paint, int x, int y) async {
    final rec = ui.PictureRecorder();
    final c = ui.Canvas(rec)..translate(50, 0);
    paint(c);
    final img = rec.endRecording().toImageSync(250, 100);
    final px = (await img.toByteData())!.buffer.asUint8List();
    final i = (y * 250 + x + 50) * 4;
    return px.sublist(i, i + 4);
  }

  test('outside part only on the pasteboard', () async {
    final r = DocumentRenderer(AssetStore());
    // Without the pasteboard: nothing beyond the canvas edge.
    expect(await at((c) => r.paint(c, doc), 120, 50), [0, 0, 0, 0]);
    // With it: the outside part, faded.
    final out = await at(
      (c) {
        r.paint(c, doc);
        r.paintPasteboard(c, doc);
      },
      120,
      50,
    );
    expect(out[0], greaterThan(100));
    expect(out[3], inInclusiveRange(120, 180));
    // Inside the canvas the layer is painted once, at full strength.
    expect(
      await at(
        (c) {
          r.paint(c, doc);
          r.paintPasteboard(c, doc);
        },
        80,
        50,
      ),
      [255, 0, 0, 255],
    );
    // The export is the canvas only.
    final img = await r.renderImage(doc);
    expect((img.width, img.height), (100, 100));
  });

  test('pattern names round-trip', () {
    for (final p in PasteboardPattern.values) {
      expect(PasteboardPattern.of(p.name), p);
    }
    expect(PasteboardPattern.of('nonsense'), PasteboardPattern.plain);
  });
}

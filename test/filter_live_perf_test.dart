import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pixora/document/assets/asset_store.dart';
import 'package:pixora/document/effects/effect_registry.dart';
import 'package:pixora/document/model/document.dart';
import 'package:pixora/document/model/fill.dart';
import 'package:pixora/document/model/layer.dart';
import 'package:pixora/document/model/layer_transform.dart';
import 'package:pixora/document/render/document_renderer.dart';
import 'package:pixora/document/render/layer_cache.dart';

void main() {
  test('rotating a filtered layer on screen', () async {
    final cache = LayerRasterCache();
    final r = DocumentRenderer(AssetStore(), cache: cache, pixelScale: 1);
    Layer layer(double rot) => TextLayer(
      LayerProps(
        id: 'fixed',
        name: 't',
        transform: LayerTransform(x: 540, y: 540, rotation: rot),
        effects: [
          EffectRegistry.instance['ripple']!.create(),
          EffectRegistry.instance['dispersion']!.create({'size': 6}),
        ],
      ),
      text: 'سکابل',
      fontSize: 260,
      fill: PixFill.color(const ui.Color(0xFFFF0000)),
    );
    Future<int> frame(double rot) async {
      final doc = PixDocument(
        name: 'd',
        width: 1080,
        height: 1080,
        layers: [layer(rot)],
      );
      final sw = Stopwatch()..start();
      final rec = ui.PictureRecorder();
      r.paint(ui.Canvas(rec), doc);
      final img = rec.endRecording().toImageSync(540, 540);
      await img.toByteData();
      return sw.elapsedMilliseconds;
    }

    final times = <int>[];
    for (var i = 0; i < 12; i++) {
      times.add(await frame(i * 0.05));
    }
    // The first frame filters; while the layer keeps turning, the
    // following frames reuse that result instead of filtering again.
    final later = times.sublist(2)..sort();
    expect(later[later.length ~/ 2], lessThan(times.first ~/ 3));
  });
}

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
import 'package:pixora/document/render/layer_cache.dart';

void main() {
  test('hundreds of layers repaint quickly once cached', () {
    final layers = <Layer>[
      for (var i = 0; i < 300; i++)
        ShapeLayer(
          LayerProps(
            name: 's$i',
            transform: LayerTransform(x: (i * 37) % 1000, y: (i * 53) % 1000),
            effects: i.isEven
                ? [EffectRegistry.instance['shadow']!.create(const {})]
                : const [],
          ),
          shape: ShapeKind.values[i % 6],
          width: 60,
          height: 60,
          fill: PixFill.color(Color(0xFF000000 | (i * 9973) & 0xFFFFFF)),
        ),
    ];
    var doc = PixDocument(name: 't', width: 1000, height: 1000, layers: layers);
    final cache = LayerRasterCache();
    final r = DocumentRenderer(AssetStore(), cache: cache, pixelScale: 1);
    void frame() {
      final rec = ui.PictureRecorder();
      r.paint(Canvas(rec), doc);
      rec.endRecording().dispose();
    }

    frame(); // warm up: builds the bitmaps
    frame();
    final sw = Stopwatch()..start();
    for (var i = 0; i < 20; i++) {
      // Dragging one layer: a new document each frame.
      final moved = doc.layers.first.withProps(
        doc.layers.first.props.copyWith(
          transform: LayerTransform(x: i * 3.0, y: 10),
        ),
      );
      doc = doc.copyWith(layers: [moved, ...doc.layers.skip(1)]);
      frame();
    }
    final perFrame = sw.elapsedMicroseconds / 20 / 1000;
    // ignore: avoid_print
    print('300 layers: ${perFrame.toStringAsFixed(2)} ms per frame');
    expect(perFrame, lessThan(40));
  });
}

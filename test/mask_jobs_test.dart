import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixora/document/assets/asset_store.dart';
import 'package:pixora/document/effects/effect_registry.dart';
import 'package:pixora/document/model/document.dart';
import 'package:pixora/document/model/effect.dart';
import 'package:pixora/document/model/fill.dart';
import 'package:pixora/document/model/layer.dart';
import 'package:pixora/document/model/layer_transform.dart';
import 'package:pixora/document/render/document_renderer.dart';
import 'package:pixora/document/render/mask_jobs.dart';

PixDocument doc(double size) => PixDocument(
  name: 't',
  width: 100,
  height: 100,
  layers: [
    ShapeLayer(
      LayerProps(
        id: 'ly_1',
        name: 's',
        effects: [
          LayerEffect(
            id: 'fx_1',
            type: 'bevel',
            params: EffectRegistry.instance['bevel']!.create({
              'size': size,
              'highlightOpacity': 1,
              'highlightMode': 0,
            }).params,
          ),
        ],
        transform: const LayerTransform(x: 50, y: 50),
      ),
      shape: ShapeKind.rectangle,
      width: 60,
      height: 60,
      fill: PixFill.color(const Color(0xFF404040)),
    ),
  ],
);

Future<ByteData> paintNow(PixDocument d) async {
  final rec = ui.PictureRecorder();
  DocumentRenderer(AssetStore()).paint(Canvas(rec), d);
  final img = await rec.endRecording().toImage(100, 100);
  return (await img.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!;
}

int lum(ByteData b, int x, int y) => b.getUint8((y * 100 + x) * 4);

void main() {
  test('a bevel never vanishes while new settings compute', () async {
    // Compute the first settings fully (as export does).
    await DocumentRenderer(AssetStore()).renderImage(doc(6));
    // New settings: painted at once, the previous bevel still shows.
    final b = await paintNow(doc(9));
    // Top-left inner edge is lit (light from 120°).
    expect(lum(b, 22, 50), greaterThan(0x50));
  });

  test('newer requests replace queued ones and keep the latest', () async {
    final cache = MaskJobCache.instance;
    ui.Image img() {
      final rec = ui.PictureRecorder();
      Canvas(rec).drawRect(
        const Rect.fromLTWH(0, 0, 4, 4),
        Paint()..color = const Color(0xFFFFFFFF),
      );
      return rec.endRecording().toImageSync(4, 4);
    }

    List<Uint8List> job(Uint8List rgba, int w, int h) => [
      Uint8List(w * h)..fillRange(0, w * h, 200),
    ];
    cache.request(
      'k1',
      'slot',
      img(),
      const Rect.fromLTWH(0, 0, 4, 4),
      job,
      lane: MaskLane.now,
    );
    await cache.wait('k1');
    expect(cache.latest('slot'), isNotNull);
    cache
      ..request('k2', 'slot', img(), const Rect.fromLTWH(0, 0, 4, 4), job)
      ..request('k3', 'slot', img(), const Rect.fromLTWH(0, 0, 4, 4), job);
    expect(cache.isPending('k2'), isFalse); // replaced by k3
    expect(cache.isPending('k3'), isTrue);
    expect(cache.latest('slot'), isNotNull);
    await cache.wait('k3');
    expect(cache.lookup('k3'), isNotNull);
  });
}

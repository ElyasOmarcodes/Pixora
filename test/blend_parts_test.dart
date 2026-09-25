import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixora/document/assets/asset_store.dart';
import 'package:pixora/document/effects/effect_registry.dart';
import 'package:pixora/document/model/blend.dart';
import 'package:pixora/document/model/document.dart';
import 'package:pixora/document/model/effect.dart';
import 'package:pixora/document/model/fill.dart';
import 'package:pixora/document/model/layer.dart';
import 'package:pixora/document/model/layer_stroke.dart';
import 'package:pixora/document/model/layer_transform.dart';
import 'package:pixora/document/render/document_renderer.dart';
import 'package:pixora/document/render/layer_cache.dart';

PixDocument doc(LayerProps props, {Color bg = const Color(0xFF00FF00)}) =>
    PixDocument(
      name: 't',
      width: 100,
      height: 100,
      background: PixFill.color(bg),
      layers: [
        ShapeLayer(
          props.copyWith(transform: const LayerTransform(x: 50, y: 50)),
          shape: ShapeKind.rectangle,
          width: 40,
          height: 40,
          fill: PixFill.color(const Color(0xFFFFFFFF)),
        ),
      ],
    );

Future<Color Function(int, int)> pixels(
  PixDocument d, {
  bool cached = false,
}) async {
  final ByteData data;
  if (cached) {
    await DocumentRenderer(AssetStore()).renderImage(d); // styles ready
    final rec = ui.PictureRecorder();
    DocumentRenderer(
      AssetStore(),
      cache: LayerRasterCache(),
    ).paint(Canvas(rec), d);
    final img = await rec.endRecording().toImage(100, 100);
    data = (await img.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!;
  } else {
    final img = await DocumentRenderer(AssetStore()).renderImage(d);
    data = (await img.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!;
  }
  return (int x, int y) {
    final i = (y * 100 + x) * 4;
    return Color.fromARGB(
      data.getUint8(i + 3),
      data.getUint8(i),
      data.getUint8(i + 1),
      data.getUint8(i + 2),
    );
  };
}

LayerEffect fx(String t, Map<String, Object> p) =>
    EffectRegistry.instance[t]!.create(p);

void main() {
  for (final cached in [false, true]) {
    test(
      'effect blend modes blend with what is beneath (cached: $cached)',
      () async {
        // Red Multiply shadow on green → black, not red.
        final px = await pixels(
          doc(
            LayerProps(
              name: 's',
              effects: [
                fx('shadow', {
                  'dx': 15,
                  'dy': 0,
                  'blur': 0,
                  'opacity': 1,
                  'color': 0xFFFF0000,
                  'blend': 2,
                }),
              ],
            ),
          ),
          cached: cached,
        );
        expect(px(80, 50).r, lessThan(0.1));
        expect(px(80, 50).g, lessThan(0.1));

        // Screen stroke (blue) on green → cyan.
        final st = await pixels(
          doc(
            LayerProps(
              name: 's',
              stroke: LayerStroke(
                size: 6,
                fill: PixFill.color(const Color(0xFF0000FF)),
                blend: PixBlendMode.screen,
              ),
            ),
          ),
          cached: cached,
        );
        expect(st(27, 50).g, greaterThan(0.9));
        expect(st(27, 50).b, greaterThan(0.9));
        // Layer opacity still fades the effects.
        final faded = await pixels(
          doc(
            LayerProps(
              name: 's',
              opacity: 0.5,
              effects: [
                fx('shadow', {
                  'dx': 15,
                  'dy': 0,
                  'blur': 0,
                  'opacity': 1,
                  'color': 0xFF000000,
                }),
              ],
            ),
          ),
          cached: cached,
        );
        expect(faded(80, 50).g, closeTo(0.5, 0.05));
      },
    );
  }

  test('3D sides are lit by the way they face', () async {
    final px = await pixels(
      doc(
        LayerProps(
          name: 's',
          effects: [
            fx('extrude', {
              'depth': 20,
              'angle': 45,
              'color': 0xFFFFFFFF,
              'shade': 0,
              'lightAngle': 90,
              'altitude': 0,
              'intensity': 100,
              'ambient': 0,
            }),
          ],
        ),
        bg: const Color(0xFF000000),
      ),
    );
    // Extrusion goes down-right; light from the top: the bottom side
    // (facing down) is dark, the right side (facing right) half-lit at most.
    final bottom = px(55, 76).r;
    final right = px(76, 55).r;
    expect(bottom, lessThan(0.2));
    expect(right, lessThan(0.6));
    // Light from below instead: the bottom side is bright.
    final below = await pixels(
      doc(
        LayerProps(
          name: 's',
          effects: [
            fx('extrude', {
              'depth': 20,
              'angle': 45,
              'color': 0xFFFFFFFF,
              'shade': 0,
              'lightAngle': -90,
              'altitude': 0,
              'intensity': 100,
              'ambient': 0,
            }),
          ],
        ),
        bg: const Color(0xFF000000),
      ),
    );
    expect(below(55, 76).r, greaterThan(0.8));
  });
}

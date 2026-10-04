import 'dart:typed_data';
import 'dart:ui';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pixora/document/assets/asset_store.dart';
import 'package:pixora/document/model/document.dart';
import 'package:pixora/document/model/fill.dart';
import 'package:pixora/document/model/layer.dart';
import 'package:pixora/document/model/layer_stroke.dart';
import 'package:pixora/document/model/layer_transform.dart';
import 'package:pixora/document/render/bevel_engine.dart';
import 'package:pixora/document/render/document_renderer.dart';

void main() {
  test('custom contours round-trip and follow their points', () {
    final c = ContourCurve(const [Offset(0, 0), Offset(0.5, 1), Offset(1, 0)]);
    expect(c.apply(0), closeTo(0, 0.02));
    expect(c.apply(0.5), closeTo(1, 0.02));
    expect(ContourCurve.decode(c.encode()), c);
    expect(ContourCurve.decode('garbage'), isNull);
  });

  test('a Ring gloss turns part of the lit slope into shadow', () {
    // A 40 px disc: its upper-left slope faces the light.
    const w = 64, h = 64;
    final alpha = Float32List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final d = Offset(x - 32.0, y - 32.0).distance;
        alpha[y * w + x] = d < 20 ? 1 : 0;
      }
    }
    double shadowOnLitSide(ContourPreset g) {
      final (_, sh) = BevelEngine.shade(
        alpha,
        w,
        h,
        1,
        BevelParams(size: 16, depth: 3, gloss: g),
      );
      var s = 0.0;
      for (var y = 14; y < 30; y++) {
        for (var x = 14; x < 30; x++) {
          s += sh[y * w + x];
        }
      }
      return s;
    }

    // Linear: the lit side has no shadow; a Ring bands it (metal).
    expect(shadowOnLitSide(ContourPreset.linear), lessThan(1));
    expect(shadowOnLitSide(ContourPreset.ring), greaterThan(5));
  });

  test('a Shape Burst stroke runs its gradient across the band', () async {
    final doc = PixDocument(
      name: 't',
      width: 120,
      height: 120,
      background: PixFill.color(const Color(0xFF000000)),
      layers: [
        ShapeLayer(
          LayerProps(
            id: 's',
            name: 's',
            transform: const LayerTransform(x: 60, y: 60),
            stroke: LayerStroke(
              size: 20,
              position: StrokePosition.outside,
              burst: true,
              fill: PixFill.linear(const [
                Color(0xFFFF0000),
                Color(0xFF0000FF),
              ]),
            ),
          ),
          shape: ShapeKind.rectangle,
          width: 40,
          height: 40,
          fill: PixFill.color(const Color(0xFFFFFFFF)),
        ),
      ],
    );
    final img = await DocumentRenderer(AssetStore()).renderImage(doc);
    final data = (await img.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    ))!;
    int red(int x, int y) => data.getUint8((y * 120 + x) * 4);
    int blue(int x, int y) => data.getUint8((y * 120 + x) * 4 + 2);
    // Inner edge (x = 82) red, outer edge (x = 98) blue — on every side.
    expect(red(82, 60), greaterThan(blue(82, 60)));
    expect(blue(98, 60), greaterThan(red(98, 60)));
    expect(red(60, 82), greaterThan(blue(60, 82)));
    expect(blue(60, 98), greaterThan(red(60, 98)));
  });
}

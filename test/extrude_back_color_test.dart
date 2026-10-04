import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pixora/document/assets/asset_store.dart';
import 'package:pixora/document/effects/effect_registry.dart';
import 'package:pixora/document/model/document.dart';
import 'package:pixora/document/model/fill.dart';
import 'package:pixora/document/model/layer.dart';
import 'package:pixora/document/model/layer_stroke.dart';
import 'package:pixora/document/model/layer_transform.dart';
import 'package:pixora/document/model/patterns.dart';
import 'package:pixora/document/render/document_renderer.dart';

void main() {
  test('extrusion sides turn from front colour to back colour', () {
    final e = EffectRegistry.instance['extrude']!.create({
      'material': 0.0,
      'color': 0xFFFFFFFF,
      'color2': 0xFF000000,
      'backMix': 50.0,
    });
    final x = ExtrudeSpec.of(e);
    expect(x.colorAt(0), const Color(0xFFFFFFFF));
    // Half-way towards black at the back.
    expect((x.colorAt(1).r * 255).round(), closeTo(128, 1));
    // Older projects (no back colour): sides stay the front colour.
    final old = ExtrudeSpec.of(
      EffectRegistry.instance['extrude']!.create({
        'material': 0.0,
        'color': 0xFF336699,
      }),
    );
    expect(old.colorAt(1), const Color(0xFF336699));
  });

  test('pattern overlay assets are kept with the layer', () {
    final fill = PixFill.pattern(Patterns.forAsset('as_wood'));
    final layer = ShapeLayer(
      LayerProps(
        id: 's',
        name: 's',
        effects: [
          EffectRegistry.instance['colorFill']!.create({
            'fill': jsonEncode(fill.toJson()),
          }),
        ],
      ),
      shape: ShapeKind.rectangle,
      width: 10,
      height: 10,
      fill: PixFill.color(const Color(0xFF000000)),
    );
    expect(layer.fillAssets, contains('as_wood'));
  });

  test('gradient material and floor shadow are read from params', () {
    final g = PixFill.linear(const [Color(0xFFFF0000), Color(0xFF0000FF)]);
    final x = ExtrudeSpec.of(
      EffectRegistry.instance['extrude']!.create({
        'material': 2.0,
        'matFill': jsonEncode(g.toJson()),
      }),
    );
    expect(x.materialFill?.colors, g.colors);
    expect(x.layerMaterial, isFalse);
    // A gradient material is not tinted by the front colour.
    expect(x.colorAt(0), const Color(0xFFFFFFFF));
    final def = EffectRegistry.instance['shadow']!;
    expect(def.shadow!(def.create({'squash': 80.0}))!.squash, 0.8);
  });

  Future<ByteData> render(Layer layer) async {
    final doc = PixDocument(
      name: 't',
      width: 200,
      height: 100,
      background: PixFill.color(const Color(0xFF000000)),
      layers: [layer],
    );
    final img = await DocumentRenderer(AssetStore()).renderImage(doc);
    return (await img.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!;
  }

  test('the extrusion starts from the outside of the stroke', () async {
    // A 40 px square with a 20 px outside stroke, pushed 30 px right.
    final data = await render(
      ShapeLayer(
        LayerProps(
          id: 's',
          name: 's',
          transform: const LayerTransform(x: 70, y: 50),
          stroke: LayerStroke(
            size: 20,
            fill: PixFill.color(const Color(0xFF00FF00)),
            position: StrokePosition.outside,
          ),
          effects: [
            EffectRegistry.instance['extrude']!.create({
              'depth': 30.0,
              'angle': 0.0,
              'material': 0.0,
              'color': 0xFFFF0000,
              'shade': 0.0,
              'intensity': 0.0,
              'ambient': 100.0,
            }),
          ],
        ),
        shape: ShapeKind.rectangle,
        width: 40,
        height: 40,
        fill: PixFill.color(const Color(0xFFFFFFFF)),
      ),
    );
    int red(int x, int y) => data.getUint8((y * 200 + x) * 4);
    int green(int x, int y) => data.getUint8((y * 200 + x) * 4 + 1);
    // The stroke ends at x = 110; the solid's red side shows beyond it.
    expect(green(105, 50), greaterThan(200));
    expect(red(125, 50), greaterThan(200));
    expect(green(125, 50), lessThan(60));
  });
}

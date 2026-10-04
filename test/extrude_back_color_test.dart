import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixora/document/effects/effect_registry.dart';
import 'package:pixora/document/model/fill.dart';
import 'package:pixora/document/model/layer.dart';
import 'package:pixora/document/model/patterns.dart';

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
      EffectRegistry.instance['extrude']!.create({'color': 0xFF336699}),
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
}

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixora/document/effects/effect_registry.dart';
import 'package:pixora/document/effects/global_light.dart';
import 'package:pixora/document/model/document.dart';
import 'package:pixora/document/model/effect.dart';
import 'package:pixora/document/model/fill.dart';
import 'package:pixora/document/model/layer.dart';

LayerEffect fx(String type, [Map<String, Object> p = const {}]) =>
    EffectRegistry.instance[type]!.create(p);

ShapeLayer shape(String id, List<LayerEffect> effects) => ShapeLayer(
  LayerProps(id: id, name: id, effects: effects),
  shape: ShapeKind.rectangle,
  width: 10,
  height: 10,
  fill: PixFill.color(const Color(0xFF000000)),
);

void main() {
  test('moving one global light moves every global effect', () {
    final bevel = fx('bevel', {'angle': 120.0, 'altitude': 30.0});
    final shadow = fx('shadow', {'dx': 5.0, 'dy': 8.66}); // light at 120°
    final local = fx('innerShadow', {'global': 0.0, 'angle': 10.0});
    final before = PixDocument(
      name: 'd',
      width: 100,
      height: 100,
      layers: [
        shape('a', [bevel]),
        shape('b', [shadow, local]),
      ],
    );
    final moved = before.updateLayer(
      'a',
      (l) => l.withProps(
        l.props.copyWith(
          effects: [bevel.withParam('angle', 45.0).withParam('altitude', 50.0)],
        ),
      ),
    );
    final after = GlobalLight.sync(before, moved);
    expect(after.lightAngle, 45);
    expect(after.lightAltitude, 50);
    final b = after.layerById('b')!.props.effects;
    // The drop shadow now falls away from 45° (down-left), same distance.
    final s = b.firstWhere((e) => e.type == 'shadow');
    expect(s.number('dx', 0), closeTo(-7.07, 0.05));
    expect(s.number('dy', 0), closeTo(7.07, 0.05));
    // An effect with its own light is left alone.
    expect(b.firstWhere((e) => e.type == 'innerShadow').number('angle', 0), 10);
  });

  test('a new global effect adopts the document light', () {
    final before = PixDocument(
      name: 'd',
      width: 100,
      height: 100,
      lightAngle: 60,
      lightAltitude: 40,
      layers: [shape('a', const [])],
    );
    final added = before.updateLayer(
      'a',
      (l) => l.withProps(l.props.copyWith(effects: [fx('bevel')])),
    );
    final after = GlobalLight.sync(before, added);
    final e = after.layerById('a')!.props.effects.single;
    expect(e.number('angle', 0), 60);
    expect(e.number('altitude', 0), 40);
  });
}

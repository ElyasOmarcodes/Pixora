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

LayerEffect fx(String type, [Map<String, Object> p = const {}]) =>
    EffectRegistry.instance[type]!.create(p);

/// A red 40×40 square centred on a 100×100 canvas; returns a pixel reader.
Future<Color Function(int, int)> render(LayerProps props) async {
  final doc = PixDocument(
    name: 't',
    width: 100,
    height: 100,
    layers: [
      ShapeLayer(
        props.copyWith(transform: const LayerTransform(x: 50, y: 50)),
        shape: ShapeKind.rectangle,
        width: 40,
        height: 40,
        fill: PixFill.color(const Color(0xFFFF0000)),
      ),
    ],
  );
  final img = await DocumentRenderer(AssetStore()).renderImage(doc);
  final ByteData data = (await img.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  ))!;
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

void main() {
  test('fill opacity fades the content but not the drop shadow', () async {
    final shadow = fx('shadow', {'dx': 20, 'dy': 0, 'blur': 0, 'opacity': 1});
    final at = await render(
      LayerProps(name: 's', fillOpacity: 0, effects: [shadow]),
    );
    expect(at(40, 50).a, 0); // content gone
    expect(at(80, 50).a, greaterThan(0.9)); // shadow still there
    final half = await render(
      LayerProps(name: 's', fillOpacity: 0.5, effects: [shadow]),
    );
    expect(half(40, 50).a, closeTo(0.5, 0.05));
    // Opacity, by contrast, fades the shadow too.
    final op = await render(
      LayerProps(name: 's', opacity: 0.5, effects: [shadow]),
    );
    expect(op(80, 50).a, closeTo(0.5, 0.05));
  });

  test('inner effects keep strength unless blended as a group', () async {
    // A hard inner shadow shifted 10 px right fills the shape's left band.
    final inner = fx('innerShadow', {
      'distance': 10,
      'angle': 0,
      'blur': 0,
      'opacity': 1,
      'color': const Color(0xFF00FF00).toARGB32(),
    });
    final keep = await render(
      LayerProps(name: 's', fillOpacity: 0, effects: [inner]),
    );
    expect(keep(33, 50).a, greaterThan(0.9));
    expect(keep(33, 50).g, greaterThan(0.9));
    expect(keep(55, 50).a, 0); // no fill, no shadow here
    expect(keep(20, 50).a, 0); // nothing outside the shape
    final grouped = await render(
      LayerProps(
        name: 's',
        fillOpacity: 0,
        blendInterior: true,
        effects: [inner],
      ),
    );
    expect(grouped(33, 50).a, 0);
  });

  test('fill opacity round-trips through JSON', () {
    final p = LayerProps(name: 's', fillOpacity: 0.3, blendInterior: true);
    final back = LayerProps.fromJson(p.toJson());
    expect(back.fillOpacity, 0.3);
    expect(back.blendInterior, isTrue);
    expect(back, p);
  });
}

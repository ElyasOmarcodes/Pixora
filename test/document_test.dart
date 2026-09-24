import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixora/document/effects/effect_registry.dart';
import 'package:pixora/document/model/blend.dart';
import 'package:pixora/document/model/document.dart';
import 'package:pixora/document/model/fill.dart';
import 'package:pixora/document/model/layer.dart';
import 'package:pixora/document/model/layer_transform.dart';
import 'package:pixora/document/render/color_matrix.dart';
import 'package:pixora/document/render/text_layout.dart';

PixDocument sampleDoc() => PixDocument(
  name: 'Sample',
  width: 1080,
  height: 1350,
  background: PixFill.linear(const [
    Color(0xFF0A84FF),
    Color(0xFF021B4D),
  ], angle: 90),
  layers: [
    RasterLayer(
      LayerProps(name: 'Photo'),
      assetId: 'a1',
      width: 800,
      height: 600,
    ),
    ShapeLayer(
      LayerProps(
        name: 'Star',
        opacity: 0.5,
        blendMode: PixBlendMode.screen,
        transform: const LayerTransform(
          x: 100,
          y: 200,
          rotation: 0.5,
          scaleX: -2,
        ),
        effects: [EffectRegistry.instance['shadow']!.create()],
      ),
      shape: ShapeKind.star,
      width: 300,
      height: 300,
      sides: 7,
      strokeWidth: 4,
      strokeColor: const Color(0xFFFF0000),
    ),
    TextLayer(
      LayerProps(name: 'Title', locked: true),
      text: 'هجران عمر',
      fontSize: 120,
    ),
  ],
);

void main() {
  group('serialization', () {
    test('document round-trips through JSON', () {
      final doc = sampleDoc();
      final json = jsonDecode(jsonEncode(doc.toJson())) as Map<String, dynamic>;
      final back = PixDocument.fromJson(json);
      expect(back, doc);
    });

    test('unknown layer kinds are skipped, not fatal', () {
      final json = sampleDoc().toJson();
      (json['layers'] as List).add({'kind': 'hologram', 'id': 'x'});
      final back = PixDocument.fromJson(
        jsonDecode(jsonEncode(json)) as Map<String, dynamic>,
      );
      expect(back.layers.length, 3);
    });

    test('missing fields fall back to defaults', () {
      final doc = PixDocument.fromJson({
        'layers': [
          {'kind': 'text'},
        ],
      });
      expect(doc.width, 1080);
      expect((doc.layers.single as TextLayer).fontSize, 96);
    });
  });

  group('document operations', () {
    test('insert, move and remove layers', () {
      var doc = sampleDoc();
      final ids = doc.layers.map((l) => l.id).toList();
      doc = doc.moveLayerTo(ids[0], 2);
      expect(doc.layers.map((l) => l.id), [ids[1], ids[2], ids[0]]);
      doc = doc.removeLayer(ids[1]);
      expect(doc.layers.length, 2);
      expect(doc.referencedAssets, {'a1'});
    });

    test('clone gets fresh ids for layer and effects', () {
      final star = sampleDoc().layers[1];
      final copy = star.cloneWithNewId();
      expect(copy.id, isNot(star.id));
      expect(copy.props.effects.first.id, isNot(star.props.effects.first.id));
      expect(copy.props.effects.first.type, 'shadow');
    });
  });

  group('transform', () {
    test('toLocal inverts toDocument', () {
      const t = LayerTransform(
        x: 40,
        y: -12,
        rotation: 1.1,
        scaleX: -1.5,
        scaleY: 0.7,
      );
      const p = Offset(33, -80);
      final back = t.toLocal(t.toDocument(p));
      expect(back.dx, closeTo(p.dx, 1e-9));
      expect(back.dy, closeTo(p.dy, 1e-9));
    });

    test('rotation by 90° maps x axis to y axis', () {
      const t = LayerTransform(rotation: math.pi / 2);
      final p = t.toDocument(const Offset(10, 0));
      expect(p.dx, closeTo(0, 1e-9));
      expect(p.dy, closeTo(10, 1e-9));
    });
  });

  group('color matrix', () {
    test('concat with identity is a no-op', () {
      final m = ColorMatrix.saturation(0.3);
      expect(ColorMatrix.concat(m, ColorMatrix.identity), m);
      expect(ColorMatrix.concat(ColorMatrix.identity, m), m);
    });

    test('neutral adjustment values are identity', () {
      expect(ColorMatrix.isIdentity(ColorMatrix.brightness(0)), isTrue);
      expect(ColorMatrix.isIdentity(ColorMatrix.contrast(0)), isTrue);
      expect(ColorMatrix.isIdentity(ColorMatrix.saturation(0)), isTrue);
      expect(ColorMatrix.isIdentity(ColorMatrix.hue(0)), isTrue);
    });
  });

  test('text direction detection', () {
    expect(detectTextDirection('سلام'), TextDirection.rtl);
    expect(detectTextDirection('ښه راغلاست'), TextDirection.rtl);
    expect(detectTextDirection('Hello'), TextDirection.ltr);
    expect(detectTextDirection('123 مرحبا'), TextDirection.rtl);
  });
}

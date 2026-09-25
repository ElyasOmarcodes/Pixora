import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixora/document/assets/asset_store.dart';
import 'package:pixora/document/effects/effect_registry.dart';
import 'package:pixora/document/model/blend.dart';
import 'package:pixora/document/model/document.dart';
import 'package:pixora/document/model/fill.dart';
import 'package:pixora/document/model/layer.dart';
import 'package:pixora/document/model/layer_stroke.dart';
import 'package:pixora/document/model/layer_transform.dart';
import 'package:pixora/document/model/mask.dart';
import 'package:pixora/document/render/document_renderer.dart';
import 'package:pixora/features/editor/panels/style_panels.dart';

const red = Color(0xFFFF0000);
const blue = Color(0xFF0000FF);

/// A red 40×40 square centred on a 100×100 canvas (spans 30..70).
Future<Color Function(int, int)> render(
  LayerProps props, {
  Color? background,
}) async {
  final doc = PixDocument(
    name: 't',
    width: 100,
    height: 100,
    background: background == null ? null : PixFill.color(background),
    layers: [
      ShapeLayer(
        props.copyWith(transform: const LayerTransform(x: 50, y: 50)),
        shape: ShapeKind.rectangle,
        width: 40,
        height: 40,
        fill: PixFill.color(red),
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

LayerProps withStroke(LayerStroke s, {double fill = 1}) =>
    LayerProps(name: 's', stroke: s, fillOpacity: fill);

void main() {
  test('outside, centre and inside strokes', () async {
    final out = await render(
      withStroke(LayerStroke(size: 6, fill: PixFill.color(blue))),
    );
    expect(out(27, 50).b, greaterThan(0.9));
    expect(out(33, 50), red);
    expect(out(20, 50).a, 0);

    final centre = await render(
      withStroke(
        LayerStroke(
          size: 8,
          position: StrokePosition.center,
          fill: PixFill.color(blue),
        ),
      ),
    );
    expect(centre(28, 50).b, greaterThan(0.9));
    expect(centre(32, 50).b, greaterThan(0.9));
    expect(centre(40, 50), red);

    final inside = await render(
      withStroke(
        LayerStroke(
          size: 6,
          position: StrokePosition.inside,
          fill: PixFill.color(blue),
        ),
      ),
    );
    expect(inside(33, 50).b, greaterThan(0.9));
    expect(inside(50, 50), red);
    expect(inside(27, 50).a, 0);
  });

  test('gradient and pattern strokes', () async {
    final g = await render(
      withStroke(
        LayerStroke(
          size: 6,
          fill: PixFill.gradient(FillKind.linear, const [red, blue], angle: 0),
        ),
      ),
    );
    expect(g(27, 50).r, greaterThan(g(27, 50).b));
    expect(g(73, 50).b, greaterThan(g(73, 50).r));
    final p = await render(
      withStroke(
        LayerStroke(
          size: 8,
          fill: PixFill.pattern(
            'stripes',
            fg: blue,
            bg: const Color(0xFF00FF00),
            scale: 0.25,
          ),
        ),
      ),
    );
    // Stripes: rows alternate between blue and green in the stroke band.
    final colours = {for (var y = 30; y < 70; y++) p(26, y).b > 0.5};
    expect(colours, {true, false});
  });

  test('fill opacity keeps the stroke; stroke opacity and blend', () async {
    final at = await render(
      withStroke(LayerStroke(size: 6, fill: PixFill.color(blue)), fill: 0),
    );
    expect(at(50, 50).a, 0);
    expect(at(27, 50).b, greaterThan(0.9));

    final faint = await render(
      withStroke(LayerStroke(size: 6, fill: PixFill.color(blue), opacity: 0.5)),
    );
    expect(faint(27, 50).a, closeTo(0.5, 0.06));

    // Multiply a grey inside stroke onto the red fill: darker red.
    final mul = await render(
      withStroke(
        LayerStroke(
          size: 6,
          position: StrokePosition.inside,
          fill: PixFill.color(const Color(0xFF808080)),
          blend: PixBlendMode.multiply,
        ),
      ),
    );
    expect(mul(33, 50).r, closeTo(0.5, 0.06));
    expect(mul(33, 50).g, lessThan(0.05));
  });

  test('drop shadow follows the stroke; shadow blend mode', () async {
    final shadow = EffectRegistry.instance['shadow']!.create({
      'dx': 0,
      'dy': 20,
      'blur': 0,
      'opacity': 1,
    });
    final at = await render(
      LayerProps(
        name: 's',
        effects: [shadow],
        stroke: LayerStroke(size: 6, fill: PixFill.color(blue)),
      ),
    );
    // Below the square + stroke: the shadow of the stroke band (x = 27).
    expect(at(27, 92).a, greaterThan(0.9));

    final multiply = EffectRegistry.instance['shadow']!.create({
      'dx': 20,
      'dy': 0,
      'blur': 0,
      'opacity': 1,
      'color': const Color(0xFF808080).toARGB32(),
      'blend': PixBlendMode.multiply.index,
    });
    final m = await render(
      LayerProps(name: 's', effects: [multiply]),
      background: const Color(0xFF00FF00),
    );
    // Grey multiplied onto green → darker green.
    expect(m(80, 50).g, closeTo(0.5, 0.06));
    expect(m(80, 50).r, lessThan(0.05));
  });

  test('stroke JSON and old simple strokes', () {
    final s = LayerStroke(
      size: 7,
      position: StrokePosition.inside,
      fill: PixFill.pattern('dots', fg: blue),
      opacity: 0.4,
      blend: PixBlendMode.screen,
    );
    expect(LayerStroke.fromJson(s.toJson()), s);
    final p = LayerProps(name: 'x', stroke: s);
    expect(LayerProps.fromJson(p.toJson()).stroke, s);

    final oldText = TextLayer(
      LayerProps(name: 't'),
      text: 'Hi',
      strokeWidth: 10,
      strokeColor: blue,
    );
    final st = StrokePanel.strokeOf(oldText)!;
    expect(st.size, 5);
    expect(st.position, StrokePosition.outside);
    final converted = StrokePanel.withStroke(oldText, st) as TextLayer;
    expect(converted.strokeWidth, 0);
    expect(converted.props.stroke, st);

    final oldShape = ShapeLayer(
      LayerProps(name: 's'),
      shape: ShapeKind.rectangle,
      width: 10,
      height: 10,
      strokeWidth: 4,
      strokeColor: red,
    );
    expect(StrokePanel.strokeOf(oldShape)!.position, StrokePosition.center);
    expect(StrokePanel.strokeOf(oldShape)!.size, 4);
  });

  test('masked layers stroke their visible pixels (sampled band)', () async {
    // A mask that hides the right half: the stroke follows the cut.
    final mask = [
      MaskStroke(
        mode: MaskMode.hide,
        shape: MaskShape.area,
        points: const [
          Offset(0, -30),
          Offset(30, -30),
          Offset(30, 30),
          Offset(0, 30),
        ],
      ),
    ];
    for (final pos in StrokePosition.values) {
      final at = await render(
        LayerProps(
          name: 's',
          mask: mask,
          stroke: LayerStroke(
            size: 6,
            position: pos,
            fill: PixFill.color(blue),
          ),
        ),
      );
      if (pos == StrokePosition.inside) {
        expect(at(33, 50).b, greaterThan(0.9), reason: pos.name);
        expect(at(47, 50).b, greaterThan(0.9), reason: pos.name); // cut edge
      } else {
        expect(at(27, 50).b, greaterThan(0.9), reason: pos.name);
        expect(at(52, 50).b, greaterThan(0.9), reason: pos.name); // cut edge
      }
      expect(at(65, 50).a, 0, reason: pos.name); // hidden half stays empty
    }
  });
}

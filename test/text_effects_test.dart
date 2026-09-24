import 'package:flutter/painting.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixora/document/effects/effect_registry.dart';
import 'package:pixora/document/model/document.dart';
import 'package:pixora/document/model/fill.dart';
import 'package:pixora/document/model/layer.dart';
import 'package:pixora/document/model/layer_transform.dart';
import 'package:pixora/document/model/mask.dart';
import 'package:pixora/document/render/text_layout.dart';
import 'package:pixora/editor/editor_controller.dart';
import 'package:pixora/projects/pixora_format.dart';

TextLayer styled() => TextLayer(
  LayerProps(
    name: 'T',
    transform: const LayerTransform(x: 300, y: 200, tiltX: 20, tiltY: -15),
    mask: [
      MaskStroke(
        mode: MaskMode.hide,
        points: const [Offset(1, 2), Offset(10.5, -3)],
        width: 12,
        softness: 0.4,
      ),
      MaskStroke(
        mode: MaskMode.show,
        shape: MaskShape.area,
        points: const [Offset(0, 0), Offset(5, 0), Offset(5, 5)],
      ),
    ],
    effects: [
      EffectRegistry.instance['innerShadow']!.create(),
      EffectRegistry.instance['bevel']!.create({'style': 2}),
      EffectRegistry.instance['extrude']!.create({'depth': 30}),
    ],
  ),
  text: 'Hello world',
  align: PixTextAlign.justify,
  strike: true,
  textCase: PixTextCase.upper,
  wordSpacing: 6,
  curve: 120,
  background: PixFill.color(const Color(0xFF112233)),
  bgPadX: 0.5,
  bgPadY: 0.25,
  bgRadius: 0.4,
);

void main() {
  test('new text, mask, tilt and effect fields survive JSON and XML', () {
    final doc = PixDocument(
      name: 'fx',
      width: 800,
      height: 600,
      layers: [styled()],
    );
    expect(PixDocument.fromJson(doc.toJson()), doc);
    final (p, _) = PixoraFormat.decode(PixoraFormat.encode(doc, const {}));
    final t = p.document.layers.single as TextLayer;
    expect(t.curve, 120);
    expect(t.textCase, PixTextCase.upper);
    expect(t.background, isNotNull);
    expect(t.props.transform.tiltX, 20);
    expect(t.props.mask.length, 2);
    expect(t.props.mask.first.points.last, const Offset(10.5, -3));
    expect(t.props.effects.map((e) => e.type), [
      'innerShadow',
      'bevel',
      'extrude',
    ]);
  });

  test('tilted transform: toLocal inverts toDocument', () {
    const t = LayerTransform(
      x: 120,
      y: 80,
      rotation: 0.6,
      scaleX: 1.4,
      scaleY: 0.8,
      tiltX: 30,
      tiltY: -25,
    );
    for (final p in const [Offset(0, 0), Offset(50, -20), Offset(-80, 60)]) {
      final back = t.toLocal(t.toDocument(p));
      expect((back - p).distance, lessThan(1e-6));
    }
  });

  test('text case and curve change the layout', () {
    expect(styled().displayText, 'HELLO WORLD');
    final flat = styled().copyWith(curve: 0);
    final curved = styled().copyWith(curve: 180);
    final a = TextLayoutCache.instance.sizeOf(flat);
    final b = TextLayoutCache.instance.sizeOf(curved);
    // A half-circle is taller and narrower than the straight line.
    expect(b.height, greaterThan(a.height));
    expect(b.width, lessThan(a.width));
  });

  test('mask editing is undoable and invert flips modes', () {
    final l = styled();
    final e = EditorController(
      document: PixDocument(name: 'm', width: 800, height: 600, layers: [l]),
    );
    e.clearMask(l.id);
    expect(e.document.layerById(l.id)!.props.mask, isEmpty);
    e.undo();
    expect(e.document.layerById(l.id)!.props.mask.length, 2);
    e.invertMask(l.id);
    final m = e.document.layerById(l.id)!.props.mask;
    expect(m.length, 3);
    expect(m[1].mode, MaskMode.show);
    expect(m[2].mode, MaskMode.hide);
  });

  test('placing on canvas and fitting', () {
    final l = styled()
        .copyWith(curve: 0)
        .withProps(
          styled().props.copyWith(
            transform: const LayerTransform(x: 300, y: 200),
          ),
        );
    final e = EditorController(
      document: PixDocument(name: 'p', width: 800, height: 600, layers: [l]),
    );
    e.placeOnCanvas([l.id], const Alignment(-1, -1));
    final b = e.boundsOf([l.id]);
    expect(b.left, closeTo(0, 0.01));
    expect(b.top, closeTo(0, 0.01));
    e.fitToCanvas([l.id]);
    final f = e.boundsOf([l.id]);
    expect(f.width, closeTo(800, 0.5));
    expect(f.center.dx, closeTo(400, 0.5));
  });
}

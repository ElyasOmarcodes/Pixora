import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixora/document/model/document.dart';
import 'package:pixora/document/model/layer.dart';
import 'package:pixora/document/model/mask.dart';
import 'package:pixora/document/render/brush_paint.dart';
import 'package:pixora/document/render/document_renderer.dart';
import 'package:pixora/editor/editor_controller.dart';
import 'package:pixora/projects/pixora_format.dart';

void main() {
  test('Photoshop-style mask and drawing layers survive .pixora XML', () {
    final doc = PixDocument(
      name: 'm',
      width: 400,
      height: 400,
      layers: [
        DrawingLayer(
          LayerProps(
            name: 'd',
            maskDensity: 0.6,
            maskFeather: 12,
            mask: [
              MaskStroke(
                mode: MaskMode.hide,
                shape: MaskShape.fill,
                points: const [],
              ),
              MaskStroke(
                mode: MaskMode.show,
                shape: MaskShape.radial,
                points: const [Offset(1, 2), Offset(50, 60)],
                level: 0.25,
                opacity: 0.5,
              ),
            ],
          ),
          strokes: [
            BrushStroke(
              points: const [Offset(0, 0), Offset(10.5, 20)],
              type: BrushType.calligraphy,
              color: const Color(0xFFE53935),
              width: 9,
              opacity: 0.7,
              softness: 0.3,
              seed: 42,
            ),
            BrushStroke(points: const [Offset(5, 5)], eraser: true),
          ],
        ),
      ],
    );
    final (back, _) = PixoraFormat.documentFromXml(
      PixoraFormat.documentToXml(doc),
    );
    final d = back.layers.single as DrawingLayer;
    expect(d.strokes, (doc.layers.single as DrawingLayer).strokes);
    expect(d.props.maskDensity, 0.6);
    expect(d.props.maskFeather, 12);
    expect(d.props.mask, doc.layers.single.props.mask);
    expect(d.props.mask[1].value, 0.25);
  });

  test('mask grey values: value, invert and packing after fills', () {
    final e = EditorController(
      document: PixDocument(name: 'x', width: 300, height: 300),
    )..addShape(ShapeKind.ellipse, name: 's', color: Colors.blue);
    final id = e.selectedLayer!.id;
    e.addLayerMask(id);
    expect(e.selectedLayer!.props.hasMaskLayer, isTrue);
    e.addMaskStroke(
      id,
      MaskStroke(
        mode: MaskMode.hide,
        points: const [Offset.zero, Offset(10, 10)],
        level: 0.3,
      ),
    );
    e.invertMask(id);
    final inverted = e.selectedLayer!.props.mask;
    expect(inverted.first.shape, MaskShape.fill);
    expect(inverted.first.value, 0);
    expect(inverted.last.value, closeTo(0.7, 1e-9));
    // A full "Hide all" makes everything before it irrelevant.
    e.fillMask(id, 0);
    expect(e.selectedLayer!.props.mask.length, 1);
    e.clearMask(id);
    expect(e.selectedLayer!.props.hasMaskLayer, isFalse);
  });

  test('live brush strokes do not pile up between frames', () {
    final e = EditorController(
      document: PixDocument(name: 'x', width: 300, height: 300),
    );
    final l = e.addDrawing();
    for (var i = 1; i <= 5; i++) {
      e.addBrushStroke(
        l.id,
        BrushStroke(points: [for (var k = 0; k < i; k++) Offset(k * 5.0, 0)]),
        live: true,
      );
    }
    e.commit('draw');
    final d = e.document.layerById(l.id) as DrawingLayer;
    expect(d.strokes.length, 1);
    expect(d.strokes.single.points.length, 5);
    e.undo();
    expect((e.document.layerById(l.id) as DrawingLayer).strokes, isEmpty);
  });

  test('every brush and mask kind paints without errors', () {
    final r = ui.PictureRecorder();
    final c = Canvas(r);
    for (final t in BrushType.values) {
      paintBrushStroke(
        c,
        BrushStroke(
          points: const [Offset(0, 0), Offset(20, 5), Offset(40, 0)],
          type: t,
          opacity: 0.5,
          softness: 0.4,
        ),
      );
      paintBrushStroke(c, BrushStroke(points: const [Offset(3, 3)], type: t));
    }
    for (final s in MaskShape.values) {
      DocumentRenderer.paintMaskStroke(
        c,
        MaskStroke(
          mode: MaskMode.hide,
          shape: s,
          points: const [Offset(0, 0), Offset(10, 0), Offset(10, 10)],
          level: 0.4,
          opacity: 0.8,
          softness: 0.2,
        ),
        const Rect.fromLTWH(-50, -50, 100, 100),
      );
    }
    r.endRecording().dispose();
    final d = DrawingLayer(
      LayerProps(name: 'd'),
      strokes: [
        BrushStroke(points: const [Offset(-10, 0), Offset(30, 0)], width: 10),
      ],
    );
    final b = drawingRect(d);
    expect(b.left, lessThanOrEqualTo(-15));
    expect(b.right, greaterThanOrEqualTo(35));
  });
}

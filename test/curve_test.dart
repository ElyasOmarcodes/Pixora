import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixora/document/model/layer.dart';
import 'package:pixora/document/render/text_layout.dart';

TextLayer _text(double curve, {String text = 'السلام علیکم'}) => TextLayer(
  LayerProps(name: 't'),
  text: text,
  fontSize: 80,
  curve: curve,
);

void main() {
  test('curved text has a sensible, finite box', () {
    final flat = TextLayoutCache.instance.sizeOf(_text(0));
    for (final c in [30.0, 180.0, 360.0, -180.0]) {
      final s = TextLayoutCache.instance.sizeOf(_text(c));
      expect(s.width.isFinite && s.height.isFinite, isTrue, reason: '$c');
      expect(s.width, greaterThan(0));
      // Bending never makes the text wider than when straight.
      expect(s.width, lessThanOrEqualTo(flat.width + 1), reason: '$c');
    }
    final half = TextLayoutCache.instance.sizeOf(_text(180));
    expect(half.height, greaterThan(flat.height));
  });

  test('curved text paints (mesh + bitmap) at several zoom levels', () {
    final l = _text(180, text: 'Hello curved world');
    for (final scale in [0.25, 1.0, 3.0]) {
      final r = ui.PictureRecorder();
      final c = Canvas(r);
      expect(
        () => TextLayoutCache.instance.paint(c, l, scale),
        returnsNormally,
      );
      r.endRecording().dispose();
    }
  });
}

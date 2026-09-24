import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixora/document/model/fill.dart';
import 'package:pixora/document/model/layer.dart';
import 'package:pixora/document/render/text_layout.dart';

void main() {
  test(
    'a text gradient spans exactly the text (left red, right blue)',
    () async {
      final l = TextLayer(
        LayerProps(name: 't'),
        text: 'MMMMMMMM',
        fontSize: 40,
        fill: PixFill.gradient(FillKind.linear, const [
          Color(0xFFFF0000),
          Color(0xFF0000FF),
        ], angle: 0),
      );
      final size = TextLayoutCache.instance.fill(l).size;
      final w = (size.width + 40).ceil(), h = (size.height + 40).ceil();
      final rec = ui.PictureRecorder();
      final c = Canvas(rec)..translate(w / 2, h / 2);
      TextLayoutCache.instance.paint(c, l, 1);
      final img = await rec.endRecording().toImage(w, h);
      final data = (await img.toByteData())!;
      Color at(int x, int y) {
        final i = (y * w + x) * 4;
        return Color.fromARGB(
          data.getUint8(i + 3),
          data.getUint8(i),
          data.getUint8(i + 1),
          data.getUint8(i + 2),
        );
      }

      // Scan the middle row for the first and last painted pixels.
      final y = h ~/ 2;
      int? first, last;
      for (var x = 0; x < w; x++) {
        if (at(x, y).a > 0.9) {
          first ??= x;
          last = x;
        }
      }
      expect(first, isNotNull);
      final left = at(first! + 2, y), right = at(last! - 2, y);
      expect(left.r, greaterThan(0.8), reason: 'left edge should be red');
      expect(right.b, greaterThan(0.8), reason: 'right edge should be blue');
    },
  );
}

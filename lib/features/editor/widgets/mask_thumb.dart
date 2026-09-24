import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../document/model/layer.dart';
import '../../../document/render/document_renderer.dart';

/// A layer mask as Photoshop shows it: white = visible, black = hidden,
/// greys in between. A red cross marks a disabled mask.
class MaskThumb extends StatelessWidget {
  const MaskThumb({
    super.key,
    required this.layer,
    this.size = 40,
    this.selected = false,
  });
  final Layer layer;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 2.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: RepaintBoundary(
        child: CustomPaint(painter: _MaskThumbPainter(layer)),
      ),
    );
  }
}

class _MaskThumbPainter extends CustomPainter {
  _MaskThumbPainter(this.layer);
  final Layer layer;

  @override
  void paint(Canvas canvas, Size size) {
    final full = Offset.zero & size;
    canvas.drawRect(full, Paint()..color = Colors.black);
    final r = layerLocalRect(layer);
    if (r.isEmpty) return;
    final s = math.min(size.width / r.width, size.height / r.height);
    canvas
      ..save()
      ..translate(size.width / 2, size.height / 2)
      ..scale(s)
      ..translate(-r.center.dx, -r.center.dy)
      ..saveLayer(r, Paint());
    final p = layer.props;
    DocumentRenderer.paintMask(canvas, p.mask, r);
    canvas
      ..restore()
      ..restore();
    if (!p.maskEnabled) {
      final red = Paint()
        ..color = const Color(0xFFFF3B30)
        ..strokeWidth = 2.5;
      canvas
        ..drawLine(full.topLeft, full.bottomRight, red)
        ..drawLine(full.topRight, full.bottomLeft, red);
    }
  }

  @override
  bool shouldRepaint(_MaskThumbPainter old) =>
      old.layer.props.mask != layer.props.mask ||
      old.layer.props.maskEnabled != layer.props.maskEnabled;
}

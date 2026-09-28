import 'package:flutter/widgets.dart';

/// Paints the classic transparency checkerboard inside [rect].
void paintCheckerboard(
  Canvas canvas,
  Rect rect,
  Color a,
  Color b, {
  double cell = 12,
}) {
  // Only the cells that can be seen: a zoomed-in canvas is far bigger
  // than the screen, and drawing every cell made panning crawl.
  final visible = rect.intersect(canvas.getLocalClipBounds());
  if (visible.isEmpty) return;
  canvas.save();
  canvas.clipRect(visible);
  canvas.drawRect(visible, Paint()..color = a);
  final p = Paint()..color = b;
  final x0 = ((visible.left - rect.left) / cell).floor();
  final y0 = ((visible.top - rect.top) / cell).floor();
  final x1 = ((visible.right - rect.left) / cell).ceil();
  final y1 = ((visible.bottom - rect.top) / cell).ceil();
  for (var y = y0; y < y1; y++) {
    for (var x = x0 + ((x0 + y).isEven ? 1 : 0); x < x1; x += 2) {
      canvas.drawRect(
        Rect.fromLTWH(rect.left + x * cell, rect.top + y * cell, cell, cell),
        p,
      );
    }
  }
  canvas.restore();
}

class CheckerboardBox extends StatelessWidget {
  const CheckerboardBox({
    super.key,
    required this.a,
    required this.b,
    this.cell = 8,
  });
  final Color a;
  final Color b;
  final double cell;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _CheckerPainter(a, b, cell));
}

class _CheckerPainter extends CustomPainter {
  _CheckerPainter(this.a, this.b, this.cell);
  final Color a, b;
  final double cell;

  @override
  void paint(Canvas canvas, Size size) =>
      paintCheckerboard(canvas, Offset.zero & size, a, b, cell: cell);

  @override
  bool shouldRepaint(_CheckerPainter old) =>
      old.a != a || old.b != b || old.cell != cell;
}

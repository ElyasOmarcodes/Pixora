import 'package:flutter/widgets.dart';

/// Paints the classic transparency checkerboard inside [rect].
void paintCheckerboard(
  Canvas canvas,
  Rect rect,
  Color a,
  Color b, {
  double cell = 12,
}) {
  canvas.save();
  canvas.clipRect(rect);
  canvas.drawRect(rect, Paint()..color = a);
  final p = Paint()..color = b;
  final cols = (rect.width / cell).ceil();
  final rows = (rect.height / cell).ceil();
  for (var y = 0; y < rows; y++) {
    for (var x = (y.isOdd ? 1 : 0); x < cols; x += 2) {
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

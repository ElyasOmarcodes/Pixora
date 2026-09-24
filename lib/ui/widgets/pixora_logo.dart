import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The Pixora mark: a soft gradient tile with layered "pixel" panes forming a
/// P. Drawn in code so it is crisp at any size and needs no image assets.
class PixoraLogo extends StatelessWidget {
  const PixoraLogo({super.key, this.size = 64, this.accent});

  final double size;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final a = accent ?? Theme.of(context).colorScheme.primary;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _LogoPainter(a)),
    );
  }
}

class _LogoPainter extends CustomPainter {
  _LogoPainter(this.accent);
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final tile = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(s * 0.28),
    );
    final hsl = HSLColor.fromColor(accent);
    final c1 = hsl.withHue((hsl.hue + 330) % 360).withLightness(0.62).toColor();
    final c2 = hsl.withLightness(math.min(0.5, hsl.lightness)).toColor();
    canvas.drawRRect(
      tile,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c1, c2],
        ).createShader(Offset.zero & size),
    );

    // Back pane (a "layer" peeking out).
    final back = RRect.fromRectAndRadius(
      Rect.fromLTWH(s * 0.36, s * 0.22, s * 0.40, s * 0.40),
      Radius.circular(s * 0.12),
    );
    canvas.drawRRect(
      back,
      Paint()..color = Colors.white.withValues(alpha: 0.35),
    );

    // The P: bowl + stem.
    final white = Paint()..color = Colors.white;
    final small = Radius.circular(s * 0.075);
    final big = Radius.circular(s * 0.14);
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(s * 0.24, s * 0.30, s * 0.40, s * 0.36),
        topLeft: small,
        topRight: big,
        bottomRight: big,
      ),
      white,
    );
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(s * 0.24, s * 0.30, s * 0.15, s * 0.52),
        topLeft: small,
        bottomLeft: small,
        bottomRight: small,
      ),
      white,
    );
    // Counter (hole of the P).
    canvas.drawCircle(
      Offset(s * 0.465, s * 0.48),
      s * 0.065,
      Paint()..color = c2,
    );
  }

  @override
  bool shouldRepaint(_LogoPainter old) => old.accent != accent;
}

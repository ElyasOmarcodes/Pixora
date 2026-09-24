import 'dart:math' as math;

/// 4×5 color matrix helpers (row-major, the layout [ColorFilter.matrix]
/// expects). Offsets in the 5th column are in 0..255 units.
abstract final class ColorMatrix {
  static const List<double> identity = [
    1, 0, 0, 0, 0, //
    0, 1, 0, 0, 0, //
    0, 0, 1, 0, 0, //
    0, 0, 0, 1, 0, //
  ];

  static bool isIdentity(List<double> m) {
    for (var i = 0; i < 20; i++) {
      if ((m[i] - identity[i]).abs() > 1e-6) return false;
    }
    return true;
  }

  /// Returns the matrix that applies [a] first and then [b].
  static List<double> concat(List<double> a, List<double> b) {
    final out = List<double>.filled(20, 0);
    for (var r = 0; r < 4; r++) {
      for (var c = 0; c < 5; c++) {
        var v = 0.0;
        for (var k = 0; k < 4; k++) {
          v += b[r * 5 + k] * a[k * 5 + c];
        }
        if (c == 4) v += b[r * 5 + 4];
        out[r * 5 + c] = v;
      }
    }
    return out;
  }

  /// Linear interpolation between identity and [m] by [t] (0..1).
  static List<double> mixWithIdentity(List<double> m, double t) => [
    for (var i = 0; i < 20; i++) identity[i] + (m[i] - identity[i]) * t,
  ];

  /// [v] in -1..1.
  static List<double> brightness(double v) {
    final o = v * 255;
    return [1, 0, 0, 0, o, 0, 1, 0, 0, o, 0, 0, 1, 0, o, 0, 0, 0, 1, 0];
  }

  /// [v] in -1..1.
  static List<double> contrast(double v) {
    final s = v >= 0 ? 1 + v * 2 : 1 + v;
    final o = 128 * (1 - s);
    return [s, 0, 0, 0, o, 0, s, 0, 0, o, 0, 0, s, 0, o, 0, 0, 0, 1, 0];
  }

  /// [v] in -1..1 (-1 = grayscale).
  static List<double> saturation(double v) {
    final s = 1 + v;
    const lr = 0.2126, lg = 0.7152, lb = 0.0722;
    final sr = (1 - s) * lr, sg = (1 - s) * lg, sb = (1 - s) * lb;
    return [
      sr + s, sg, sb, 0, 0, //
      sr, sg + s, sb, 0, 0, //
      sr, sg, sb + s, 0, 0, //
      0, 0, 0, 1, 0, //
    ];
  }

  /// Hue rotation, [degrees] in -180..180.
  static List<double> hue(double degrees) {
    final a = degrees * math.pi / 180;
    final c = math.cos(a), s = math.sin(a);
    const lr = 0.213, lg = 0.715, lb = 0.072;
    return [
      lr + c * (1 - lr) + s * -lr, lg + c * -lg + s * -lg,
      lb + c * -lb + s * (1 - lb), 0, 0, //
      lr + c * -lr + s * 0.143, lg + c * (1 - lg) + s * 0.140,
      lb + c * -lb + s * -0.283, 0, 0, //
      lr + c * -lr + s * -(1 - lr), lg + c * -lg + s * lg,
      lb + c * (1 - lb) + s * lb, 0, 0, //
      0, 0, 0, 1, 0, //
    ];
  }

  /// Color temperature, [v] in -1 (cool) .. 1 (warm).
  static List<double> warmth(double v) {
    final r = 1 + v * 0.18, b = 1 - v * 0.18;
    return [r, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, b, 0, 0, 0, 0, 0, 1, 0];
  }

  /// Green↔magenta tint, [v] in -1..1.
  static List<double> tint(double v) {
    final g = 1 - v * 0.15;
    return [1, 0, 0, 0, 0, 0, g, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0];
  }

  static const List<double> grayscale = [
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0, 0, 0, 1, 0, //
  ];

  static const List<double> sepia = [
    0.393, 0.769, 0.189, 0, 0, //
    0.349, 0.686, 0.168, 0, 0, //
    0.272, 0.534, 0.131, 0, 0, //
    0, 0, 0, 1, 0, //
  ];

  static const List<double> invert = [
    -1, 0, 0, 0, 255, //
    0, -1, 0, 0, 255, //
    0, 0, -1, 0, 255, //
    0, 0, 0, 1, 0, //
  ];

  /// Lifts blacks / lowers whites, [v] in 0..1.
  static List<double> fade(double v) {
    final s = 1 - v * 0.35, o = v * 0.35 * 128;
    return [s, 0, 0, 0, o, 0, s, 0, 0, o, 0, 0, s, 0, o, 0, 0, 0, 1, 0];
  }
}

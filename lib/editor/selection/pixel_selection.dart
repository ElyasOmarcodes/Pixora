import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// How a new selection combines with the current one (Photoshop's
/// New / Add / Subtract / Intersect).
enum SelectionMode { replace, add, subtract, intersect }

/// A soft selection over the document: one coverage byte (0 = outside,
/// 255 = fully selected) per cell of a grid laid over the canvas.
///
/// The grid is the document scaled by [scale] (≤ 1), so big canvases stay
/// fast to edit. Every operation returns a new value; selections are
/// immutable so undo is just a list of them.
class PixelSelection {
  PixelSelection(this.width, this.height, this.scale, this.data)
    : assert(data.length == width * height);

  /// An empty selection sized for a [docWidth] × [docHeight] canvas.
  factory PixelSelection.empty(double docWidth, double docHeight) {
    final s = gridScale(docWidth, docHeight);
    final w = math.max(1, (docWidth * s).round());
    final h = math.max(1, (docHeight * s).round());
    return PixelSelection(w, h, s, Uint8List(w * h));
  }

  /// Longest grid side. Keeps pixel operations interactive on phones.
  static const int maxSide = 1600;

  /// Grid cells per document pixel for a canvas of that size.
  static double gridScale(double docWidth, double docHeight) =>
      math.min(1.0, maxSide / math.max(1.0, math.max(docWidth, docHeight)));

  final int width;
  final int height;

  /// Grid cells per document pixel.
  final double scale;

  /// Row-major coverage, `width × height` bytes.
  final Uint8List data;

  PixelSelection _with(Uint8List d) => PixelSelection(width, height, scale, d);

  bool get isEmpty {
    for (final v in data) {
      if (v != 0) return false;
    }
    return true;
  }

  bool get isNotEmpty => !isEmpty;

  /// Coverage 0..1 at a document point (0 outside the grid).
  double coverageAt(Offset doc) {
    final x = (doc.dx * scale).floor(), y = (doc.dy * scale).floor();
    if (x < 0 || y < 0 || x >= width || y >= height) return 0;
    return data[y * width + x] / 255;
  }

  /// Bounding box of every selected cell in grid cells, or null if empty.
  ({int left, int top, int right, int bottom})? get gridBounds {
    var l = width, t = height, r = -1, b = -1;
    for (var y = 0; y < height; y++) {
      final row = y * width;
      for (var x = 0; x < width; x++) {
        if (data[row + x] == 0) continue;
        if (x < l) l = x;
        if (x > r) r = x;
        if (y < t) t = y;
        if (y > b) b = y;
      }
    }
    if (r < 0) return null;
    return (left: l, top: t, right: r + 1, bottom: b + 1);
  }

  /// Bounding box in document pixels, or null if empty.
  Rect? get bounds {
    final g = gridBounds;
    if (g == null) return null;
    return Rect.fromLTRB(
      g.left / scale,
      g.top / scale,
      g.right / scale,
      g.bottom / scale,
    );
  }

  // ------------------------------------------------------------ combine

  /// Combines [next] (same grid) into this selection.
  PixelSelection combine(PixelSelection next, SelectionMode mode) {
    assert(next.width == width && next.height == height);
    final a = data, b = next.data;
    final out = Uint8List(a.length);
    switch (mode) {
      case SelectionMode.replace:
        out.setAll(0, b);
      case SelectionMode.add:
        for (var i = 0; i < out.length; i++) {
          out[i] = math.max(a[i], b[i]);
        }
      case SelectionMode.subtract:
        for (var i = 0; i < out.length; i++) {
          out[i] = (a[i] * (255 - b[i]) + 127) ~/ 255;
        }
      case SelectionMode.intersect:
        for (var i = 0; i < out.length; i++) {
          out[i] = (a[i] * b[i] + 127) ~/ 255;
        }
    }
    return _with(out);
  }

  PixelSelection all() =>
      _with(Uint8List(data.length)..fillRange(0, data.length, 255));

  PixelSelection inverted() {
    final out = Uint8List(data.length);
    for (var i = 0; i < out.length; i++) {
      out[i] = 255 - data[i];
    }
    return _with(out);
  }

  /// Converts a document-pixel distance to grid cells (at least 1).
  int cells(double docPixels) => math.max(1, (docPixels * scale).round());

  // ------------------------------------------------------------ modify

  /// Soft edge: three box blurs approximate a Gaussian of [radius] doc px.
  PixelSelection feathered(double radius) {
    if (radius <= 0) return this;
    final r = math.max(1, (cells(radius) / 1.7).round());
    var d = data;
    for (var i = 0; i < 3; i++) {
      d = _boxBlur(d, width, height, r);
    }
    return _with(d);
  }

  /// Grows (positive) or shrinks (negative) the selection by [radius] doc
  /// pixels (Photoshop's Expand / Contract).
  PixelSelection expanded(double radius) {
    if (radius == 0) return this;
    final r = cells(radius.abs());
    if (radius > 0) return _with(_dilate(data, width, height, r));
    // Contract = expand the outside.
    final inv = inverted();
    return _with(_dilate(inv.data, width, height, r)).inverted();
  }

  /// Rounds corners and removes specks (blur, then re-threshold with a
  /// thin anti-aliased edge).
  PixelSelection smoothed(double radius) {
    if (radius <= 0) return this;
    final r = cells(radius);
    final b = _boxBlur(_boxBlur(data, width, height, r), width, height, r);
    final out = Uint8List(b.length);
    for (var i = 0; i < b.length; i++) {
      out[i] = ((b[i] - 128) * 4 + 128).clamp(0, 255);
    }
    return _with(out);
  }

  /// White pixels whose alpha is the coverage (for images and overlays).
  Uint8List toRgba({bool invert = false}) {
    final out = Uint8List(data.length * 4);
    for (var i = 0, j = 0; i < data.length; i++, j += 4) {
      out[j] = 255;
      out[j + 1] = 255;
      out[j + 2] = 255;
      out[j + 3] = invert ? 255 - data[i] : data[i];
    }
    return out;
  }

  /// Takes the alpha channel of a `width × height` RGBA buffer.
  PixelSelection fromAlpha(Uint8List rgba) {
    final out = Uint8List(data.length);
    for (var i = 0; i < out.length; i++) {
      out[i] = rgba[i * 4 + 3];
    }
    return _with(out);
  }

  // ------------------------------------------------------------ pick

  /// Photoshop's Magic Wand on a `width × height` RGBA buffer: every cell
  /// whose colour is within [tolerance] (0..255, per channel) of the seed
  /// cell, either only those connected to it ([contiguous]) or all of them.
  PixelSelection magicWand(
    Uint8List rgba,
    Offset doc, {
    int tolerance = 32,
    bool contiguous = true,
  }) {
    final sx = (doc.dx * scale).floor(), sy = (doc.dy * scale).floor();
    final out = Uint8List(data.length);
    if (sx < 0 || sy < 0 || sx >= width || sy >= height) return _with(out);
    final seed = (sy * width + sx) * 4;
    final r0 = rgba[seed], g0 = rgba[seed + 1], b0 = rgba[seed + 2];
    final a0 = rgba[seed + 3];
    bool match(int i) {
      final j = i * 4;
      final a = rgba[j + 3];
      if ((a - a0).abs() > tolerance) return false;
      // Fully transparent cells match each other whatever their colour.
      if (a == 0 && a0 == 0) return true;
      return (rgba[j] - r0).abs() <= tolerance &&
          (rgba[j + 1] - g0).abs() <= tolerance &&
          (rgba[j + 2] - b0).abs() <= tolerance;
    }

    if (!contiguous) {
      for (var i = 0; i < out.length; i++) {
        if (match(i)) out[i] = 255;
      }
      return _with(out);
    }
    // Scanline flood fill.
    final stack = <int>[sy * width + sx];
    while (stack.isNotEmpty) {
      final i = stack.removeLast();
      if (out[i] != 0 || !match(i)) continue;
      final y = i ~/ width, row = y * width;
      var l = i - row, r = l;
      while (l > 0 && out[row + l - 1] == 0 && match(row + l - 1)) {
        l--;
      }
      while (r < width - 1 && out[row + r + 1] == 0 && match(row + r + 1)) {
        r++;
      }
      for (var x = l; x <= r; x++) {
        out[row + x] = 255;
        if (y > 0 && out[row - width + x] == 0) stack.add(row - width + x);
        if (y < height - 1 && out[row + width + x] == 0) {
          stack.add(row + width + x);
        }
      }
    }
    return _with(out);
  }

  /// Photoshop's Color Range: cells close to [color] are selected, fading
  /// out as the difference approaches [fuzziness] (0..255).
  PixelSelection colorRange(Uint8List rgba, Color color, {int fuzziness = 40}) {
    final out = Uint8List(data.length);
    final r0 = (color.r * 255).round(), g0 = (color.g * 255).round();
    final b0 = (color.b * 255).round();
    final f = math.max(1, fuzziness);
    for (var i = 0; i < out.length; i++) {
      final j = i * 4;
      final a = rgba[j + 3];
      if (a == 0) continue;
      final d = math.max(
        (rgba[j] - r0).abs(),
        math.max((rgba[j + 1] - g0).abs(), (rgba[j + 2] - b0).abs()),
      );
      double v;
      if (d <= f / 2) {
        v = 1;
      } else if (d >= f) {
        v = 0;
      } else {
        v = 1 - (d - f / 2) / (f / 2);
      }
      out[i] = (v * a).round();
    }
    return _with(out);
  }

  /// Selects by brightness: full inside [from]..[to] (0..1 luminance),
  /// fading over [softness] on both sides. Shadows ≈ 0..0.3,
  /// midtones ≈ 0.35..0.65, highlights ≈ 0.7..1.
  PixelSelection luminanceRange(
    Uint8List rgba, {
    double from = 0.7,
    double to = 1,
    double softness = 0.1,
  }) {
    final out = Uint8List(data.length);
    final lo = math.min(from, to), hi = math.max(from, to);
    final s = math.max(0.001, softness);
    for (var i = 0; i < out.length; i++) {
      final j = i * 4;
      final a = rgba[j + 3];
      if (a == 0) continue;
      final y =
          (0.2126 * rgba[j] + 0.7152 * rgba[j + 1] + 0.0722 * rgba[j + 2]) /
          255;
      double v;
      if (y >= lo && y <= hi) {
        v = 1;
      } else if (y < lo) {
        v = math.max(0, 1 - (lo - y) / s);
      } else {
        v = math.max(0, 1 - (y - hi) / s);
      }
      out[i] = (v * a).round();
    }
    return _with(out);
  }

  // ------------------------------------------------------------ outline

  /// The selection edge (coverage ≥ 50%) as horizontal and vertical
  /// segments in document space, for marching ants. Large grids are
  /// sampled coarser so the path stays light.
  Path outline({int maxCells = 700}) {
    final step = math.max(1, (math.max(width, height) / maxCells).ceil());
    final w = (width / step).ceil(), h = (height / step).ceil();
    bool inside(int x, int y) {
      if (x < 0 || y < 0 || x >= w || y >= h) return false;
      final gx = math.min(width - 1, x * step + step ~/ 2);
      final gy = math.min(height - 1, y * step + step ~/ 2);
      return data[gy * width + gx] >= 128;
    }

    final k = step / scale;
    final path = Path();
    // Horizontal edges between rows y-1 and y.
    for (var y = 0; y <= h; y++) {
      var start = -1;
      for (var x = 0; x <= w; x++) {
        final edge = x < w && inside(x, y) != inside(x, y - 1);
        if (edge && start < 0) start = x;
        if (!edge && start >= 0) {
          path
            ..moveTo(start * k, y * k)
            ..lineTo(x * k, y * k);
          start = -1;
        }
      }
    }
    // Vertical edges between columns x-1 and x.
    for (var x = 0; x <= w; x++) {
      var start = -1;
      for (var y = 0; y <= h; y++) {
        final edge = y < h && inside(x, y) != inside(x - 1, y);
        if (edge && start < 0) start = y;
        if (!edge && start >= 0) {
          path
            ..moveTo(x * k, start * k)
            ..lineTo(x * k, y * k);
          start = -1;
        }
      }
    }
    return path;
  }
}

/// Separable box blur of radius [r] with edge clamping.
Uint8List _boxBlur(Uint8List src, int w, int h, int r) {
  final tmp = Uint8List(src.length);
  final out = Uint8List(src.length);
  final n = 2 * r + 1;
  for (var y = 0; y < h; y++) {
    final row = y * w;
    var sum = 0;
    for (var k = -r; k <= r; k++) {
      sum += src[row + k.clamp(0, w - 1)];
    }
    for (var x = 0; x < w; x++) {
      tmp[row + x] = sum ~/ n;
      sum +=
          src[row + math.min(w - 1, x + r + 1)] - src[row + math.max(0, x - r)];
    }
  }
  for (var x = 0; x < w; x++) {
    var sum = 0;
    for (var k = -r; k <= r; k++) {
      sum += tmp[k.clamp(0, h - 1) * w + x];
    }
    for (var y = 0; y < h; y++) {
      out[y * w + x] = sum ~/ n;
      sum +=
          tmp[math.min(h - 1, y + r + 1) * w + x] -
          tmp[math.max(0, y - r) * w + x];
    }
  }
  return out;
}

/// Separable max filter (square of radius [r]) using a monotonic deque,
/// O(pixels) whatever the radius.
Uint8List _dilate(Uint8List src, int w, int h, int r) {
  Uint8List pass(Uint8List s, int len, int count, int stride, int step) {
    final out = Uint8List(s.length);
    final dq = Int32List(len);
    for (var c = 0; c < count; c++) {
      final base = c * stride;
      var head = 0, tail = 0;
      var next = 0; // next index to push
      for (var i = 0; i < len; i++) {
        final hi = math.min(len - 1, i + r);
        while (next <= hi) {
          final v = s[base + next * step];
          while (tail > head && s[base + dq[tail - 1] * step] <= v) {
            tail--;
          }
          dq[tail++] = next++;
        }
        while (dq[head] < i - r) {
          head++;
        }
        out[base + i * step] = s[base + dq[head] * step];
      }
    }
    return out;
  }

  final rows = pass(src, w, h, w, 1);
  return pass(rows, h, w, 1, w);
}

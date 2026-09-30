import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

/// Image ▸ Adjustments ▸ Curves and Levels, as Photoshop computes them:
/// each becomes a 256-entry lookup table per channel (the composite RGB
/// curve or levels applied after the channel's own).
enum ToneChannel { rgb, red, green, blue }

extension ToneChannelKey on ToneChannel {
  /// Short key used in effect params.
  String get key => switch (this) {
    ToneChannel.rgb => 'rgb',
    ToneChannel.red => 'r',
    ToneChannel.green => 'g',
    ToneChannel.blue => 'b',
  };
}

/// Photoshop's Curves: up to 14 points per channel (input → output,
/// 0..255), joined by a natural cubic spline; beyond the end points the
/// curve stays flat.
class ToneCurves {
  ToneCurves(Map<ToneChannel, List<Offset>> points)
    : points = {
        for (final c in ToneChannel.values) c: _sorted(points[c] ?? identity),
      };

  static const identity = [Offset(0, 0), Offset(255, 255)];
  static const maxPoints = 14;

  final Map<ToneChannel, List<Offset>> points;

  static List<Offset> _sorted(List<Offset> p) {
    final list = [
      for (final o in p) Offset(o.dx.clamp(0.0, 255.0), o.dy.clamp(0.0, 255.0)),
    ]..sort((a, b) => a.dx.compareTo(b.dx));
    // Photoshop keeps inputs apart; drop duplicates.
    final out = <Offset>[];
    for (final o in list) {
      if (out.isEmpty || (o.dx - out.last.dx).abs() >= 1) out.add(o);
    }
    return out.length >= 2 ? out : identity;
  }

  bool get isIdentity => points.values.every(_isStraight);

  static bool _isStraight(List<Offset> p) =>
      p.every((o) => (o.dx - o.dy).abs() < 0.5) &&
      p.first.dx <= 0.5 &&
      p.last.dx >= 254.5;

  /// "rgb:0,0 128,150 255,255;r:…" — compact and readable in the file.
  String encode() => [
    for (final c in ToneChannel.values)
      if (!_isStraight(points[c]!) || c == ToneChannel.rgb)
        '${c.key}:${points[c]!.map((o) => '${o.dx.round()},${o.dy.round()}').join(' ')}',
  ].join(';');

  static ToneCurves decode(String? s) {
    final map = <ToneChannel, List<Offset>>{};
    if (s != null) {
      for (final part in s.split(';')) {
        final i = part.indexOf(':');
        if (i <= 0) continue;
        final key = part.substring(0, i).trim();
        final ch = ToneChannel.values.where((c) => c.key == key);
        if (ch.isEmpty) continue;
        final pts = <Offset>[];
        for (final xy in part.substring(i + 1).trim().split(RegExp(r'\s+'))) {
          final v = xy.split(',');
          if (v.length != 2) continue;
          final x = double.tryParse(v[0]), y = double.tryParse(v[1]);
          if (x != null && y != null) pts.add(Offset(x, y));
        }
        map[ch.first] = pts;
      }
    }
    return ToneCurves(map);
  }

  ToneCurves withChannel(ToneChannel c, List<Offset> p) =>
      ToneCurves({...points, c: p});

  /// The channel's curve sampled at every input level.
  static Float64List sample(List<Offset> p) => _spline(p);

  /// Interleaved R, G, B tables (768 bytes).
  Uint8List lut() {
    final master = _spline(points[ToneChannel.rgb]!);
    final out = Uint8List(768);
    for (var k = 0; k < 3; k++) {
      final ch = _spline(points[ToneChannel.values[k + 1]]!);
      for (var i = 0; i < 256; i++) {
        final v = ch[i].round().clamp(0, 255);
        out[i * 3 + k] = master[v].round().clamp(0, 255);
      }
    }
    return out;
  }

  /// A natural cubic spline through [p] (sorted), flat outside it.
  static Float64List _spline(List<Offset> p) {
    final out = Float64List(256);
    final n = p.length;
    if (n == 2) {
      final a = p[0], b = p[1];
      for (var i = 0; i < 256; i++) {
        final x = i.toDouble();
        out[i] = x <= a.dx
            ? a.dy
            : x >= b.dx
            ? b.dy
            : a.dy + (b.dy - a.dy) * (x - a.dx) / (b.dx - a.dx);
      }
      return out;
    }
    // Second derivatives (tridiagonal solve).
    final xs = [for (final o in p) o.dx], ys = [for (final o in p) o.dy];
    final y2 = List<double>.filled(n, 0), u = List<double>.filled(n, 0);
    for (var i = 1; i < n - 1; i++) {
      final sig = (xs[i] - xs[i - 1]) / (xs[i + 1] - xs[i - 1]);
      final q = sig * y2[i - 1] + 2;
      y2[i] = (sig - 1) / q;
      final d =
          (ys[i + 1] - ys[i]) / (xs[i + 1] - xs[i]) -
          (ys[i] - ys[i - 1]) / (xs[i] - xs[i - 1]);
      u[i] = (6 * d / (xs[i + 1] - xs[i - 1]) - sig * u[i - 1]) / q;
    }
    for (var k = n - 2; k >= 0; k--) {
      y2[k] = y2[k] * y2[k + 1] + u[k];
    }
    var seg = 0;
    for (var i = 0; i < 256; i++) {
      final x = i.toDouble();
      if (x <= xs.first) {
        out[i] = ys.first;
        continue;
      }
      if (x >= xs.last) {
        out[i] = ys.last;
        continue;
      }
      while (seg < n - 2 && x > xs[seg + 1]) {
        seg++;
      }
      final h = xs[seg + 1] - xs[seg];
      final a = (xs[seg + 1] - x) / h, b = (x - xs[seg]) / h;
      out[i] =
          a * ys[seg] +
          b * ys[seg + 1] +
          ((a * a * a - a) * y2[seg] + (b * b * b - b) * y2[seg + 1]) *
              h *
              h /
              6;
    }
    for (var i = 0; i < 256; i++) {
      out[i] = out[i].clamp(0.0, 255.0);
    }
    return out;
  }

  /// Photoshop's Curves presets.
  static const presets = <String, String>{
    'default': 'rgb:0,0 255,255',
    'colorNegative':
        'r:0,255 102,153 255,0;g:0,255 106,143 255,0;b:0,255 116,125 255,0',
    'crossProcess': 'r:0,0 88,47 170,188 221,249 255,255;g:0,0 65,57 184,208 255,255;b:0,29 255,226',
    'darker': 'rgb:0,0 145,114 255,255',
    'increaseContrast': 'rgb:0,0 62,50 193,207 255,255',
    'lighter': 'rgb:0,0 109,143 255,255',
    'linearContrast': 'rgb:0,0 63,52 191,202 255,255',
    'mediumContrast': 'rgb:0,0 50,35 205,220 255,255',
    'negative': 'rgb:0,255 255,0',
    'strongContrast': 'rgb:0,0 63,39 191,214 255,255',
  };
}

/// Photoshop's Levels for one channel: input black / white points, the
/// midtone gamma (0.01–9.99, 1 = unchanged) and output black / white.
class LevelsChannel {
  const LevelsChannel({
    this.inBlack = 0,
    this.inWhite = 255,
    this.gamma = 1,
    this.outBlack = 0,
    this.outWhite = 255,
  });
  final double inBlack, inWhite, gamma, outBlack, outWhite;

  bool get isIdentity =>
      inBlack <= 0 &&
      inWhite >= 255 &&
      (gamma - 1).abs() < 1e-3 &&
      outBlack <= 0 &&
      outWhite >= 255;

  double apply(double v) {
    final span = math.max(1.0, inWhite - inBlack);
    var t = ((v - inBlack) / span).clamp(0.0, 1.0);
    t = math.pow(t, 1 / gamma.clamp(0.01, 9.99)).toDouble();
    return outBlack + t * (outWhite - outBlack);
  }

  /// Where the grey (midtone) slider sits, 0..1 between the input points.
  double get midPosition => math.pow(0.5, gamma.clamp(0.01, 9.99)).toDouble();

  /// The gamma for a grey slider at [pos] (0..1 between the input points).
  static double gammaFor(double pos) {
    final p = pos.clamp(0.001, 0.999);
    return (math.log(p) / math.log(0.5)).clamp(0.01, 9.99);
  }
}

class ToneLevels {
  ToneLevels(this.channels);
  final Map<ToneChannel, LevelsChannel> channels;

  static const _fields = [
    'inBlack',
    'inWhite',
    'gamma',
    'outBlack',
    'outWhite',
  ];

  /// Effect param keys: `rgbInBlack`, `rGamma`, …
  static String param(ToneChannel c, String field) =>
      '${c.key}${field[0].toUpperCase()}${field.substring(1)}';

  static Iterable<String> get allParams => [
    for (final c in ToneChannel.values)
      for (final f in _fields) param(c, f),
  ];

  static double defaultOf(String field) => switch (field) {
    'inWhite' || 'outWhite' => 255,
    'gamma' => 1,
    _ => 0,
  };

  factory ToneLevels.read(double Function(String key, double fallback) n) =>
      ToneLevels({
        for (final c in ToneChannel.values)
          c: LevelsChannel(
            inBlack: n(param(c, 'inBlack'), 0),
            inWhite: n(param(c, 'inWhite'), 255),
            gamma: n(param(c, 'gamma'), 1),
            outBlack: n(param(c, 'outBlack'), 0),
            outWhite: n(param(c, 'outWhite'), 255),
          ),
      });

  bool get isIdentity => channels.values.every((c) => c.isIdentity);

  Uint8List lut() {
    final master = channels[ToneChannel.rgb]!;
    final out = Uint8List(768);
    for (var k = 0; k < 3; k++) {
      final ch = channels[ToneChannel.values[k + 1]]!;
      for (var i = 0; i < 256; i++) {
        final v = ch.apply(i.toDouble());
        out[i * 3 + k] = master.apply(v).round().clamp(0, 255);
      }
    }
    return out;
  }

  /// Photoshop's Levels presets (composite channel): black, grey, white
  /// input and output black, white.
  static const presets = <String, (double, double, double, double, double)>{
    'default': (0, 1, 255, 0, 255),
    'darker': (15, 1, 255, 0, 230),
    'increaseContrast1': (10, 1, 245, 0, 255),
    'increaseContrast2': (20, 1, 235, 0, 255),
    'increaseContrast3': (30, 1, 225, 0, 255),
    'lightenShadows': (0, 1.6, 255, 0, 255),
    'lighter': (0, 1, 230, 25, 255),
    'midtonesBrighter': (0, 1.25, 255, 0, 255),
    'midtonesDarker': (0, 0.75, 255, 0, 255),
  };

  /// Auto Contrast: clip 0.1 % of the darkest and lightest pixels of the
  /// luminance [histogram] (256 bins) — Photoshop's default.
  static (double, double) autoPoints(List<int> histogram) {
    final total = histogram.fold(0, (a, b) => a + b);
    if (total == 0) return (0, 255);
    final clip = total * 0.001;
    var acc = 0.0, lo = 0, hi = 255;
    for (var i = 0; i < 256; i++) {
      acc += histogram[i];
      if (acc > clip) {
        lo = i;
        break;
      }
    }
    acc = 0;
    for (var i = 255; i >= 0; i--) {
      acc += histogram[i];
      if (acc > clip) {
        hi = i;
        break;
      }
    }
    if (hi - lo < 2) return (0, 255);
    return (lo.toDouble(), hi.toDouble());
  }
}

/// Counts of each level (256 bins) for red, green, blue and luminosity,
/// alpha-weighted, from premultiplied RGBA pixels.
class ToneHistogram {
  ToneHistogram(this.red, this.green, this.blue, this.luminosity);
  final List<int> red, green, blue, luminosity;

  factory ToneHistogram.fromRgba(Uint8List px) {
    final r = List<int>.filled(256, 0), g = List<int>.filled(256, 0);
    final b = List<int>.filled(256, 0), l = List<int>.filled(256, 0);
    for (var i = 0; i + 3 < px.length; i += 4) {
      final a = px[i + 3];
      if (a < 8) continue;
      final rr = (px[i] * 255 / a).round().clamp(0, 255);
      final gg = (px[i + 1] * 255 / a).round().clamp(0, 255);
      final bb = (px[i + 2] * 255 / a).round().clamp(0, 255);
      r[rr]++;
      g[gg]++;
      b[bb]++;
      l[(0.3 * rr + 0.59 * gg + 0.11 * bb).round().clamp(0, 255)]++;
    }
    return ToneHistogram(r, g, b, l);
  }

  List<int> of(ToneChannel c) => switch (c) {
    ToneChannel.rgb => luminosity,
    ToneChannel.red => red,
    ToneChannel.green => green,
    ToneChannel.blue => blue,
  };
}

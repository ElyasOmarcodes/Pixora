import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../model/layer.dart';
import '../model/text_span_style.dart';

/// Detects the base direction from the first strong character, so Pashto,
/// Dari/Persian, Arabic and Urdu text is laid out right-to-left automatically.
TextDirection detectTextDirection(String text) {
  for (final rune in text.runes) {
    if (_isRtl(rune)) return TextDirection.rtl;
    if (_isLtrStrong(rune)) return TextDirection.ltr;
  }
  return TextDirection.ltr;
}

bool _isRtl(int c) =>
    (c >= 0x0590 && c <= 0x08FF) ||
    (c >= 0xFB1D && c <= 0xFDFF) ||
    (c >= 0xFE70 && c <= 0xFEFF);

bool _isLtrStrong(int c) =>
    (c >= 0x41 && c <= 0x5A) ||
    (c >= 0x61 && c <= 0x7A) ||
    (c >= 0xC0 && c <= 0x24F) ||
    (c >= 0x370 && c <= 0x58F) ||
    (c >= 0x3040 && c <= 0x9FFF);

/// Lays out text layers and caches the result.
///
/// Both the renderer and hit-testing need the laid-out size of a text layer;
/// caching by content keeps dragging and repainting smooth.
class TextLayoutCache {
  TextLayoutCache._();
  static final TextLayoutCache instance = TextLayoutCache._();

  static const _maxEntries = 64;
  final LinkedHashMap<int, TextLayoutEntry> _cache = LinkedHashMap();

  /// Bumped whenever cached layouts become stale (a font finished
  /// loading), so bitmap caches built from them are rebuilt too.
  static int generation = 0;

  /// Forgets all layouts (e.g. after a font finished loading).
  void clear() {
    _cache.clear();
    generation++;
  }

  /// Padding around glyphs so strokes and italics are not clipped.
  static double paddingFor(TextLayer l) =>
      l.strokeWidth / 2 + l.fontSize * 0.08;

  TextPainter fill(TextLayer l) => entry(l).fill;
  TextPainter? stroke(TextLayer l) => entry(l).stroke;

  /// Size of the layer's local box (text, padding and background).
  Size sizeOf(TextLayer l) => entry(l).size;

  /// Paints [l] centred on the canvas origin.
  void paint(Canvas canvas, TextLayer l, [double pixelScale = 2]) =>
      entry(l).paint(canvas, pixelScale);

  TextLayoutEntry entry(TextLayer l) {
    final key = Object.hash(
      Object.hash(
        l.text,
        l.fontFamily,
        l.fontSize,
        l.fontWeight,
        l.italic,
        l.fill,
        l.align,
        l.letterSpacing,
        l.lineHeight,
        l.strokeWidth,
        l.strokeColor,
        l.underline,
        l.boxWidth,
      ),
      l.strike,
      l.textCase,
      l.wordSpacing,
      l.curve,
      l.background,
      l.bgPadX,
      l.bgPadY,
      l.bgRadius,
      Object.hashAll(l.spans),
    );
    final hit = _cache.remove(key);
    if (hit != null) {
      _cache[key] = hit;
      return hit;
    }
    final entry = TextLayoutEntry._build(l);
    _cache[key] = entry;
    if (_cache.length > _maxEntries) {
      // Not disposed eagerly: a painter handed out earlier in the current
      // frame may still be in use. The GC reclaims it.
      _cache.remove(_cache.keys.first);
    }
    return entry;
  }
}

/// Curved text: the straight layout is rendered once into a bitmap and
/// drawn bent over a triangle strip that follows concentric arcs. Every
/// glyph bends continuously (no seams or gaps, Arabic-script joins stay
/// intact) and the bitmap is reused until the zoom level doubles/halves.
class _CurveMesh {
  _CurveMesh({required this.source, required this.positions, required this.xs});

  /// Straight-layout area that is bent (text box plus padding).
  final Rect source;

  /// Triangle strip, top/bottom pairs, relative to the layer centre.
  final Float32List positions;

  /// Straight x of every column (relative to [source.left]).
  final List<double> xs;

  double? _scale;
  ui.Image? _image;
  ui.Vertices? _vertices;

  void paint(Canvas canvas, double pixelScale, void Function(Canvas) draw) {
    var bucket = 1.0;
    // Oversampled: the bitmap is resampled once more when bent.
    final want = (pixelScale * 1.5).clamp(1 / 16, 16.0);
    while (bucket < want) {
      bucket *= 2;
    }
    while (bucket / 2 >= want) {
      bucket /= 2;
    }
    final longest = math.max(source.width, source.height);
    final s = math.min(bucket, 4096 / longest);
    if (_scale != s || _image == null) {
      final w = math.max(1, (source.width * s).ceil());
      final h = math.max(1, (source.height * s).ceil());
      final recorder = ui.PictureRecorder();
      final c = Canvas(recorder)
        ..scale(w / source.width, h / source.height)
        ..translate(-source.left, -source.top);
      draw(c);
      final picture = recorder.endRecording();
      _image = picture.toImageSync(w, h);
      picture.dispose();
      final tex = Float32List(xs.length * 4);
      final kx = w / source.width;
      for (var i = 0; i < xs.length; i++) {
        tex[i * 4] = xs[i] * kx;
        tex[i * 4 + 1] = 0;
        tex[i * 4 + 2] = xs[i] * kx;
        tex[i * 4 + 3] = h.toDouble();
      }
      _vertices = ui.Vertices.raw(
        ui.VertexMode.triangleStrip,
        positions,
        textureCoordinates: tex,
      );
      _scale = s;
    }
    canvas.drawVertices(
      _vertices!,
      BlendMode.srcOver,
      Paint()
        ..isAntiAlias = true
        ..shader = ImageShader(
          _image!,
          TileMode.clamp,
          TileMode.clamp,
          Float64List.fromList([
            1,
            0,
            0,
            0,
            0,
            1,
            0,
            0,
            0,
            0,
            1,
            0,
            0,
            0,
            0,
            1,
          ]),
          filterQuality: FilterQuality.medium,
        ),
    );
  }
}

/// Builds the paragraph: the base style for the whole text plus child
/// spans for ranges with their own font or colour. The stroke pass only
/// takes fonts (the outline keeps its own colour).
InlineSpan _spanTree(
  String text,
  TextStyle base,
  List<TextSpanStyle> spans, {
  required bool stroke,
  required bool foreground,
}) {
  if (spans.isEmpty) return TextSpan(text: text, style: base);
  final children = <InlineSpan>[];
  var cursor = 0;
  for (final s in spans) {
    final a = s.start.clamp(0, text.length), b = s.end.clamp(0, text.length);
    if (b <= a || a < cursor) continue;
    if (a > cursor) children.add(TextSpan(text: text.substring(cursor, a)));
    final c = stroke ? null : s.color;
    children.add(
      TextSpan(
        text: text.substring(a, b),
        style: TextStyle(
          fontFamily: s.fontFamily == 'System' ? null : s.fontFamily,
          // A gradient base paints with `foreground`; a span colour then
          // has to be a foreground paint too (both can't be set).
          color: c != null && !foreground ? c : null,
          foreground: c != null && foreground ? (Paint()..color = c) : null,
          decorationColor: c,
        ),
      ),
    );
    cursor = b;
  }
  if (cursor < text.length) {
    children.add(TextSpan(text: text.substring(cursor)));
  }
  return TextSpan(style: base, children: children);
}

class TextLayoutEntry {
  TextLayoutEntry._(this.layer, this.fill, this.stroke, this.size, this._mesh);

  final TextLayer layer;
  final TextPainter fill;
  final TextPainter? stroke;

  /// Local box size (centred on the origin).
  final Size size;
  final _CurveMesh? _mesh;

  static TextLayoutEntry _build(TextLayer l) {
    final text = l.displayText;
    final dir = detectTextDirection(text);
    final align = switch (l.align) {
      PixTextAlign.start => TextAlign.start,
      PixTextAlign.center => TextAlign.center,
      PixTextAlign.end => TextAlign.end,
      PixTextAlign.justify => TextAlign.justify,
    };
    final decorations = [
      if (l.underline) TextDecoration.underline,
      if (l.strike) TextDecoration.lineThrough,
    ];
    TextStyle style(Paint? foreground) => TextStyle(
      fontFamily: l.fontFamily == 'System' ? null : l.fontFamily,
      // Letters missing from the chosen font (Pashto ګ ښ ځ ډ …).
      fontFamilyFallback: const ['Vazirmatn', 'Noto Naskh Arabic'],
      fontSize: l.fontSize,
      fontWeight: FontWeight.values[((l.fontWeight ~/ 100) - 1).clamp(0, 8)],
      fontVariations: [FontVariation('wght', l.fontWeight.toDouble())],
      fontStyle: l.italic ? FontStyle.italic : FontStyle.normal,
      letterSpacing: l.letterSpacing,
      wordSpacing: l.wordSpacing,
      height: l.lineHeight,
      decoration: decorations.isEmpty
          ? null
          : TextDecoration.combine(decorations),
      decorationColor: l.fill.primary,
      decorationThickness: 1.4,
      foreground: foreground,
      color: foreground == null ? l.fill.primary : null,
    );

    TextPainter make(Paint? fg, {bool stroke = false}) =>
        TextPainter(
          text: _spanTree(
            text.isEmpty ? ' ' : text,
            style(fg),
            l.spans,
            stroke: stroke,
            foreground: fg != null,
          ),
          textDirection: dir,
          textAlign: align,
        )..layout(
          minWidth: l.boxWidth ?? 0,
          maxWidth: l.boxWidth ?? double.infinity,
        );

    // Gradient fills need the laid-out size first, so lay out once plainly.
    var fill = make(null);
    if (l.fill.isGradient) {
      final rect = Offset.zero & fill.size;
      fill.dispose();
      fill = make(l.fill.applyTo(Paint(), rect));
    }
    TextPainter? stroke;
    if (l.strokeWidth > 0) {
      stroke = make(
        Paint()
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = l.strokeWidth
          ..strokeJoin = ui.StrokeJoin.round
          ..color = l.strokeColor,
        stroke: true,
      );
    }

    final pad = TextLayoutCache.paddingFor(l);
    final bgPad = l.background == null
        ? Size.zero
        : Size(l.bgPadX * l.fontSize, l.bgPadY * l.fontSize);

    if (l.curve.abs() < 0.5 || fill.width <= 0) {
      final w = fill.width + 2 * math.max(pad, bgPad.width);
      final h = fill.height + 2 * math.max(pad, bgPad.height);
      return TextLayoutEntry._(l, fill, stroke, Size(w, h), null);
    }

    // Curved: map the straight layout onto concentric arcs. A point at
    // (dx, dy) from the centre goes to angle dx / r0 on radius r0 - dy.
    final w = fill.width, h = fill.height;
    final sign = l.curve.sign;
    final r0 = w / (l.curve.abs() * math.pi / 180);
    Offset map(double x, double y) {
      final theta = (x - w / 2) / r0;
      final r = math.max(0.0, r0 - sign * (y - h / 2));
      return Offset(
        r * math.sin(theta),
        sign * r0 - sign * r * math.cos(theta),
      );
    }

    // Room for strokes, italics and diacritics outside the line boxes.
    final padX = pad + l.fontSize * 0.1;
    final padY = pad + l.fontSize * 0.35;
    final source = Rect.fromLTRB(-padX, -padY, w + padX, h + padY);
    // One column per degree (or finer for small, strongly bent text).
    final sweep = source.width / r0 * 180 / math.pi;
    final n = sweep.ceil().clamp(4, 720);
    final xs = <double>[];
    final pos = Float32List((n + 1) * 4);
    var bounds = Rect.zero;
    var first = true;
    final lines = fill.computeLineMetrics();
    var gTop = 0.0, gBottom = h;
    if (lines.isNotEmpty) {
      gTop = lines.first.baseline - lines.first.ascent - pad;
      gBottom = lines.last.baseline + lines.last.descent + pad;
    }
    for (var i = 0; i <= n; i++) {
      final x = source.left + source.width * i / n;
      xs.add(x - source.left);
      final t = map(x, source.top), b = map(x, source.bottom);
      pos[i * 4] = t.dx;
      pos[i * 4 + 1] = t.dy;
      pos[i * 4 + 2] = b.dx;
      pos[i * 4 + 3] = b.dy;
      if (x < -pad || x > w + pad) continue;
      for (final p in [map(x, gTop), map(x, gBottom)]) {
        final pr = Rect.fromLTRB(p.dx, p.dy, p.dx, p.dy);
        bounds = first ? pr : bounds.expandToInclude(pr);
        first = false;
      }
    }
    // Centre the bent text on the layer origin.
    final c = bounds.center;
    for (var i = 0; i < pos.length; i += 2) {
      pos[i] -= c.dx;
      pos[i + 1] -= c.dy;
    }
    final size = Size(
      bounds.width + 2 * math.max(pad, bgPad.width),
      bounds.height + 2 * math.max(pad, bgPad.height),
    );
    return TextLayoutEntry._(
      l,
      fill,
      stroke,
      size,
      _CurveMesh(source: source, positions: pos, xs: xs),
    );
  }

  /// [pixelScale]: device pixels per local unit (sharpness of curves).
  void paint(Canvas canvas, [double pixelScale = 2]) {
    final l = layer;
    final bg = l.background;
    if (bg != null) {
      final rect = Rect.fromCenter(
        center: Offset.zero,
        width: size.width,
        height: size.height,
      );
      final radius = math.min(l.bgRadius * l.fontSize, rect.shortestSide / 2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(radius)),
        bg.applyTo(Paint()..isAntiAlias = true, rect),
      );
    }
    final mesh = _mesh;
    if (mesh == null) {
      final origin = Offset(-fill.width / 2, -fill.height / 2);
      stroke?.paint(canvas, origin);
      fill.paint(canvas, origin);
      return;
    }
    mesh.paint(canvas, pixelScale, (c) {
      stroke?.paint(c, Offset.zero);
      fill.paint(c, Offset.zero);
    });
  }
}

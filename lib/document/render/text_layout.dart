import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:characters/characters.dart';

import 'package:flutter/painting.dart';

import '../model/layer.dart';

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

  /// Forgets all layouts (e.g. after a font finished loading).
  void clear() => _cache.clear();

  /// Padding around glyphs so strokes and italics are not clipped.
  static double paddingFor(TextLayer l) =>
      l.strokeWidth / 2 + l.fontSize * 0.08;

  TextPainter fill(TextLayer l) => entry(l).fill;
  TextPainter? stroke(TextLayer l) => entry(l).stroke;

  /// Size of the layer's local box (text, padding and background).
  Size sizeOf(TextLayer l) => entry(l).size;

  /// Paints [l] centred on the canvas origin.
  void paint(Canvas canvas, TextLayer l) => entry(l).paint(canvas);

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

/// One glyph cluster placed on a curve.
class _Placed {
  const _Placed(this.box, this.pos, this.angle);

  /// Cluster box in the straight layout.
  final Rect box;

  /// Centre of the cluster on the curve (relative to the layer centre).
  final Offset pos;
  final double angle;
}

class TextLayoutEntry {
  TextLayoutEntry._(
    this.layer,
    this.fill,
    this.stroke,
    this.size,
    this._placed,
    this._curveShift,
  );

  final TextLayer layer;
  final TextPainter fill;
  final TextPainter? stroke;

  /// Local box size (centred on the origin).
  final Size size;
  final List<_Placed>? _placed;
  final Offset _curveShift;

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

    TextPainter make(Paint? fg) =>
        TextPainter(
          text: TextSpan(text: text.isEmpty ? ' ' : text, style: style(fg)),
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
      );
    }

    final pad = TextLayoutCache.paddingFor(l);
    final bgPad = l.background == null
        ? Size.zero
        : Size(l.bgPadX * l.fontSize, l.bgPadY * l.fontSize);

    if (l.curve.abs() < 0.5 || fill.width <= 0) {
      final w = fill.width + 2 * math.max(pad, bgPad.width);
      final h = fill.height + 2 * math.max(pad, bgPad.height);
      return TextLayoutEntry._(l, fill, stroke, Size(w, h), null, Offset.zero);
    }

    // Curved: place every grapheme cluster on concentric arcs.
    final w = fill.width, h = fill.height;
    final sign = l.curve.sign;
    final r0 = w / (l.curve.abs() * math.pi / 180);
    final placed = <_Placed>[];
    var bounds = Rect.zero;
    var first = true;
    var offset = 0;
    for (final g in text.characters) {
      final start = offset;
      offset += g.length;
      if (g.trim().isEmpty) continue;
      final boxes = fill.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: offset),
      );
      if (boxes.isEmpty) continue;
      var box = boxes.first.toRect();
      for (final b in boxes.skip(1)) {
        box = box.expandToInclude(b.toRect());
      }
      final dx = box.center.dx - w / 2, dy = box.center.dy - h / 2;
      final theta = dx / r0;
      final r = r0 - sign * dy;
      final pos = Offset(
        r * math.sin(theta),
        sign * r0 - sign * r * math.cos(theta),
      );
      final angle = sign * theta;
      placed.add(_Placed(box, pos, angle));
      // Rotated cluster corners for the bounds.
      final c = math.cos(angle), s = math.sin(angle);
      final hw = box.width / 2, hh = box.height / 2;
      for (final (x, y) in [(-hw, -hh), (hw, -hh), (hw, hh), (-hw, hh)]) {
        final p = pos + Offset(x * c - y * s, x * s + y * c);
        if (first) {
          bounds = Rect.fromLTRB(p.dx, p.dy, p.dx, p.dy);
          first = false;
        } else {
          bounds = bounds.expandToInclude(
            Rect.fromLTRB(p.dx, p.dy, p.dx, p.dy),
          );
        }
      }
    }
    if (placed.isEmpty) {
      return TextLayoutEntry._(
        l,
        fill,
        stroke,
        Size(w + 2 * pad, h + 2 * pad),
        null,
        Offset.zero,
      );
    }
    final size = Size(
      bounds.width + 2 * math.max(pad, bgPad.width),
      bounds.height + 2 * math.max(pad, bgPad.height),
    );
    return TextLayoutEntry._(l, fill, stroke, size, placed, -bounds.center);
  }

  void paint(Canvas canvas) {
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
    final placed = _placed;
    if (placed == null) {
      final origin = Offset(-fill.width / 2, -fill.height / 2);
      stroke?.paint(canvas, origin);
      fill.paint(canvas, origin);
      return;
    }
    // Each cluster: clip the straight layout to the cluster and paint it
    // rotated onto the arc. Painting whole lines keeps Arabic-script joins
    // and shaping intact.
    final grow = l.strokeWidth / 2 + 0.6;
    void pass(TextPainter p) {
      for (final g in placed) {
        canvas
          ..save()
          ..translate(g.pos.dx + _curveShift.dx, g.pos.dy + _curveShift.dy)
          ..rotate(g.angle)
          ..clipRect(
            Rect.fromCenter(
              center: Offset.zero,
              width: g.box.width + grow * 2,
              height: g.box.height + l.fontSize,
            ),
          );
        p.paint(canvas, -g.box.center);
        canvas.restore();
      }
    }

    if (stroke != null) pass(stroke!);
    pass(fill);
  }
}

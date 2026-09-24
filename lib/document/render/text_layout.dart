import 'dart:collection';
import 'dart:ui' as ui;

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
  final LinkedHashMap<int, _Entry> _cache = LinkedHashMap();

  /// Padding around glyphs so strokes and italics are not clipped.
  static double paddingFor(TextLayer l) =>
      l.strokeWidth / 2 + l.fontSize * 0.08;

  TextPainter fill(TextLayer l) => _entry(l).fill;
  TextPainter? stroke(TextLayer l) => _entry(l).stroke;

  /// Size of the layer's local box (text plus padding).
  Size sizeOf(TextLayer l) {
    final p = fill(l);
    final pad = paddingFor(l) * 2;
    return Size(p.width + pad, p.height + pad);
  }

  _Entry _entry(TextLayer l) {
    final key = Object.hash(
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
    );
    final hit = _cache.remove(key);
    if (hit != null) {
      _cache[key] = hit;
      return hit;
    }
    final entry = _build(l);
    _cache[key] = entry;
    if (_cache.length > _maxEntries) {
      final oldest = _cache.keys.first;
      // Not disposed eagerly: a painter handed out earlier in the current
      // frame may still be in use. The GC reclaims it.
      _cache.remove(oldest);
    }
    return entry;
  }

  _Entry _build(TextLayer l) {
    final dir = detectTextDirection(l.text);
    final align = switch (l.align) {
      PixTextAlign.start => TextAlign.start,
      PixTextAlign.center => TextAlign.center,
      PixTextAlign.end => TextAlign.end,
    };
    TextStyle style(Paint? foreground) => TextStyle(
      fontFamily: l.fontFamily == 'System' ? null : l.fontFamily,
      fontSize: l.fontSize,
      fontWeight: FontWeight.values[((l.fontWeight ~/ 100) - 1).clamp(0, 8)],
      fontStyle: l.italic ? FontStyle.italic : FontStyle.normal,
      letterSpacing: l.letterSpacing,
      height: l.lineHeight,
      decoration: l.underline ? TextDecoration.underline : null,
      decorationColor: l.fill.primary,
      foreground: foreground,
      color: foreground == null ? l.fill.primary : null,
    );

    TextPainter make(Paint? fg) =>
        TextPainter(
          text: TextSpan(text: l.text.isEmpty ? ' ' : l.text, style: style(fg)),
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
    return _Entry(fill, stroke);
  }
}

class _Entry {
  _Entry(this.fill, this.stroke);
  final TextPainter fill;
  final TextPainter? stroke;
}

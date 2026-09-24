import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../core/utils/json.dart';

/// Style for part of a text layer ([start], [end]) — its own font and/or
/// colour. Offsets are UTF-16 indices into the layer's text.
@immutable
class TextSpanStyle {
  const TextSpanStyle({
    required this.start,
    required this.end,
    this.fontFamily,
    this.color,
  });

  final int start;
  final int end;
  final String? fontFamily;
  final Color? color;

  bool get isEmpty => end <= start || (fontFamily == null && color == null);

  TextSpanStyle copyWith({
    int? start,
    int? end,
    String? fontFamily,
    Color? color,
  }) => TextSpanStyle(
    start: start ?? this.start,
    end: end ?? this.end,
    fontFamily: fontFamily ?? this.fontFamily,
    color: color ?? this.color,
  );

  Json toJson() => {
    's': start,
    'e': end,
    'font': ?fontFamily,
    if (color != null) 'color': writeColor(color!),
  };

  static TextSpanStyle fromJson(Json m) => TextSpanStyle(
    start: readInt(m['s']),
    end: readInt(m['e']),
    fontFamily: m['font'] == null ? null : readString(m['font']),
    color: m['color'] == null ? null : readColor(m['color']),
  );

  @override
  bool operator ==(Object other) =>
      other is TextSpanStyle &&
      other.start == start &&
      other.end == end &&
      other.fontFamily == fontFamily &&
      other.color == color;

  @override
  int get hashCode => Object.hash(start, end, fontFamily, color);
}

/// Pure helpers for editing lists of [TextSpanStyle].
abstract final class TextSpans {
  /// Applies a font and/or colour to [start]..[end], splitting existing
  /// spans so later styles win where they overlap.
  static List<TextSpanStyle> apply(
    List<TextSpanStyle> spans,
    int start,
    int end, {
    String? fontFamily,
    Color? color,
  }) {
    if (end <= start) return spans;
    final out = <TextSpanStyle>[];
    for (final s in spans) {
      if (s.end <= start || s.start >= end) {
        out.add(s);
        continue;
      }
      // Keep the parts outside the new range.
      if (s.start < start) out.add(s.copyWith(end: start));
      if (s.end > end) out.add(s.copyWith(start: end));
      // The overlapping part keeps its other attribute.
      final os = math.max(s.start, start), oe = math.min(s.end, end);
      out.add(
        TextSpanStyle(
          start: os,
          end: oe,
          fontFamily: fontFamily ?? s.fontFamily,
          color: color ?? s.color,
        ),
      );
    }
    // Parts of the range not covered by any existing span.
    final covered = [
      for (final s in spans)
        if (!(s.end <= start || s.start >= end))
          (math.max(s.start, start), math.min(s.end, end)),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    var cursor = start;
    for (final (a, b) in covered) {
      if (a > cursor) {
        out.add(
          TextSpanStyle(
            start: cursor,
            end: a,
            fontFamily: fontFamily,
            color: color,
          ),
        );
      }
      cursor = math.max(cursor, b);
    }
    if (cursor < end) {
      out.add(
        TextSpanStyle(
          start: cursor,
          end: end,
          fontFamily: fontFamily,
          color: color,
        ),
      );
    }
    return normalize(out);
  }

  /// Removes styling (font, colour or both) from a range.
  static List<TextSpanStyle> clear(
    List<TextSpanStyle> spans,
    int start,
    int end, {
    bool font = true,
    bool color = true,
  }) {
    final out = <TextSpanStyle>[];
    for (final s in spans) {
      if (s.end <= start || s.start >= end) {
        out.add(s);
        continue;
      }
      if (s.start < start) out.add(s.copyWith(end: start));
      if (s.end > end) out.add(s.copyWith(start: end));
      final os = math.max(s.start, start), oe = math.min(s.end, end);
      final kept = TextSpanStyle(
        start: os,
        end: oe,
        fontFamily: font ? null : s.fontFamily,
        color: color ? null : s.color,
      );
      if (!kept.isEmpty) out.add(kept);
    }
    return normalize(out);
  }

  /// Sorted, non-empty, merged where neighbours have the same style.
  static List<TextSpanStyle> normalize(List<TextSpanStyle> spans) {
    final list = [
      for (final s in spans)
        if (!s.isEmpty) s,
    ]..sort((a, b) => a.start.compareTo(b.start));
    final out = <TextSpanStyle>[];
    for (final s in list) {
      final last = out.isEmpty ? null : out.last;
      if (last != null &&
          last.end == s.start &&
          last.fontFamily == s.fontFamily &&
          last.color == s.color) {
        out[out.length - 1] = last.copyWith(end: s.end);
      } else {
        out.add(s);
      }
    }
    return out;
  }

  /// Moves spans after a text edit that replaced [oldText] with [newText]
  /// (a single contiguous change, as typing and pasting produce).
  static List<TextSpanStyle> adjust(
    List<TextSpanStyle> spans,
    String oldText,
    String newText,
  ) {
    if (spans.isEmpty || oldText == newText) return spans;
    var prefix = 0;
    final minLen = math.min(oldText.length, newText.length);
    while (prefix < minLen && oldText[prefix] == newText[prefix]) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < minLen - prefix &&
        oldText[oldText.length - 1 - suffix] ==
            newText[newText.length - 1 - suffix]) {
      suffix++;
    }
    final oldEnd = oldText.length - suffix; // end of replaced part (old)
    final delta = newText.length - oldText.length;
    int map(int i, {required bool isEnd}) {
      if (i <= prefix) return i;
      if (i >= oldEnd) return i + delta;
      // Inside the replaced part: clamp to the edit.
      return isEnd ? prefix + (newText.length - suffix - prefix) : prefix;
    }

    return normalize([
      for (final s in spans)
        s.copyWith(
          start: map(s.start, isEnd: false),
          end: map(s.end, isEnd: true),
        ),
    ]).where((s) => s.start < newText.length).map((s) {
      return s.end > newText.length ? s.copyWith(end: newText.length) : s;
    }).toList();
  }
}

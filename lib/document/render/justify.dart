import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../model/text_span_style.dart';

/// Professional paragraph justification (Photoshop / InDesign style).
///
/// Flutter's own `TextAlign.justify` only widens the spaces, which tears
/// Arabic-script lines apart. Here every line is measured once, then:
///
/// * Arabic, Persian, Pashto and Urdu words are stretched with kashida
///   (tatweel, U+0640) at the calligraphically right joins — after
///   Seen/Sad, before final Heh/Dal, before final Alef/Lam/Kaf, … — spread
///   evenly over the line and capped per word;
/// * whatever is left (and all of it for Latin text) goes into the word
///   spaces of that line only;
/// * every line break is made explicit, so the widened lines can't rewrap.
///
/// A check layout then measures the real width of every line and corrects
/// the kashida width (fonts with contextual alternates stretch differently)
/// and the sub-pixel error, so both edges line up exactly. Only cheap
/// per-line paragraph queries are used, so huge texts stay fast.
class Justified {
  Justified._(this.text, this.spans, this.gaps, this.width);

  /// Text with kashidas and explicit line breaks.
  final String text;

  /// The layer's style spans, moved to the new offsets.
  final List<TextSpanStyle> spans;

  /// Line ranges whose word spaces are widened: (start, end, extra px).
  final List<(int, int, double)> gaps;

  /// Line width everything was justified to.
  final double width;
}

/// Builds the paragraph span tree for a text, its style spans and gaps.
typedef JustifyTree = InlineSpan Function(
  String text,
  List<TextSpanStyle> spans,
  List<(int, int, double)> gaps,
);

ui.Paragraph _layout(InlineSpan span, TextDirection dir, double width) {
  final style =
      (span is TextSpan ? span.style : null)?.getParagraphStyle(
        textDirection: dir,
      ) ??
      ui.ParagraphStyle(textDirection: dir);
  final b = ui.ParagraphBuilder(style);
  span.build(b);
  return b.build()..layout(ui.ParagraphConstraints(width: width));
}

/// Justifies [text]. [boxWidth]: line width (null = the longest line).
/// [tatweel]: advance of one kashida in the base font (0 = no kashida).
/// [maxKashida]: longest stretch per word, px. [shrink]: how far word
/// spaces may shrink to absorb a rounding overflow, px. Null when the
/// lines can't be read (the caller then lays the text out plainly).
Justified? justifyText({
  required String text,
  required List<TextSpanStyle> spans,
  required JustifyTree tree,
  required TextDirection dir,
  required double? boxWidth,
  required bool all,
  required double tatweel,
  required double maxKashida,
  required double baseWordSpacing,
  required double shrink,
}) {
  final measure = _layout(
    tree(text, spans, const []),
    dir,
    boxWidth ?? double.infinity,
  );
  final width = boxWidth ?? measure.longestLine;
  // The web engine's per-offset line numbers are unreliable: walk the
  // line boundaries there.
  final lines = kIsWeb
      ? _readLinesSlow(measure, text)
      : _readLines(measure, text) ?? _readLinesSlow(measure, text);
  measure.dispose();
  if (lines == null) return null;
  final j = _Justifier(
    text,
    spans,
    lines,
    width,
    all,
    tatweel,
    maxKashida,
    -(baseWordSpacing + shrink),
  );
  var out = j.build();
  // Word spaces widen exactly by the planned amount, kashidas don't (fonts
  // with contextual alternates stretch more or less than one tatweel).
  // So only lines with kashidas are checked: the first layout corrects
  // the kashida width, a second one (if that changed anything) the
  // spaces. At most two extra layouts, none for text without kashida.
  for (var pass = 0; pass < 2 && j.hasKashida; pass++) {
    final check = _layout(
      tree(out.text, out.spans, out.gaps),
      dir,
      width * 2 + 1000,
    );
    final replanned = j.correct(check, replan: pass == 0);
    check.dispose();
    out = j.build();
    if (!replanned) break;
  }
  return out;
}

/// A laid-out line of the measuring pass and its justification plan.
class _Line {
  _Line(this.start, this.content, this.end, this.last);

  /// First character, end of the visible content (trailing spaces
  /// excluded) and end of the range (before a `\n` or the next line).
  final int start, content, end;

  /// Last line of its paragraph (hard break or end of text).
  final bool last;
  double width = 0;
  int spaces = 0;
  bool justify = false;
  List<_Slot> slots = const [];
  List<int> counts = const [];

  /// Kashida advance used for this line (corrected after measuring).
  double tatweel = 0;
  double extra = 0;
}

/// Splits the measured paragraph [p] of [text] into lines, using only
/// per-offset line numbers (computeLineMetrics and getLineBoundary are
/// slow on long texts).
List<_Line>? _readLines(ui.Paragraph p, String text) {
  final n = text.length;
  int lineAt(int i) => p.getLineNumberAt(i) ?? -1;
  final starts = <int>[0];
  var cur = 0;
  // Finds the breaks inside [ws, we) (a word too long for the box).
  void inside(int ws, int we) {
    var b = lineAt(we - 1);
    while (b > cur) {
      var lo = ws + 1, hi = we - 1;
      while (lo < hi) {
        final mid = (lo + hi) >> 1;
        if (lineAt(mid) > cur) {
          hi = mid;
        } else {
          lo = mid + 1;
        }
      }
      starts.add(lo);
      cur = lineAt(lo);
    }
  }

  // One query per word; the previous word is only looked into when the
  // line changed (it may have been broken inside).
  var prevStart = -1, prevEnd = -1;
  var i = 0;
  while (i < n) {
    final c = text.codeUnitAt(i);
    if (c == 0x0A) {
      if (prevStart >= 0) inside(prevStart, prevEnd);
      prevStart = -1;
      if (i + 1 < n) starts.add(i + 1);
      cur++;
      i++;
      continue;
    }
    if (_isSpace(c)) {
      i++;
      continue;
    }
    var we = i;
    while (we < n) {
      final d = text.codeUnitAt(we);
      if (d == 0x0A || _isSpace(d)) break;
      we++;
    }
    final a = lineAt(i);
    if (a < 0) return null;
    if (a > cur) {
      if (prevStart >= 0) inside(prevStart, prevEnd);
      if (a > cur) {
        if (a != cur + 1) return null;
        starts.add(i);
        cur = a;
      }
    }
    prevStart = i;
    prevEnd = we;
    i = we;
  }
  if (prevStart >= 0) inside(prevStart, prevEnd);
  final count = p.numberOfLines;
  final trailing = n > 0 && text.codeUnitAt(n - 1) == 0x0A;
  if (count != starts.length + (trailing ? 1 : 0)) return null;
  final lines = <_Line>[];
  for (var k = 0; k < starts.length; k++) {
    final s = starts[k];
    var end = k + 1 < starts.length ? starts[k + 1] : n;
    var last = k + 1 == starts.length;
    if (end > s && text.codeUnitAt(end - 1) == 0x0A) {
      end--;
      last = true;
    }
    var content = end;
    while (content > s && _isSpace(text.codeUnitAt(content - 1))) {
      content--;
    }
    lines.add(
      _Line(s, content, end, last)..width = p.getLineMetricsAt(k)!.width,
    );
  }
  return lines;
}

/// Reads the lines by walking the line boundaries (one metrics call). The
/// web engine ends a boundary before the trailing spaces, the native one
/// after them; both are handled.
List<_Line>? _readLinesSlow(ui.Paragraph p, String text) {
  final n = text.length;
  final lines = <_Line>[];
  var o = 0;
  while (o < n) {
    var r = p.getLineBoundary(ui.TextPosition(offset: o));
    // The web engine answers a line's first offset with the line before.
    if (r.end <= o && o + 1 < n) {
      r = p.getLineBoundary(ui.TextPosition(offset: o + 1));
    }
    var end = math.max(r.end, o);
    final nl = text.indexOf('\n', o);
    if (nl >= 0 && nl < end) end = nl;
    // Trailing spaces belong to the line.
    while (end < n && _isSpace(text.codeUnitAt(end))) {
      end++;
    }
    if (end == o && nl != o) return null; // no progress
    var content = end;
    while (content > o && _isSpace(text.codeUnitAt(content - 1))) {
      content--;
    }
    final last = end >= n || text.codeUnitAt(end) == 0x0A;
    lines.add(_Line(o, content, end, last));
    o = last && end < n ? end + 1 : end;
  }
  final metrics = p.computeLineMetrics();
  final trailing = n > 0 && text.codeUnitAt(n - 1) == 0x0A;
  if (lines.isEmpty || metrics.length != lines.length + (trailing ? 1 : 0)) {
    return null;
  }
  for (var i = 0; i < lines.length; i++) {
    lines[i].width = metrics[i].width;
  }
  return lines;
}

bool _isSpace(int c) => c == 0x20 || c == 0x09 || c == 0xA0 || c == 0x3000;

class _Justifier {
  _Justifier(
    this.text,
    this.spans,
    this.lines,
    this.width,
    bool all,
    double tatweel,
    this.maxKashida,
    this.minExtra,
  ) {
    for (final l in lines) {
      for (var i = l.start; i < l.content; i++) {
        if (text.codeUnitAt(i) == 0x20) l.spaces++;
      }
      l.justify =
          (!l.last || all) && l.content > l.start && width - l.width > 0.25;
      if (!l.justify) continue;
      if (tatweel > 0 && maxKashida > 0) {
        l.slots = _kashidaSlots(text, l.start, l.content);
      }
      _plan(l, tatweel);
    }
  }

  final String text;
  final List<TextSpanStyle> spans;
  final List<_Line> lines;
  final double width;
  final double maxKashida;
  final double minExtra;

  /// Kashidas first (in whole tatweels), the rest into the spaces.
  void _plan(_Line l, double tatweel) {
    l.tatweel = tatweel;
    final deficit = width - l.width;
    var left = deficit;
    if (l.slots.isNotEmpty && tatweel > 0) {
      final cap = math.max(1, (maxKashida / tatweel).floor());
      l.counts = _distribute(l.slots, (deficit / tatweel).floor(), cap);
      for (final c in l.counts) {
        left -= c * tatweel;
      }
    } else {
      l.counts = const [];
    }
    l.extra = l.spaces > 0 && left > 0 ? left / l.spaces : 0;
  }

  bool get hasKashida => lines.any((l) => l.counts.any((c) => c > 0));

  /// Adjusts the plan from the check layout [p]: the kashida width of
  /// lines that are off (if [replan]), otherwise their word spaces.
  /// Returns true when kashidas were re-planned (to be measured again).
  bool correct(ui.Paragraph p, {required bool replan}) {
    if (p.numberOfLines < lines.length) return false;
    final all = kIsWeb ? p.computeLineMetrics() : null;
    var changed = false;
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      if (!l.justify) continue;
      final w = (all?[i] ?? p.getLineMetricsAt(i)!).width;
      final error = width - w;
      if (error.abs() < 0.25) continue;
      final kashidas = l.counts.fold(0, (a, b) => a + b);
      if (replan && kashidas > 0) {
        final real = (w - l.width - l.extra * l.spaces) / kashidas;
        if (real > 0.05 && (real - l.tatweel).abs() * kashidas > 0.5) {
          _plan(l, real);
          changed = true;
          continue;
        }
      }
      if (l.spaces > 0) {
        l.extra = math.max(minExtra, l.extra + error / l.spaces);
      }
    }
    return changed;
  }

  Justified build() {
    // Edits of the original text, in order: kashidas and line breaks.
    final inserts = <(int, String)>[];
    final breaks = <int>{}; // trailing spaces turned into line breaks
    for (final l in lines) {
      for (var k = 0; k < l.counts.length; k++) {
        if (l.counts[k] > 0) {
          inserts.add((l.slots[k].pos, '\u0640' * l.counts[k]));
        }
      }
      if (!l.last) {
        // Make the soft break hard: the last trailing space becomes `\n`,
        // or (a word broken mid-way) a `\n` is inserted.
        if (l.end > l.content) {
          breaks.add(l.end - 1);
        } else {
          inserts.add((l.end, '\n'));
        }
      }
    }
    inserts.sort((a, b) => a.$1.compareTo(b.$1));

    // New text and an offset map (inserts at a position count for that
    // position: a span ending there takes its kashida along).
    final out = StringBuffer();
    final shiftAt = <int>[];
    final shiftBy = <int>[];
    var k = 0, shift = 0, from = 0;
    void copy(int to) {
      while (from < to) {
        final b = breaks.isEmpty ? -1 : _nextBreak(breaks, from, to);
        if (b < 0) {
          out.write(text.substring(from, to));
          from = to;
        } else {
          out
            ..write(text.substring(from, b))
            ..write('\n');
          from = b + 1;
        }
      }
    }

    while (k < inserts.length) {
      final pos = inserts[k].$1;
      copy(pos);
      while (k < inserts.length && inserts[k].$1 == pos) {
        out.write(inserts[k].$2);
        shift += inserts[k].$2.length;
        k++;
      }
      shiftAt.add(pos);
      shiftBy.add(shift);
    }
    copy(text.length);

    int map(int i) {
      var lo = 0, hi = shiftAt.length - 1, best = 0;
      while (lo <= hi) {
        final mid = (lo + hi) >> 1;
        if (shiftAt[mid] <= i) {
          best = shiftBy[mid];
          lo = mid + 1;
        } else {
          hi = mid - 1;
        }
      }
      return i + best;
    }

    final gaps = <(int, int, double)>[];
    for (var li = 0; li < lines.length; li++) {
      final l = lines[li];
      if (l.extra == 0) continue;
      final start = li == 0 ? 0 : map(l.start);
      final end = li + 1 < lines.length ? map(lines[li + 1].start) : out.length;
      gaps.add((start, end, l.extra));
    }
    return Justified._(
      out.toString(),
      [
        for (final s in spans)
          s.copyWith(
            start: map(s.start.clamp(0, text.length)),
            end: map(s.end.clamp(0, text.length)),
          ),
      ],
      gaps,
      width,
    );
  }

  /// Sorted break positions, searched linearly from a moving cursor.
  List<int>? _sortedBreaks;
  int _nextBreak(Set<int> breaks, int from, int to) {
    final sorted = _sortedBreaks ??= breaks.toList()..sort();
    var lo = 0, hi = sorted.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (sorted[mid] < from) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo < sorted.length && sorted[lo] < to ? sorted[lo] : -1;
  }
}

// --- Kashida -------------------------------------------------------------

class _Slot {
  _Slot(this.pos, this.priority, this.word);

  /// Insert position (before the second letter of the join).
  final int pos;

  /// 1 = best.
  final int priority;
  final int word;
}

/// Letters that join on both sides (Unicode joining type D), for Arabic,
/// Persian, Pashto, Urdu, Sindhi and Kurdish.
bool _dual(int c) =>
    c == 0x0620 ||
    c == 0x0626 ||
    c == 0x0628 ||
    (c >= 0x062A && c <= 0x062E) ||
    (c >= 0x0633 && c <= 0x063F) ||
    (c >= 0x0640 && c <= 0x0647) ||
    c == 0x0649 ||
    c == 0x064A ||
    c == 0x066E ||
    c == 0x066F ||
    (c >= 0x0678 && c <= 0x0687) ||
    (c >= 0x069A && c <= 0x06BF) ||
    c == 0x06C1 ||
    c == 0x06C2 ||
    c == 0x06CC ||
    c == 0x06CE ||
    c == 0x06D0 ||
    c == 0x06D1 ||
    (c >= 0x06FA && c <= 0x06FC) ||
    c == 0x06FF ||
    (c >= 0x0750 && c <= 0x077F && !_rightOnly(c));

/// Letters that join to the previous letter only (joining type R).
bool _rightOnly(int c) =>
    (c >= 0x0622 && c <= 0x0625) ||
    c == 0x0627 ||
    c == 0x0629 ||
    (c >= 0x062F && c <= 0x0632) ||
    c == 0x0648 ||
    (c >= 0x0671 && c <= 0x0673) ||
    (c >= 0x0675 && c <= 0x0677) ||
    (c >= 0x0688 && c <= 0x0699) ||
    c == 0x06C0 ||
    (c >= 0x06C3 && c <= 0x06CB) ||
    c == 0x06CD ||
    c == 0x06CF ||
    c == 0x06D2 ||
    c == 0x06D3 ||
    c == 0x06D5 ||
    c == 0x06EE ||
    c == 0x06EF ||
    c == 0x0759 ||
    c == 0x075A ||
    c == 0x076B ||
    c == 0x076C ||
    c == 0x0771 ||
    c == 0x0773 ||
    c == 0x0774 ||
    c == 0x0778 ||
    c == 0x0779;

/// Marks that sit on a letter without breaking its joins (harakat, …).
bool _mark(int c) =>
    (c >= 0x0610 && c <= 0x061A) ||
    (c >= 0x064B && c <= 0x065F) ||
    c == 0x0670 ||
    (c >= 0x06D6 && c <= 0x06DC) ||
    (c >= 0x06DF && c <= 0x06E4) ||
    c == 0x06E7 ||
    c == 0x06E8 ||
    (c >= 0x06EA && c <= 0x06ED);

bool _alef(int c) =>
    (c >= 0x0622 && c <= 0x0623) ||
    c == 0x0625 ||
    c == 0x0627 ||
    (c >= 0x0671 && c <= 0x0673) ||
    c == 0x0675;

bool _seenSad(int c) =>
    (c >= 0x0633 && c <= 0x0636) ||
    (c >= 0x069A && c <= 0x069E) ||
    c == 0x06FA ||
    c == 0x06FB;

bool _hehDal(int c) =>
    c == 0x0629 ||
    c == 0x0647 ||
    c == 0x06C0 ||
    c == 0x06C1 ||
    c == 0x06D5 ||
    (c >= 0x062F && c <= 0x0630) ||
    (c >= 0x0688 && c <= 0x0690);

bool _tall(int c) =>
    _alef(c) ||
    c == 0x0637 ||
    c == 0x0638 ||
    c == 0x0644 ||
    c == 0x0643 ||
    c == 0x06A9 ||
    c == 0x06AA ||
    c == 0x06AB ||
    c == 0x06AF ||
    c == 0x06B3;

bool _baLike(int c) =>
    c == 0x0628 ||
    c == 0x062A ||
    c == 0x062B ||
    c == 0x0679 ||
    c == 0x067C ||
    c == 0x067E ||
    c == 0x0646 ||
    c == 0x06BC ||
    c == 0x064A ||
    c == 0x06CC ||
    c == 0x06D0;

bool _raYa(int c) =>
    (c >= 0x0631 && c <= 0x0632) ||
    c == 0x0691 ||
    c == 0x0693 ||
    c == 0x0696 ||
    c == 0x0698 ||
    c == 0x0649 ||
    c == 0x064A ||
    c == 0x06CC ||
    c == 0x06CD ||
    c == 0x06D0 ||
    c == 0x06D2;

bool _wawAin(int c) =>
    c == 0x0648 ||
    c == 0x0624 ||
    (c >= 0x06C4 && c <= 0x06CB) ||
    c == 0x0639 ||
    c == 0x063A ||
    c == 0x0641 ||
    c == 0x0642 ||
    c == 0x06A4;

/// The best kashida position of every Arabic-script word in
/// [start, end), ranked like the classic Naskh rules.
List<_Slot> _kashidaSlots(String text, int start, int end) {
  final slots = <_Slot>[];
  var word = 0;
  _Slot? best;
  int next(int i) {
    // Next base letter after i (marks skipped), or -1.
    var j = i + 1;
    while (j < end && _mark(text.codeUnitAt(j))) {
      j++;
    }
    return j < end ? j : -1;
  }

  bool joinsBack(int c) => _dual(c) || _rightOnly(c);
  void flush() {
    if (best != null) slots.add(best!);
    best = null;
    word++;
  }

  for (var i = start; i < end; i++) {
    final a = text.codeUnitAt(i);
    if (_isSpace(a)) {
      flush();
      continue;
    }
    if (_mark(a) || !_dual(a) || a == 0x0640) continue;
    final j = next(i);
    if (j < 0) continue;
    final b = text.codeUnitAt(j);
    if (!joinsBack(b)) continue;
    // Lam + Alef is one ligature: never pull it apart.
    if (a == 0x0644 && _alef(b)) continue;
    final k = next(j);
    final bNext = k < 0 ? 0 : text.codeUnitAt(k);
    final bFinal = _rightOnly(b) || !joinsBack(bNext);
    final int p;
    if (_seenSad(a)) {
      p = 1;
    } else if (bFinal && _hehDal(b)) {
      p = 2;
    } else if (bFinal && _tall(b)) {
      p = 3;
    } else if (!bFinal && _baLike(b) && _raYa(bNext)) {
      p = 4;
    } else if (bFinal && _wawAin(b)) {
      p = 5;
    } else if (bFinal) {
      p = 6;
    } else {
      p = 7;
    }
    // Ties go to the later join (nearer the word's end).
    if (best == null || p <= best!.priority) best = _Slot(j, p, word);
  }
  flush();
  return slots;
}

/// Kashida counts per slot: [want] in total, at most [cap] each, the best
/// ranked words first and spread evenly along the line within a rank.
List<int> _distribute(List<_Slot> slots, int want, int cap) {
  final counts = List.filled(slots.length, 0);
  if (want <= 0) return counts;
  final order = <int>[];
  final ranks = slots.map((s) => s.priority).toSet().toList()..sort();
  for (final r in ranks) {
    final idx = [
      for (var i = 0; i < slots.length; i++)
        if (slots[i].priority == r) i,
    ];
    order.addAll(_spread(idx));
  }
  var left = want;
  for (var round = 0; round < cap && left > 0; round++) {
    for (final i in order) {
      if (left == 0) break;
      counts[i]++;
      left--;
    }
  }
  return counts;
}

/// Orders [idx] so that any prefix is spread evenly (middle first, then the
/// points farthest from those already taken).
List<int> _spread(List<int> idx) {
  final n = idx.length;
  if (n <= 2) return idx;
  // Distance of every point to the nearest one taken so far.
  final dist = List.filled(n, 1 << 30);
  final out = <int>[];
  var pick = n ~/ 2;
  while (true) {
    out.add(idx[pick]);
    dist[pick] = -1;
    if (out.length == n) break;
    var bestD = -1;
    final last = pick;
    for (var i = 0; i < n; i++) {
      if (dist[i] < 0) continue;
      final d = math.min(dist[i], (i - last).abs());
      dist[i] = d;
      if (d > bestD) {
        bestD = d;
        pick = i;
      }
    }
  }
  return out;
}

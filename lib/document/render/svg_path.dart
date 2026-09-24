import 'dart:collection';
import 'dart:ui';

/// Parses SVG path data (`d` attribute) into a [Path]. Supports every
/// command (M L H V C S Q T A Z, absolute and relative) and the compact
/// number syntax icon sets use (`-80v-480`, `.5.5`, `1e-3`).
Path parseSvgPath(String d) => _SvgPathParser(d).parse();

/// Parsed paths are cached by their data string.
class SvgPathCache {
  SvgPathCache._();
  static final LinkedHashMap<String, Path> _cache = LinkedHashMap();

  static Path get(String d) {
    final hit = _cache.remove(d);
    if (hit != null) {
      _cache[d] = hit;
      return hit;
    }
    final p = parseSvgPath(d);
    _cache[d] = p;
    if (_cache.length > 2048) _cache.remove(_cache.keys.first);
    return p;
  }
}

class _SvgPathParser {
  _SvgPathParser(this.s);
  final String s;
  int i = 0;

  bool _isCmd(int c) =>
      (c >= 65 && c <= 90 && c != 69) || (c >= 97 && c <= 122 && c != 101);

  void _skip() {
    while (i < s.length) {
      final c = s.codeUnitAt(i);
      if (c == 32 || c == 44 || c == 9 || c == 10 || c == 13) {
        i++;
      } else {
        break;
      }
    }
  }

  bool get _hasNumber {
    _skip();
    if (i >= s.length) return false;
    final c = s.codeUnitAt(i);
    return (c >= 48 && c <= 57) || c == 45 || c == 43 || c == 46;
  }

  double _num() {
    _skip();
    final start = i;
    if (i < s.length && (s[i] == '-' || s[i] == '+')) i++;
    var dot = false, digits = false;
    while (i < s.length) {
      final c = s.codeUnitAt(i);
      if (c >= 48 && c <= 57) {
        digits = true;
        i++;
      } else if (c == 46 && !dot) {
        dot = true;
        i++;
      } else {
        break;
      }
    }
    if (digits && i < s.length && (s[i] == 'e' || s[i] == 'E')) {
      var j = i + 1;
      if (j < s.length && (s[j] == '-' || s[j] == '+')) j++;
      if (j < s.length && s.codeUnitAt(j) >= 48 && s.codeUnitAt(j) <= 57) {
        i = j;
        while (i < s.length && s.codeUnitAt(i) >= 48 && s.codeUnitAt(i) <= 57) {
          i++;
        }
      }
    }
    return double.tryParse(s.substring(start, i)) ?? 0;
  }

  bool _flag() {
    _skip();
    final c = i < s.length ? s[i] : '0';
    i++;
    return c == '1';
  }

  Path parse() {
    final p = Path();
    var cur = Offset.zero, start = Offset.zero;
    Offset? lastCubic, lastQuad;
    String cmd = 'M';
    while (true) {
      _skip();
      if (i >= s.length) break;
      final c = s.codeUnitAt(i);
      if (_isCmd(c)) {
        cmd = s[i];
        i++;
      } else if (!_hasNumber) {
        i++;
        continue;
      }
      final rel = cmd == cmd.toLowerCase();
      Offset pt(double x, double y) => rel ? cur + Offset(x, y) : Offset(x, y);
      switch (cmd.toUpperCase()) {
        case 'M':
          cur = pt(_num(), _num());
          start = cur;
          p.moveTo(cur.dx, cur.dy);
          // Further pairs are implicit line-tos.
          cmd = rel ? 'l' : 'L';
          lastCubic = lastQuad = null;
          continue;
        case 'L':
          cur = pt(_num(), _num());
          p.lineTo(cur.dx, cur.dy);
          lastCubic = lastQuad = null;
        case 'H':
          final x = _num();
          cur = Offset(rel ? cur.dx + x : x, cur.dy);
          p.lineTo(cur.dx, cur.dy);
          lastCubic = lastQuad = null;
        case 'V':
          final y = _num();
          cur = Offset(cur.dx, rel ? cur.dy + y : y);
          p.lineTo(cur.dx, cur.dy);
          lastCubic = lastQuad = null;
        case 'C':
          final c1 = pt(_num(), _num());
          final c2 = pt(_num(), _num());
          final e = pt(_num(), _num());
          p.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, e.dx, e.dy);
          lastCubic = c2;
          lastQuad = null;
          cur = e;
        case 'S':
          final c1 = lastCubic == null ? cur : cur * 2 - lastCubic;
          final c2 = pt(_num(), _num());
          final e = pt(_num(), _num());
          p.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, e.dx, e.dy);
          lastCubic = c2;
          lastQuad = null;
          cur = e;
        case 'Q':
          final q = pt(_num(), _num());
          final e = pt(_num(), _num());
          p.quadraticBezierTo(q.dx, q.dy, e.dx, e.dy);
          lastQuad = q;
          lastCubic = null;
          cur = e;
        case 'T':
          final q = lastQuad == null ? cur : cur * 2 - lastQuad;
          final e = pt(_num(), _num());
          p.quadraticBezierTo(q.dx, q.dy, e.dx, e.dy);
          lastQuad = q;
          lastCubic = null;
          cur = e;
        case 'A':
          final rx = _num().abs(), ry = _num().abs();
          final rot = _num();
          final large = _flag();
          final sweep = _flag();
          final e = pt(_num(), _num());
          if (rx == 0 || ry == 0) {
            p.lineTo(e.dx, e.dy);
          } else {
            p.arcToPoint(
              e,
              radius: Radius.elliptical(rx, ry),
              rotation: rot,
              largeArc: large,
              clockwise: sweep,
            );
          }
          lastCubic = lastQuad = null;
          cur = e;
        case 'Z':
          p.close();
          cur = start;
          lastCubic = lastQuad = null;
          // Stray numbers after Z (invalid SVG) become line-tos rather
          // than looping forever.
          cmd = 'L';
          continue;
        default:
          i++;
      }
    }
    return p;
  }
}

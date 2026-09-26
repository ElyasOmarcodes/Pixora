import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Pattern tiles for [FillKind.pattern] fills (Photoshop's Pattern
/// Overlay / pattern fills).
///
/// Two sources:
/// * built-in patterns, drawn procedurally in the fill's two colours
///   (foreground on background), ids like `dots`;
/// * image patterns (from a photo, a layer or a selection), stored as
///   project assets, ids like `asset:as_12ab`.
abstract final class Patterns {
  static const assetPrefix = 'asset:';

  /// Built-in pattern ids, in picker order.
  static const builtins = [
    'dots',
    'polka',
    'stripes',
    'diagonal',
    'checker',
    'grid',
    'bricks',
    'zigzag',
    'waves',
    'crosshatch',
    'honeycomb',
    'triangles',
    'diamonds',
    'scales',
    'hearts',
    'stars',
    'plaid',
    'confetti',
  ];

  static bool isAsset(String id) => id.startsWith(assetPrefix);
  static String assetId(String id) => id.substring(assetPrefix.length);
  static String forAsset(String assetId) => '$assetPrefix$assetId';

  /// Where decoded asset images come from (each open editor registers its
  /// asset store).
  static final List<ui.Image? Function(String assetId)> _lookups = [];

  static void addLookup(ui.Image? Function(String assetId) f) =>
      _lookups.add(f);
  static void removeLookup(ui.Image? Function(String assetId) f) =>
      _lookups.remove(f);

  /// Side of a built-in tile in pattern pixels (before the fill's scale).
  static const tileSize = 48.0;

  static final Map<(String, int, int, bool, double), ui.Image> _tiles = {};
  static final Map<(ui.Image, bool), ui.Image> _mirrored = {};
  static final Map<(ui.Image, int, int, bool), ui.Image> _tinted = {};

  /// The repeating tile for pattern [id]: built-ins in [fg] on [bg], their
  /// elements sized by [detail] (1 = standard); image patterns as they are
  /// or, with [tint], as a stencil in [fg] on [bg]. With [mirror] the tile
  /// is mirrored into a 2×2 block so its edges always meet (a seamless
  /// pattern from any image). Null while an image pattern is decoding.
  static ui.Image? tile(
    String id, {
    Color fg = const Color(0xFF000000),
    Color bg = const Color(0x00000000),
    bool mirror = false,
    double detail = 1,
    bool tint = false,
  }) {
    if (isAsset(id)) {
      final aid = assetId(id);
      ui.Image? img;
      for (final f in _lookups) {
        img = f(aid);
        if (img != null) break;
      }
      if (img == null) return null;
      if (tint) img = _tint(img, fg, bg);
      return mirror ? _mirror(img) : img;
    }
    final k = detail.clamp(0.1, 4.0);
    final key = (id, fg.toARGB32(), bg.toARGB32(), mirror, k);
    final hit = _tiles[key];
    if (hit != null) return hit;
    if (_tiles.length > 96) {
      // Images may still be referenced by pictures; let the GC free them.
      _tiles.clear();
    }
    var img = _draw(id, fg, bg, k);
    if (mirror) img = _mirror(img);
    _tiles[key] = img;
    return img;
  }

  /// An image pattern's shape (its alpha) in [fg] over [bg].
  static ui.Image _tint(ui.Image src, Color fg, Color bg) {
    final key = (src, fg.toARGB32(), bg.toARGB32(), true);
    final hit = _tinted[key];
    if (hit != null) return hit;
    if (_tinted.length > 24) _tinted.clear();
    final w = src.width.toDouble(), h = src.height.toDouble();
    final rec = ui.PictureRecorder();
    final r = Rect.fromLTWH(0, 0, w, h);
    Canvas(rec)
      ..drawRect(r, Paint()..color = bg)
      ..drawImage(
        src,
        Offset.zero,
        Paint()..colorFilter = ColorFilter.mode(fg, BlendMode.srcIn),
      );
    final pic = rec.endRecording();
    final out = pic.toImageSync(src.width, src.height);
    pic.dispose();
    return _tinted[key] = out;
  }

  static ui.Image _mirror(ui.Image src) {
    final key = (src, true);
    final hit = _mirrored[key];
    if (hit != null) return hit;
    if (_mirrored.length > 16) _mirrored.clear();
    final w = src.width.toDouble(), h = src.height.toDouble();
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    final srcRect = Rect.fromLTWH(0, 0, w, h);
    final p = Paint()..filterQuality = FilterQuality.medium;
    for (final (fx, fy) in [
      (false, false),
      (true, false),
      (false, true),
      (true, true),
    ]) {
      c
        ..save()
        ..translate(fx ? 2 * w : 0, fy ? 2 * h : 0)
        ..scale(fx ? -1 : 1, fy ? -1 : 1)
        ..drawImageRect(src, srcRect, srcRect, p)
        ..restore();
    }
    final pic = rec.endRecording();
    final out = pic.toImageSync((w * 2).toInt(), (h * 2).toInt());
    pic.dispose();
    _mirrored[key] = out;
    return out;
  }

  static ui.Image _draw(String id, Color fg, Color bg, double k) {
    const s = tileSize;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.drawRect(const Rect.fromLTWH(0, 0, s, s), Paint()..color = bg);
    final p = Paint()
      ..color = fg
      ..isAntiAlias = true;
    final line = Paint()
      ..color = fg
      ..style = PaintingStyle.stroke
      ..strokeWidth = s / 12 * k
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    Path poly(List<Offset> pts) => Path()..addPolygon(pts, true);
    // Draws [path] scaled by k about [o] (element size for shapes).
    void shapeAt(Offset o, Path path) {
      c
        ..save()
        ..translate(o.dx, o.dy)
        ..scale(k)
        ..translate(-o.dx, -o.dy)
        ..drawPath(path, p)
        ..restore();
    }

    switch (id) {
      case 'dots':
        c.drawCircle(
          const Offset(s / 2, s / 2),
          math.min(s / 2, s * 0.18 * k),
          p,
        );
      case 'polka':
        for (final o in const [
          Offset(s / 4, s / 4),
          Offset(s * 3 / 4, s * 3 / 4),
        ]) {
          c.drawCircle(o, math.min(s / 4, s * 0.13 * k), p);
        }
      case 'stripes':
        c.drawRect(Rect.fromLTWH(0, 0, s, math.min(s, s / 2 * k)), p);
      case 'diagonal':
        // Bands at 45° that meet across tiles.
        final band = Paint()
          ..color = fg
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.3536 * k
          ..isAntiAlias = true;
        // Lines x + y = 0, s, 2s, long enough to cross the whole tile.
        for (final k0 in const [0.0, s, 2 * s]) {
          c.drawLine(
            Offset(k0 - 2 * s, 2 * s),
            Offset(k0 + 2 * s, -2 * s),
            band,
          );
        }
      case 'checker':
        final q = math.min(s / 2, s / 2 * k);
        final o = (s / 2 - q) / 2;
        c
          ..drawRect(Rect.fromLTWH(o, o, q, q), p)
          ..drawRect(Rect.fromLTWH(s / 2 + o, s / 2 + o, q, q), p);
      case 'grid':
        final g = math.min(s, s / 16 * k);
        c
          ..drawRect(Rect.fromLTWH(0, 0, s, g), p)
          ..drawRect(Rect.fromLTWH(0, 0, g, s), p);
      case 'bricks':
        // Element size = brick size: mortar shrinks as bricks grow.
        final m = (s / 24 / k).clamp(0.3, s / 4);
        c
          ..drawRect(Rect.fromLTRB(m, m, s - m, s / 2 - m), p)
          ..drawRect(Rect.fromLTRB(-s / 2 + m, s / 2 + m, s / 2 - m, s - m), p)
          ..drawRect(
            Rect.fromLTRB(s / 2 + m, s / 2 + m, s * 1.5 - m, s - m),
            p,
          );
      case 'zigzag':
        c.drawPath(
          Path()
            ..moveTo(0, s * 0.65)
            ..lineTo(s / 4, s * 0.35)
            ..lineTo(s / 2, s * 0.65)
            ..lineTo(s * 3 / 4, s * 0.35)
            ..lineTo(s, s * 0.65),
          line,
        );
      case 'waves':
        c.drawPath(
          Path()
            ..moveTo(0, s / 2)
            ..cubicTo(s / 6, s * 0.2, s / 3, s * 0.2, s / 2, s / 2)
            ..cubicTo(s * 2 / 3, s * 0.8, s * 5 / 6, s * 0.8, s, s / 2),
          line,
        );
      case 'crosshatch':
        final thin = line..strokeWidth = s / 20 * k;
        c
          ..drawLine(Offset.zero, const Offset(s, s), thin)
          ..drawLine(const Offset(s, 0), const Offset(0, s), thin);
      case 'honeycomb':
        const r = s / 3;
        final path = Path();
        for (var i = 0; i < 6; i++) {
          final a = math.pi / 3 * i;
          final pt =
              const Offset(s / 2, s / 2) + Offset(math.cos(a), math.sin(a)) * r;
          i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
        }
        path.close();
        c
          ..drawPath(path, line..strokeWidth = s / 24 * k)
          ..drawLine(
            const Offset(s / 2 + r, s / 2),
            const Offset(s, s / 2),
            line,
          )
          ..drawLine(
            const Offset(s / 2 - r, s / 2),
            const Offset(0, s / 2),
            line,
          );
      case 'triangles':
        shapeAt(
          const Offset(s / 2, s / 3),
          poly(const [Offset(0, s / 2), Offset(s / 2, 0), Offset(s, s / 2)]),
        );
        shapeAt(
          const Offset(s / 2, s * 5 / 6),
          poly(const [Offset(0, s), Offset(s / 2, s / 2), Offset(s, s)]),
        );
      case 'diamonds':
        shapeAt(
          const Offset(s / 2, s / 2),
          poly(const [
            Offset(s / 2, s * 0.1),
            Offset(s * 0.9, s / 2),
            Offset(s / 2, s * 0.9),
            Offset(s * 0.1, s / 2),
          ]),
        );
      case 'scales':
        final sc = line..strokeWidth = s / 20 * k;
        for (final o in const [
          Offset(0, s / 2),
          Offset(s, s / 2),
          Offset(s / 2, 0),
          Offset(s / 2, s),
        ]) {
          c.drawArc(
            Rect.fromCircle(center: o, radius: s / 2),
            0,
            math.pi,
            false,
            sc,
          );
        }
      case 'hearts':
        shapeAt(
          const Offset(s / 2, s / 2),
          Path()
            ..moveTo(s / 2, s * 0.78)
            ..cubicTo(s * 0.1, s * 0.5, s * 0.2, s * 0.18, s / 2, s * 0.34)
            ..cubicTo(s * 0.8, s * 0.18, s * 0.9, s * 0.5, s / 2, s * 0.78)
            ..close(),
        );
      case 'stars':
        final star = Path();
        for (var i = 0; i < 10; i++) {
          final r = i.isEven ? s * 0.3 : s * 0.13;
          final a = -math.pi / 2 + math.pi / 5 * i;
          final pt = Offset(s / 2 + math.cos(a) * r, s / 2 + math.sin(a) * r);
          i == 0 ? star.moveTo(pt.dx, pt.dy) : star.lineTo(pt.dx, pt.dy);
        }
        shapeAt(const Offset(s / 2, s / 2), star..close());
      case 'plaid':
        final soft = Paint()..color = fg.withValues(alpha: fg.a * 0.45);
        final b = math.min(s / 2, s / 4 * k), t = math.min(s / 4, s / 16 * k);
        c
          ..drawRect(Rect.fromLTWH(0, s / 4, s, b), soft)
          ..drawRect(Rect.fromLTWH(s / 4, 0, b, s), soft)
          ..drawRect(Rect.fromLTWH(0, s * 0.7, s, t), p)
          ..drawRect(Rect.fromLTWH(s * 0.7, 0, t, s), p);
      case 'confetti':
        final rnd = math.Random(7);
        for (var i = 0; i < 14; i++) {
          c.drawCircle(
            Offset(rnd.nextDouble() * s, rnd.nextDouble() * s),
            s * (0.025 + rnd.nextDouble() * 0.035) * k,
            p,
          );
        }
      default:
        c.drawCircle(const Offset(s / 2, s / 2), s * 0.18 * k, p);
    }
    final pic = rec.endRecording();
    final img = pic.toImageSync(s.toInt(), s.toInt());
    pic.dispose();
    return img;
  }
}

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../document/model/layer.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui/widgets/pix_slider.dart';

/// The result of the crop page: the new pixels and how they were made.
class CropOutcome {
  const CropOutcome(this.bytes, this.width, this.height, this.state);
  final Uint8List bytes;
  final double width;
  final double height;
  final CropState state;
}

/// Full-page crop & resize: aspect presets, free crop, rotate 90°, flip,
/// straighten, round (ellipse) crop, ratio lock and output resolution.
/// [image] is the original (uncropped) picture.
Future<CropOutcome?> showCropPage(
  BuildContext context, {
  required ui.Image image,
  CropState? initial,
}) => Navigator.of(context).push<CropOutcome>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _CropPage(image: image, initial: initial),
  ),
);

/// Geometry of the turned, flipped and straightened image.
class _Geo {
  _Geo(this.image, this.state) {
    final w = image.width.toDouble(), h = image.height.toDouble();
    final odd = state.quarterTurns.isOdd;
    final tw = odd ? h : w, th = odd ? w : h;
    final a = state.straighten * math.pi / 180;
    final c = math.cos(a).abs(), s = math.sin(a).abs();
    box = Size(tw * c + th * s, tw * s + th * c);
    turned = Size(tw, th);
  }
  final ui.Image image;
  final CropState state;
  late final Size box;
  late final Size turned;

  double get angle =>
      state.quarterTurns * math.pi / 2 + state.straighten * math.pi / 180;

  /// Draws the image into [box] coordinates (origin top-left).
  void paint(Canvas canvas, {FilterQuality q = FilterQuality.medium}) {
    final w = image.width.toDouble(), h = image.height.toDouble();
    canvas
      ..save()
      ..translate(box.width / 2, box.height / 2)
      ..rotate(angle)
      ..scale(state.flipH ? -1 : 1, state.flipV ? -1 : 1)
      ..drawImageRect(
        image,
        Rect.fromLTWH(0, 0, w, h),
        Rect.fromCenter(center: Offset.zero, width: w, height: h),
        Paint()
          ..filterQuality = q
          ..isAntiAlias = true,
      )
      ..restore();
  }

  /// Whether a point (box coordinates) lies on the image.
  bool contains(Offset p) {
    final c = Offset(box.width / 2, box.height / 2);
    final d = p - c;
    final a = -state.straighten * math.pi / 180;
    final x = d.dx * math.cos(a) - d.dy * math.sin(a);
    final y = d.dx * math.sin(a) + d.dy * math.cos(a);
    return x.abs() <= turned.width / 2 + 0.5 &&
        y.abs() <= turned.height / 2 + 0.5;
  }

  /// Largest crop (same centre and shape as [r], 0..1 of the box) with no
  /// empty corners.
  Rect fitInside(Rect r) {
    Rect scaled(double k) {
      final c = r.center;
      return Rect.fromCenter(
        center: c,
        width: r.width * k,
        height: r.height * k,
      );
    }

    bool ok(Rect n) {
      for (final p in [n.topLeft, n.topRight, n.bottomRight, n.bottomLeft]) {
        if (!contains(Offset(p.dx * box.width, p.dy * box.height))) {
          return false;
        }
      }
      return true;
    }

    if (ok(r)) return r;
    var lo = 0.0, hi = 1.0;
    for (var i = 0; i < 24; i++) {
      final m = (lo + hi) / 2;
      ok(scaled(m)) ? lo = m : hi = m;
    }
    return scaled(lo);
  }
}

enum _Grip { tl, t, tr, r, br, b, bl, l, move }

class _CropPage extends StatefulWidget {
  const _CropPage({required this.image, this.initial});
  final ui.Image image;
  final CropState? initial;

  @override
  State<_CropPage> createState() => _CropPageState();
}

class _CropPageState extends State<_CropPage> {
  late CropState _s = widget.initial ?? const CropState();

  /// Width / height of the crop in pixels, or null for free.
  double? _ratio;
  bool _busy = false;
  _Grip? _grip;
  Rect _startRect = Rect.zero;
  Offset _startPos = Offset.zero;

  _Geo get _geo => _Geo(widget.image, _s);

  Size get _outPx {
    final g = _geo;
    return Size(
      (_s.rect.width * g.box.width * _s.resolution).roundToDouble(),
      (_s.rect.height * g.box.height * _s.resolution).roundToDouble(),
    );
  }

  /// Applies [ratio] around the current centre, as large as fits.
  void _setRatio(double? ratio) {
    HapticFeedback.selectionClick();
    setState(() {
      _ratio = ratio;
      if (ratio == null) return;
      final g = _geo;
      // In normalised box units: w/h = ratio * boxH / boxW.
      final k = ratio * g.box.height / g.box.width;
      var w = 1.0, h = w / k;
      if (h > 1) {
        h = 1;
        w = k;
      }
      final c = _s.rect.center;
      var r = Rect.fromCenter(center: c, width: w, height: h);
      r = r.shift(
        Offset(
          r.left < 0 ? -r.left : (r.right > 1 ? 1 - r.right : 0),
          r.top < 0 ? -r.top : (r.bottom > 1 ? 1 - r.bottom : 0),
        ),
      );
      _s = _s.copyWith(rect: g.fitInside(r));
    });
  }

  void _turn(int d) {
    HapticFeedback.selectionClick();
    setState(() {
      _s = _s.copyWith(
        quarterTurns: (_s.quarterTurns + d) % 4,
        rect: const Rect.fromLTRB(0, 0, 1, 1),
      );
      if (_ratio != null) _setRatio(1 / _ratio!);
    });
  }

  void _straighten(double deg) {
    setState(() {
      final oldBox = _geo.box;
      final base = _s.copyWith(straighten: deg);
      final g = _Geo(widget.image, base);
      // Keep the crop's pixel size (and so its aspect ratio) while the
      // rotated box changes shape; then shrink it uniformly until it fits.
      final c = _s.rect.center;
      var w = _s.rect.width * oldBox.width / g.box.width;
      var h = _s.rect.height * oldBox.height / g.box.height;
      final over = math.max(1.0, math.max(w, h));
      w /= over;
      h /= over;
      var r = Rect.fromCenter(
        center: Offset(
          c.dx.clamp(w / 2, 1 - w / 2).toDouble(),
          c.dy.clamp(h / 2, 1 - h / 2).toDouble(),
        ),
        width: w,
        height: h,
      );
      if (_ratio == null && r.isEmpty) r = const Rect.fromLTRB(0, 0, 1, 1);
      _s = base.copyWith(rect: g.fitInside(r));
    });
  }

  Future<void> _done() async {
    setState(() => _busy = true);
    final g = _geo;
    final out = _outPx;
    final w = math.max(1, out.width.round()),
        h = math.max(1, out.height.round());
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    if (_s.ellipse) {
      c.clipPath(
        Path()..addOval(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble())),
      );
    }
    c
      ..scale(_s.resolution)
      ..translate(-_s.rect.left * g.box.width, -_s.rect.top * g.box.height);
    g.paint(c, q: FilterQuality.high);
    final img = await rec.endRecording().toImage(w, h);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    if (!mounted || data == null) return;
    Navigator.pop(
      context,
      CropOutcome(data.buffer.asUint8List(), w.toDouble(), h.toDouble(), _s),
    );
  }

  // ------------------------------------------------------------ gestures

  _Grip? _hit(Offset p, Rect r) {
    const t = 28.0;
    final points = <_Grip, Offset>{
      _Grip.tl: r.topLeft,
      _Grip.tr: r.topRight,
      _Grip.br: r.bottomRight,
      _Grip.bl: r.bottomLeft,
      _Grip.t: r.topCenter,
      _Grip.r: r.centerRight,
      _Grip.b: r.bottomCenter,
      _Grip.l: r.centerLeft,
    };
    for (final e in points.entries) {
      if ((e.value - p).distance < t) return e.key;
    }
    return r.contains(p) ? _Grip.move : null;
  }

  void _drag(Offset p, Rect view) {
    final g = _grip;
    if (g == null) return;
    // Normalised delta.
    final d = Offset(
      (p.dx - _startPos.dx) / view.width,
      (p.dy - _startPos.dy) / view.height,
    );
    final s = _startRect;
    var l = s.left, t = s.top, r = s.right, b = s.bottom;
    switch (g) {
      case _Grip.move:
        final dx = d.dx.clamp(-s.left, 1 - s.right);
        final dy = d.dy.clamp(-s.top, 1 - s.bottom);
        setState(() => _s = _s.copyWith(rect: s.shift(Offset(dx, dy))));
        return;
      case _Grip.tl:
        l += d.dx;
        t += d.dy;
      case _Grip.t:
        t += d.dy;
      case _Grip.tr:
        r += d.dx;
        t += d.dy;
      case _Grip.r:
        r += d.dx;
      case _Grip.br:
        r += d.dx;
        b += d.dy;
      case _Grip.b:
        b += d.dy;
      case _Grip.bl:
        l += d.dx;
        b += d.dy;
      case _Grip.l:
        l += d.dx;
    }
    const minN = 0.04;
    l = l.clamp(0.0, r - minN);
    t = t.clamp(0.0, b - minN);
    r = r.clamp(l + minN, 1.0);
    b = b.clamp(t + minN, 1.0);
    var n = Rect.fromLTRB(l, t, r, b);
    final ratio = _ratio;
    if (ratio != null) {
      final geo = _geo;
      final k = ratio * geo.box.height / geo.box.width; // n.w / n.h
      final vertical = g == _Grip.t || g == _Grip.b;
      var w = n.width, h = n.height;
      if (vertical) {
        w = h * k;
      } else {
        h = w / k;
      }
      // Anchor at the opposite side / corner.
      final ax = switch (g) {
        _Grip.tl || _Grip.bl || _Grip.l => s.right,
        _Grip.tr || _Grip.br || _Grip.r => s.left,
        _ => s.center.dx,
      };
      final ay = switch (g) {
        _Grip.tl || _Grip.tr || _Grip.t => s.bottom,
        _Grip.bl || _Grip.br || _Grip.b => s.top,
        _ => s.center.dy,
      };
      final left = switch (g) {
        _Grip.tl || _Grip.bl || _Grip.l => ax - w,
        _Grip.tr || _Grip.br || _Grip.r => ax,
        _ => ax - w / 2,
      };
      final top = switch (g) {
        _Grip.tl || _Grip.tr || _Grip.t => ay - h,
        _Grip.bl || _Grip.br || _Grip.b => ay,
        _ => ay - h / 2,
      };
      n = Rect.fromLTWH(left, top, w, h);
      if (n.left < -1e-6 ||
          n.top < -1e-6 ||
          n.right > 1 + 1e-6 ||
          n.bottom > 1 + 1e-6) {
        return; // would leave the image
      }
    }
    setState(() => _s = _s.copyWith(rect: n));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final g = _geo;
    final out = _outPx;
    final iw = widget.image.width.toDouble(),
        ih = widget.image.height.toDouble();
    final ratios = <(String, double?)>[
      (l.free, null),
      (l.original, _s.quarterTurns.isOdd ? ih / iw : iw / ih),
      ('1:1', 1),
      ('4:5', 4 / 5),
      ('5:4', 5 / 4),
      ('3:4', 3 / 4),
      ('4:3', 4 / 3),
      ('2:3', 2 / 3),
      ('3:2', 3 / 2),
      ('9:16', 9 / 16),
      ('16:9', 16 / 9),
      ('1:2', 1 / 2),
      ('2:1', 2),
    ];
    const dark = Color(0xFF111216);
    const panel = Color(0xFF1B1D23);
    final accent = theme.colorScheme.primary;

    Widget tool(
      IconData icon,
      String tip,
      VoidCallback onTap, {
      bool on = false,
      int turns = 0,
    }) => IconButton(
      tooltip: tip,
      onPressed: onTap,
      isSelected: on,
      style: IconButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: on ? accent : Colors.white10,
        fixedSize: const Size(48, 48),
      ),
      icon: RotatedBox(quarterTurns: turns, child: Icon(icon)),
    );

    return Theme(
      data: theme.copyWith(
        scaffoldBackgroundColor: dark,
        textTheme: theme.textTheme.apply(
          bodyColor: Colors.white,
          displayColor: Colors.white,
        ),
      ),
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: dark,
          foregroundColor: Colors.white,
          title: Text(
            l.crop,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          actions: [
            IconButton(
              tooltip: l.reset,
              onPressed: () => setState(() {
                _s = const CropState();
                _ratio = null;
              }),
              icon: const Icon(Icons.restart_alt_rounded),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 12),
              child: FilledButton.icon(
                onPressed: _busy ? null : _done,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded),
                label: Text(l.apply),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: LayoutBuilder(
                    builder: (context, c) {
                      const pad = 28.0;
                      final avail = Size(
                        c.maxWidth - pad * 2,
                        c.maxHeight - pad * 2,
                      );
                      final k = math.min(
                        avail.width / g.box.width,
                        avail.height / g.box.height,
                      );
                      final vw = g.box.width * k, vh = g.box.height * k;
                      final view = Rect.fromLTWH(
                        (c.maxWidth - vw) / 2,
                        (c.maxHeight - vh) / 2,
                        vw,
                        vh,
                      );
                      final r = Rect.fromLTRB(
                        view.left + _s.rect.left * vw,
                        view.top + _s.rect.top * vh,
                        view.left + _s.rect.right * vw,
                        view.top + _s.rect.bottom * vh,
                      );
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (d) {
                          _grip = _hit(d.localPosition, r);
                          _startRect = _s.rect;
                          _startPos = d.localPosition;
                        },
                        onPanUpdate: (d) => _drag(d.localPosition, view),
                        onPanEnd: (_) {
                          _grip = null;
                          // No empty corners after a straighten.
                          if (_s.straighten != 0) {
                            setState(
                              () => _s = _s.copyWith(
                                rect: _geo.fitInside(_s.rect),
                              ),
                            );
                          }
                        },
                        child: CustomPaint(
                          size: Size(c.maxWidth, c.maxHeight),
                          painter: _CropPainter(
                            geo: g,
                            view: view,
                            crop: r,
                            ellipse: _s.ellipse,
                            accent: accent,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              Container(
                color: panel,
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  children: [
                    Text(
                      '${out.width.round()} × ${out.height.round()} px',
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(
                      height: 72,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        children: [
                          for (final (name, ratio) in ratios)
                            _RatioChip(
                              label: name,
                              ratio: ratio,
                              selected: ratio == null
                                  ? _ratio == null
                                  : _ratio != null &&
                                        (_ratio! - ratio).abs() < 0.001,
                              accent: accent,
                              onTap: () => _setRatio(ratio),
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          tool(
                            Icons.rotate_left_rounded,
                            l.rotateLeft,
                            () => _turn(-1),
                          ),
                          tool(
                            Icons.rotate_right_rounded,
                            l.rotateRight,
                            () => _turn(1),
                          ),
                          tool(
                            Icons.flip_rounded,
                            l.flipH,
                            () => setState(
                              () => _s = _s.copyWith(flipH: !_s.flipH),
                            ),
                            on: _s.flipH,
                          ),
                          tool(
                            Icons.flip_rounded,
                            l.flipV,
                            () => setState(
                              () => _s = _s.copyWith(flipV: !_s.flipV),
                            ),
                            on: _s.flipV,
                            turns: 1,
                          ),
                          tool(
                            Icons.circle_outlined,
                            l.roundCrop,
                            () => setState(
                              () => _s = _s.copyWith(ellipse: !_s.ellipse),
                            ),
                            on: _s.ellipse,
                          ),
                          tool(
                            _ratio == null
                                ? Icons.lock_open_rounded
                                : Icons.lock_rounded,
                            l.keepRatio,
                            () => _setRatio(
                              _ratio == null
                                  ? out.width / math.max(1, out.height)
                                  : null,
                            ),
                            on: _ratio != null,
                          ),
                        ],
                      ),
                    ),
                    Theme(
                      data: theme,
                      child: Material(
                        color: theme.colorScheme.surface,
                        child: Column(
                          children: [
                            const SizedBox(height: 6),
                            PixSlider(
                              label: l.straighten,
                              value: _s.straighten,
                              min: -45,
                              max: 45,
                              defaultValue: 0,
                              format: (v) => '${v.toStringAsFixed(1)}°',
                              onChanged: _straighten,
                            ),
                            PixSlider(
                              label: l.resolution,
                              value: _s.resolution,
                              min: 0.1,
                              max: 1,
                              defaultValue: 1,
                              format: (v) => '${(v * 100).round()}%',
                              onChanged: (v) => setState(
                                () => _s = _s.copyWith(resolution: v),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RatioChip extends StatelessWidget {
  const _RatioChip({
    required this.label,
    required this.ratio,
    required this.selected,
    required this.accent,
    required this.onTap,
  });
  final String label;
  final double? ratio;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? accent : Colors.white70;
    final r = ratio;
    const box = 26.0;
    final w = r == null ? box : (r >= 1 ? box : box * r);
    final h = r == null ? box : (r >= 1 ? box / r : box);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 62,
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.16) : null,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: box + 2,
              child: Center(
                child: r == null
                    ? Icon(Icons.crop_free_rounded, color: color, size: 26)
                    : Container(
                        width: w,
                        height: h,
                        decoration: BoxDecoration(
                          border: Border.all(color: color, width: 2),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: TextDirection.ltr,
              style: TextStyle(
                color: color,
                fontSize: 11.5,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CropPainter extends CustomPainter {
  _CropPainter({
    required this.geo,
    required this.view,
    required this.crop,
    required this.ellipse,
    required this.accent,
  });
  final _Geo geo;
  final Rect view;
  final Rect crop;
  final bool ellipse;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final k = view.width / geo.box.width;
    canvas
      ..save()
      ..translate(view.left, view.top)
      ..scale(k);
    geo.paint(canvas);
    canvas.restore();

    // Dim everything outside the crop.
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size);
    ellipse ? outside.addOval(crop) : outside.addRect(crop);
    canvas.drawPath(
      outside,
      Paint()..color = Colors.black.withValues(alpha: 0.62),
    );

    // Rule-of-thirds grid.
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final x = crop.left + crop.width * i / 3;
      final y = crop.top + crop.height * i / 3;
      canvas
        ..drawLine(Offset(x, crop.top), Offset(x, crop.bottom), grid)
        ..drawLine(Offset(crop.left, y), Offset(crop.right, y), grid);
    }
    final frame = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white;
    canvas.drawRect(crop, frame);
    if (ellipse) {
      canvas.drawOval(crop, frame..color = accent);
    }
    // Handles: big dots at the corners, small ones on the edges.
    final dot = Paint()..color = Colors.white;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.black26;
    for (final p in [
      crop.topLeft,
      crop.topRight,
      crop.bottomRight,
      crop.bottomLeft,
    ]) {
      canvas
        ..drawCircle(p, 11, dot)
        ..drawCircle(p, 11, ring);
    }
    for (final p in [
      crop.topCenter,
      crop.centerRight,
      crop.bottomCenter,
      crop.centerLeft,
    ]) {
      canvas
        ..drawCircle(p, 7, dot)
        ..drawCircle(p, 7, ring);
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) =>
      old.crop != crop ||
      old.view != view ||
      old.ellipse != ellipse ||
      old.geo.state != geo.state;
}

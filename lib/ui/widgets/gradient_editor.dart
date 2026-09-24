import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_theme.dart';
import '../../core/colors/recent_colors.dart';
import '../../document/model/fill.dart';
import '../../l10n/app_localizations.dart';
import '../../projects/canvas_presets.dart';
import 'checkerboard.dart';
import 'color_picker.dart';
import 'pix_slider.dart';

/// Paints a [PixFill] into its box (used for every gradient preview).
class FillSwatchPainter extends CustomPainter {
  FillSwatchPainter(this.fill, {this.radius = 10});
  final PixFill fill;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, Radius.circular(radius)),
      fill.applyTo(Paint()..isAntiAlias = true, r),
    );
  }

  @override
  bool shouldRepaint(FillSwatchPainter old) =>
      old.fill != fill || old.radius != radius;
}

/// Opens the Photoshop-style gradient editor. [aspect] is the width/height
/// of what the gradient will paint, so the preview matches it.
Future<PixFill?> showGradientEditor(
  BuildContext context, {
  required PixFill initial,
  double aspect = 1,
}) => Navigator.of(context).push<PixFill>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _GradientEditor(initial: initial, aspect: aspect),
  ),
);

class _Stop {
  _Stop(this.color, this.pos);
  Color color;
  double pos;
}

enum _Handle { a, b, move }

class _GradientEditor extends StatefulWidget {
  const _GradientEditor({required this.initial, required this.aspect});
  final PixFill initial;
  final double aspect;

  @override
  State<_GradientEditor> createState() => _GradientEditorState();
}

class _GradientEditorState extends State<_GradientEditor> {
  late FillKind _kind;
  late List<_Stop> _stops;
  late double _angle;
  late double _scale;
  late Offset _center;
  int _sel = 0;
  _Handle? _drag;
  Offset _dragStart = Offset.zero;
  Offset _centerStart = Offset.zero;

  @override
  void initState() {
    super.initState();
    _load(widget.initial);
  }

  void _load(PixFill f) {
    final g = f.isGradient
        ? f
        : PixFill.linear([
            f.primary,
            Color.lerp(f.primary, Colors.white, 0.7)!,
          ], angle: 90);
    _kind = g.kind;
    _stops = [
      for (var i = 0; i < g.colors.length; i++)
        _Stop(g.colors[i], g.effectiveStops[i]),
    ];
    _angle = g.angle;
    _scale = g.scale;
    _center = g.center;
    _sel = _sel.clamp(0, _stops.length - 1);
  }

  PixFill get _fill {
    final sorted = [..._stops]..sort((a, b) => a.pos.compareTo(b.pos));
    return PixFill.gradient(
      _kind,
      [for (final s in sorted) s.color],
      stops: [for (final s in sorted) s.pos],
      angle: _angle,
      scale: _scale,
      center: _center,
    );
  }

  Color _colorAt(double t) {
    final sorted = [..._stops]..sort((a, b) => a.pos.compareTo(b.pos));
    if (t <= sorted.first.pos) return sorted.first.color;
    for (var i = 0; i + 1 < sorted.length; i++) {
      final a = sorted[i], b = sorted[i + 1];
      if (t <= b.pos) {
        final k = b.pos == a.pos ? 0.0 : (t - a.pos) / (b.pos - a.pos);
        return Color.lerp(a.color, b.color, k)!;
      }
    }
    return sorted.last.color;
  }

  void _addStop([double? at]) {
    HapticFeedback.selectionClick();
    final sorted = [..._stops]..sort((a, b) => a.pos.compareTo(b.pos));
    var pos = at;
    if (pos == null) {
      final cur = _stops[_sel];
      final i = sorted.indexOf(cur);
      final next = i + 1 < sorted.length ? sorted[i + 1] : null;
      pos = next == null
          ? (cur.pos + (i > 0 ? sorted[i - 1].pos : 0)) / 2
          : (cur.pos + next.pos) / 2;
    }
    final s = _Stop(_colorAt(pos), pos);
    setState(() {
      _stops.add(s);
      _sel = _stops.length - 1;
    });
  }

  void _deleteStop() {
    if (_stops.length <= 2) return;
    HapticFeedback.selectionClick();
    setState(() {
      _stops.removeAt(_sel);
      _sel = _sel.clamp(0, _stops.length - 1);
    });
  }

  void _step(int d) {
    final sorted = [..._stops]..sort((a, b) => a.pos.compareTo(b.pos));
    final i = sorted.indexOf(_stops[_sel]);
    final j = (i + d).clamp(0, sorted.length - 1);
    setState(() => _sel = _stops.indexOf(sorted[j]));
  }

  void _reverse() {
    HapticFeedback.selectionClick();
    setState(() {
      for (final s in _stops) {
        s.pos = 1 - s.pos;
      }
    });
  }

  void _distribute() {
    final sorted = [..._stops]..sort((a, b) => a.pos.compareTo(b.pos));
    setState(() {
      for (var i = 0; i < sorted.length; i++) {
        sorted[i].pos = i / (sorted.length - 1);
      }
    });
  }

  Future<void> _pickColor() async {
    final s = _stops[_sel];
    final c = await showPixColorPicker(
      context,
      initial: s.color,
      onLive: (c) => setState(() => s.color = c),
    );
    if (c != null) {
      RecentColors.instance.addColor(c);
      setState(() => s.color = c);
    }
  }

  // ------------------------------------------------------------ handles

  (Offset a, Offset b) _handles(Rect r) {
    final f = _fill;
    final c = f.centerIn(r);
    final rad = _angle * math.pi / 180;
    final d = Offset(math.cos(rad), math.sin(rad));
    return switch (_kind) {
      FillKind.linear => (c - d * f.linearHalf(r), c + d * f.linearHalf(r)),
      FillKind.reflected => (c, c + d * f.linearHalf(r)),
      FillKind.radial => (c, c + d * f.radialRadius(r)),
      _ => (c, c + d * r.shortestSide * 0.32),
    };
  }

  void _dragTo(Rect r, Offset p) {
    final (a0, b0) = _handles(r);
    var a = a0, b = b0;
    switch (_drag) {
      case _Handle.a:
        if (_kind == FillKind.linear) {
          a = p;
        } else {
          // Move the centre, keep the direction handle's offset.
          b = p + (b0 - a0);
          a = p;
        }
      case _Handle.b:
        b = p;
      case _Handle.move:
        final delta = p - _dragStart;
        // (both in the layer's true proportions)
        setState(
          () => _center =
              _centerStart +
              Offset(delta.dx / (r.width / 2), delta.dy / (r.height / 2)),
        );
        return;
      case null:
        return;
    }
    final v = b - a;
    if (v.distance < 2) return;
    setState(() {
      _angle = (math.atan2(v.dy, v.dx) * 180 / math.pi) % 360;
      final rad = _angle * math.pi / 180;
      final base =
          (r.width * math.cos(rad).abs() + r.height * math.sin(rad).abs()) / 2;
      final c = _kind == FillKind.linear ? (a + b) / 2 : a;
      _center = Offset(
        (c.dx - r.center.dx) / (r.width / 2),
        (c.dy - r.center.dy) / (r.height / 2),
      );
      switch (_kind) {
        case FillKind.linear:
          _scale = (v.distance / 2 / base).clamp(0.05, 20.0);
        case FillKind.reflected:
          _scale = (v.distance / base).clamp(0.05, 20.0);
        case FillKind.radial:
          _scale = (v.distance / (r.shortestSide / 2 + r.longestSide / 4))
              .clamp(0.05, 20.0);
        default:
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pix = PixColors.of(context);
    final fill = _fill;
    final sel = _stops[_sel];

    Widget round(IconData icon, String tip, VoidCallback? onTap) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: IconButton.filled(
        tooltip: tip,
        onPressed: onTap,
        iconSize: 20,
        constraints: const BoxConstraints.tightFor(width: 42, height: 42),
        padding: EdgeInsets.zero,
        icon: Icon(icon),
      ),
    );
    final narrow = MediaQuery.sizeOf(context).width < 520;
    ButtonSegment<FillKind> seg(FillKind k, IconData i, String label) =>
        ButtonSegment(
          value: k,
          tooltip: label,
          icon: Icon(i, size: 20),
          // Phones: icons only, so labels never wrap or get cut.
          label: narrow ? null : Text(label),
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(l.gradient),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: FilledButton.icon(
              onPressed: () => Navigator.pop(context, fill),
              icon: const Icon(Icons.check_rounded),
              label: Text(l.apply),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: SegmentedButton<FillKind>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: [
                  seg(FillKind.linear, Icons.gradient_rounded, l.linear),
                  seg(FillKind.radial, Icons.radio_button_checked, l.radial),
                  seg(FillKind.sweep, Icons.rotate_right_rounded, l.angular),
                  seg(
                    FillKind.reflected,
                    Icons.compare_arrows_rounded,
                    l.reflected,
                  ),
                ],
                selected: {_kind},
                onSelectionChanged: (s) => setState(() => _kind = s.first),
              ),
            ),
            // Live preview with draggable start / end handles. Very wide
            // or tall layers (a line of text) are shown stretched into a
            // comfortable box; handles and drags map back exactly.
            Expanded(
              flex: 5,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: LayoutBuilder(
                  builder: (context, c) {
                    final box = c.biggest;
                    final shown = widget.aspect.clamp(0.55, 1.8);
                    var w = box.width, h = w / shown;
                    if (h > box.height - 16) {
                      h = math.max(40.0, box.height - 16);
                      w = math.min(box.width, h * shown);
                    }
                    final r = Rect.fromLTWH(
                      (box.width - w) / 2,
                      (box.height - h) / 2,
                      w,
                      h,
                    );
                    // The layer's true proportions.
                    final v = widget.aspect >= 1
                        ? Rect.fromLTWH(0, 0, w, w / widget.aspect)
                        : Rect.fromLTWH(0, 0, h * widget.aspect, h);
                    final sx = r.width / v.width, sy = r.height / v.height;
                    Offset toShown(Offset p) =>
                        r.topLeft + Offset(p.dx * sx, p.dy * sy);
                    Offset toTrue(Offset p) =>
                        Offset((p.dx - r.left) / sx, (p.dy - r.top) / sy);
                    final (a, b) = _handles(v);
                    final sa = toShown(a), sb = toShown(b);
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (d) {
                        final p = d.localPosition;
                        _dragStart = toTrue(p);
                        _centerStart = _center;
                        _drag = (p - sb).distance < 36
                            ? _Handle.b
                            : (p - sa).distance < 36
                            ? _Handle.a
                            : _Handle.move;
                      },
                      onPanUpdate: (d) => _dragTo(v, toTrue(d.localPosition)),
                      onPanEnd: (_) => _drag = null,
                      child: Stack(
                        children: [
                          Positioned.fromRect(
                            rect: r,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  CheckerboardBox(
                                    a: pix.checkerA,
                                    b: pix.checkerB,
                                    cell: 10,
                                  ),
                                  CustomPaint(
                                    painter: _StretchedFillPainter(
                                      fill,
                                      v,
                                      sx,
                                      sy,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _HandlesPainter(
                                a: sa,
                                b: sb,
                                line: _kind != FillKind.radial,
                                accent: scheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            // Everything below scrolls on short screens.
            Flexible(
              flex: 6,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 10),
                    // Colour stops.
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: _StopsBar(
                        stops: _stops,
                        selected: _sel,
                        fill: fill,
                        onSelect: (i) => setState(() => _sel = i),
                        onMove: (i, pos) =>
                            setState(() => _stops[i].pos = pos.clamp(0.0, 1.0)),
                        onRemove: (i) {
                          if (_stops.length <= 2) return;
                          setState(() {
                            _stops.removeAt(i);
                            _sel = _sel.clamp(0, _stops.length - 1);
                          });
                        },
                        onAddAt: _addStop,
                        onEdit: _pickColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        round(Icons.add_rounded, l.addStop, () => _addStop()),
                        round(
                          Icons.remove_rounded,
                          l.deleteStop,
                          _stops.length > 2 ? _deleteStop : null,
                        ),
                        round(
                          Icons.chevron_left_rounded,
                          l.previous,
                          () => _step(-1),
                        ),
                        round(Icons.swap_horiz_rounded, l.reverse, _reverse),
                        round(
                          Icons.chevron_right_rounded,
                          l.next,
                          () => _step(1),
                        ),
                        round(
                          Icons.format_color_fill_rounded,
                          l.color,
                          _pickColor,
                        ),
                        round(
                          Icons.align_horizontal_center_rounded,
                          l.distribute,
                          _distribute,
                        ),
                      ],
                    ),
                    PixSlider(
                      label: l.location,
                      value: sel.pos,
                      min: 0,
                      max: 1,
                      format: (v) => '${(v * 100).round()}%',
                      onChanged: (v) => setState(() => sel.pos = v),
                    ),
                    PixSlider(
                      label: l.opacity,
                      value: sel.color.a,
                      min: 0,
                      max: 1,
                      defaultValue: 1,
                      format: (v) => '${(v * 100).round()}%',
                      onChanged: (v) => setState(
                        () => sel.color = sel.color.withValues(alpha: v),
                      ),
                    ),
                    if (_kind != FillKind.radial)
                      PixSlider(
                        label: l.angle,
                        value: _angle,
                        min: 0,
                        max: 360,
                        defaultValue: 90,
                        format: (v) => '${v.round()}°',
                        onChanged: (v) => setState(() => _angle = v),
                      ),
                    if (_kind != FillKind.sweep)
                      PixSlider(
                        label: l.scale,
                        value: _scale,
                        min: 0.1,
                        max: 3,
                        defaultValue: 1,
                        format: (v) => '${(v * 100).round()}%',
                        onChanged: (v) => setState(() => _scale = v),
                      ),
                    // Presets and recently used gradients.
                    SizedBox(
                      height: 58,
                      child: ListenableBuilder(
                        listenable: RecentColors.instance,
                        builder: (context, _) => ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                          children: [
                            for (final g in [
                              ...RecentColors.instance.gradients,
                              for (final c in kBackgroundGradients)
                                PixFill.linear(c, angle: 90),
                            ])
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    setState(() {
                                      final k = _kind, a = _angle;
                                      final sc = _scale, c = _center;
                                      _load(g);
                                      // Presets bring colours; keep the geometry.
                                      if (g.kind == FillKind.linear) {
                                        _kind = k;
                                        _angle = a;
                                        _scale = sc;
                                        _center = c;
                                      }
                                    });
                                  },
                                  child: SizedBox(
                                    width: 46,
                                    height: 46,
                                    child: CustomPaint(
                                      painter: FillSwatchPainter(g),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Paints [fill] laid out in [v] (the layer's proportions), stretched by
/// [sx]/[sy] into the preview box.
class _StretchedFillPainter extends CustomPainter {
  _StretchedFillPainter(this.fill, this.v, this.sx, this.sy);
  final PixFill fill;
  final Rect v;
  final double sx, sy;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..scale(sx, sy)
      ..drawRect(v, fill.applyTo(Paint()..isAntiAlias = true, v))
      ..restore();
  }

  @override
  bool shouldRepaint(_StretchedFillPainter old) =>
      old.fill != fill || old.v != v || old.sx != sx || old.sy != sy;
}

class _HandlesPainter extends CustomPainter {
  _HandlesPainter({
    required this.a,
    required this.b,
    required this.line,
    required this.accent,
  });
  final Offset a, b;
  final bool line;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.35)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final white = Paint()
      ..color = Colors.white
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawLine(a, b, shadow)
      ..drawLine(a, b, white);
    // Direction arrows along the line.
    final v = b - a;
    if (line && v.distance > 60) {
      final u = v / v.distance;
      final n = Offset(-u.dy, u.dx);
      for (final t in [0.35, 0.65]) {
        final p = a + v * t;
        final path = Path()
          ..moveTo((p - u * 8 + n * 7).dx, (p - u * 8 + n * 7).dy)
          ..lineTo(p.dx, p.dy)
          ..lineTo((p - u * 8 - n * 7).dx, (p - u * 8 - n * 7).dy);
        canvas
          ..drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 4
              ..color = Colors.black.withValues(alpha: 0.35),
          )
          ..drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = Colors.white,
          );
      }
    }
    for (final (p, big) in [(a, true), (b, false)]) {
      canvas
        ..drawCircle(
          p,
          big ? 15 : 13,
          Paint()..color = Colors.black.withValues(alpha: 0.3),
        )
        ..drawCircle(p, big ? 13 : 11, Paint()..color = Colors.white)
        ..drawCircle(p, big ? 5 : 6, Paint()..color = accent);
    }
  }

  @override
  bool shouldRepaint(_HandlesPainter old) =>
      old.a != a || old.b != b || old.line != line;
}

/// The colour-stop ramp: tap a marker to select it, drag it to move it,
/// drag it down to remove it, tap the ramp to add a stop there, and
/// double-tap a marker to change its colour.
class _StopsBar extends StatelessWidget {
  const _StopsBar({
    required this.stops,
    required this.selected,
    required this.fill,
    required this.onSelect,
    required this.onMove,
    required this.onRemove,
    required this.onAddAt,
    required this.onEdit,
  });
  final List<_Stop> stops;
  final int selected;
  final PixFill fill;
  final ValueChanged<int> onSelect;
  final void Function(int i, double pos) onMove;
  final ValueChanged<int> onRemove;
  final ValueChanged<double> onAddAt;
  final VoidCallback onEdit;

  static const _barH = 34.0, _markH = 30.0;

  @override
  Widget build(BuildContext context) {
    final pix = PixColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          final ramp = PixFill.gradient(
            FillKind.linear,
            fill.colors,
            stops: fill.effectiveStops,
            angle: 0,
          );
          int? hit(Offset p) {
            int? best;
            var bd = 22.0;
            for (var i = 0; i < stops.length; i++) {
              final d = (stops[i].pos * w - p.dx).abs();
              if (d < bd) {
                bd = d;
                best = i;
              }
            }
            return best;
          }

          var dragging = -1;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) {
              final i = hit(d.localPosition);
              if (i != null && d.localPosition.dy > _barH - 4) {
                onSelect(i);
              } else if (d.localPosition.dy <= _barH) {
                onAddAt((d.localPosition.dx / w).clamp(0.0, 1.0));
              } else if (i != null) {
                onSelect(i);
              }
            },
            onDoubleTap: onEdit,
            onHorizontalDragStart: (d) {
              dragging = hit(d.localPosition) ?? -1;
              if (dragging >= 0) onSelect(dragging);
            },
            onHorizontalDragUpdate: (d) {
              if (dragging < 0) return;
              if (d.localPosition.dy > _barH + _markH + 50) {
                onRemove(dragging);
                dragging = -1;
                return;
              }
              onMove(dragging, d.localPosition.dx / w);
            },
            child: SizedBox(
              height: _barH + _markH,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    height: _barH,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CheckerboardBox(
                        a: pix.checkerA,
                        b: pix.checkerB,
                        cell: 6,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    height: _barH,
                    child: CustomPaint(
                      painter: FillSwatchPainter(ramp, radius: 8),
                    ),
                  ),
                  for (var i = 0; i < stops.length; i++)
                    Positioned(
                      left: stops[i].pos * w - 13,
                      top: _barH - 2,
                      child: _Marker(
                        color: stops[i].color,
                        selected: i == selected,
                        accent: scheme.primary,
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Marker extends StatelessWidget {
  const _Marker({
    required this.color,
    required this.selected,
    required this.accent,
  });
  final Color color;
  final bool selected;
  final Color accent;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(26, 32),
    painter: _MarkerPainter(color, selected ? accent : Colors.white),
  );
}

class _MarkerPainter extends CustomPainter {
  _MarkerPainter(this.color, this.ring);
  final Color color, ring;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final path = Path()
      ..moveTo(w / 2, 0)
      ..lineTo(w, 8)
      ..lineTo(w, size.height)
      ..lineTo(0, size.height)
      ..lineTo(0, 8)
      ..close();
    canvas
      ..drawShadow(path, Colors.black, 2, false)
      ..drawPath(path, Paint()..color = ring)
      ..drawRect(
        Rect.fromLTWH(4, 10, w - 8, size.height - 14),
        Paint()..color = color.withValues(alpha: 1),
      );
  }

  @override
  bool shouldRepaint(_MarkerPainter old) =>
      old.color != color || old.ring != ring;
}

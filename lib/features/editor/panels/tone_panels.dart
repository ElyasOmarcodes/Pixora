import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../document/effects/tone.dart';
import '../../../l10n/app_localizations.dart';
import 'effect_panels.dart';

const _channelColors = {
  ToneChannel.rgb: Color(0xFF9E9E9E),
  ToneChannel.red: Color(0xFFE53935),
  ToneChannel.green: Color(0xFF43A047),
  ToneChannel.blue: Color(0xFF1E88E5),
};

String _channelLabel(AppLocalizations l, ToneChannel c) => switch (c) {
  ToneChannel.rgb => 'RGB',
  ToneChannel.red => l.toneRed,
  ToneChannel.green => l.toneGreen,
  ToneChannel.blue => l.toneBlue,
};

/// RGB · Red · Green · Blue.
class _ChannelBar extends StatelessWidget {
  const _ChannelBar({required this.value, required this.onChanged});
  final ToneChannel value;
  final ValueChanged<ToneChannel> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SegmentedButton<ToneChannel>(
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: [
        for (final c in ToneChannel.values)
          ButtonSegment(
            value: c,
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: _channelColors[c],
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    _channelLabel(l, c),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
      selected: {value},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

/// A compact numeric field (0..255 or a gamma).
class _NumField extends StatefulWidget {
  const _NumField({
    required this.label,
    required this.value,
    required this.onSubmit,
    this.decimals = 0,
    this.enabled = true,
  });
  final String label;
  final double value;
  final int decimals;
  final bool enabled;
  final ValueChanged<double> onSubmit;

  @override
  State<_NumField> createState() => _NumFieldState();
}

class _NumFieldState extends State<_NumField> {
  late final _c = TextEditingController(text: _fmt(widget.value));
  final _focus = FocusNode();

  String _fmt(double v) => v.toStringAsFixed(widget.decimals);

  @override
  void didUpdateWidget(_NumField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && _fmt(widget.value) != _c.text) {
      _c.text = _fmt(widget.value);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    final v = double.tryParse(_c.text.replaceAll(',', '.'));
    if (v != null) widget.onSubmit(v);
    _c.text = _fmt(widget.value);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 74,
      child: TextField(
        controller: _c,
        focusNode: _focus,
        enabled: widget.enabled,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        keyboardType: TextInputType.numberWithOptions(
          decimal: widget.decimals > 0,
        ),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[0-9.,]'))],
        onSubmitted: (_) => _submit(),
        onTapOutside: (_) {
          if (_focus.hasFocus) {
            _submit();
            _focus.unfocus();
          }
        },
        style: const TextStyle(fontWeight: FontWeight.w700),
        decoration: InputDecoration(
          labelText: widget.label,
          isDense: true,
          filled: true,
          fillColor: scheme.onSurface.withValues(alpha: 0.05),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 6,
            vertical: 8,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

/// Loads the histogram once and repaints when it arrives.
class _HistogramLoader extends StatelessWidget {
  const _HistogramLoader({required this.future, required this.builder});
  final Future<ToneHistogram?>? future;
  final Widget Function(ToneHistogram? h) builder;

  @override
  Widget build(BuildContext context) => FutureBuilder<ToneHistogram?>(
    future: future,
    builder: (context, snap) => builder(snap.data),
  );
}

/// Draws a histogram as soft bars filling [rect].
void _paintHistogram(Canvas c, Rect rect, List<int>? bins, Color color) {
  if (bins == null) return;
  // Scale to a high percentile so one spike does not flatten the rest.
  final sorted = [...bins]..sort();
  final top = math.max(1, sorted[(sorted.length * 0.995).floor()]);
  final path = Path()..moveTo(rect.left, rect.bottom);
  for (var i = 0; i < 256; i++) {
    final x = rect.left + rect.width * (i + 0.5) / 256;
    final h = (bins[i] / top).clamp(0.0, 1.0) * rect.height;
    path.lineTo(x, rect.bottom - h);
  }
  path
    ..lineTo(rect.right, rect.bottom)
    ..close();
  c.drawPath(path, Paint()..color = color);
}

// ─────────────────────────────── Curves

/// Photoshop's Curves: a channel picker, presets, the curve graph with a
/// histogram behind it, and exact input / output values for the selected
/// point.
class CurvesEditor extends StatefulWidget {
  const CurvesEditor({super.key, required this.ctx});
  final FxEffectContext ctx;

  @override
  State<CurvesEditor> createState() => _CurvesEditorState();
}

class _CurvesEditorState extends State<CurvesEditor> {
  int? _selected;
  bool _fineGrid = false;

  ToneCurves get _curves =>
      ToneCurves.decode(widget.ctx.effect.string('curves'));

  ToneChannel get _channel =>
      ToneChannel.values[widget.ctx.effect
          .number('channel', 0)
          .round()
          .clamp(0, 3)];

  void _write(ToneCurves c, {bool live = false}) =>
      widget.ctx.set('curves', c.encode(), live: live);

  void _setPoints(List<Offset> pts, {bool live = false}) =>
      _write(_curves.withChannel(_channel, pts), live: live);

  void _preset(String key) {
    final p = ToneCurves.presets[key];
    if (p == null) return;
    setState(() => _selected = null);
    _write(ToneCurves.decode(p));
  }

  Future<void> _auto() async {
    final h = await widget.ctx.histogram;
    if (h == null) return;
    final (lo, hi) = ToneLevels.autoPoints(h.luminosity);
    setState(() => _selected = null);
    _write(
      ToneCurves({
        ToneChannel.rgb: [Offset(lo, 0), Offset(hi, 255)],
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final curves = _curves;
    final ch = _channel;
    final pts = curves.points[ch]!;
    final sel = _selected != null && _selected! < pts.length ? _selected : null;
    final presets = {
      'default': l.presetDefault,
      'colorNegative': l.presetColorNegative,
      'crossProcess': l.presetCrossProcess,
      'darker': l.presetDarker,
      'increaseContrast': l.presetIncreaseContrast,
      'lighter': l.presetLighter,
      'linearContrast': l.presetLinearContrast,
      'mediumContrast': l.presetMediumContrast,
      'negative': l.presetNegative,
      'strongContrast': l.presetStrongContrast,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: PopupMenuButton<String>(
                  tooltip: l.tonePreset,
                  onSelected: _preset,
                  itemBuilder: (_) => [
                    for (final e in presets.entries)
                      PopupMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: l.tonePreset,
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.auto_awesome_rounded, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            presets.entries
                                    .where(
                                      (e) =>
                                          ToneCurves.decode(
                                            ToneCurves.presets[e.key],
                                          ).encode() ==
                                          curves.encode(),
                                    )
                                    .map((e) => e.value)
                                    .firstOrNull ??
                                '—',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(Icons.arrow_drop_down_rounded),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: widget.ctx.histogram == null ? null : _auto,
                icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                label: Text(l.toneAuto),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _ChannelBar(
            value: ch,
            onChanged: (c) {
              setState(() => _selected = null);
              widget.ctx.set('channel', c.index);
            },
          ),
          const SizedBox(height: 10),
          _HistogramLoader(
            future: widget.ctx.histogram,
            builder: (h) => _CurveGraph(
              curves: curves,
              channel: ch,
              selected: sel,
              fineGrid: _fineGrid,
              histogram: h?.of(ch),
              onSelect: (i) => setState(() => _selected = i),
              onChanged: (p, {live = false}) => _setPoints(p, live: live),
              onEnd: widget.ctx.commit,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _NumField(
                label: l.toneInput,
                value: sel == null ? 0 : pts[sel].dx,
                enabled: sel != null,
                onSubmit: (v) {
                  if (sel == null) return;
                  final p = [...pts];
                  final lo = sel == 0 ? 0.0 : p[sel - 1].dx + 1;
                  final hi = sel == p.length - 1 ? 255.0 : p[sel + 1].dx - 1;
                  p[sel] = Offset(v.clamp(lo, hi), p[sel].dy);
                  _setPoints(p);
                },
              ),
              const SizedBox(width: 8),
              _NumField(
                label: l.toneOutput,
                value: sel == null ? 0 : pts[sel].dy,
                enabled: sel != null,
                onSubmit: (v) {
                  if (sel == null) return;
                  final p = [...pts];
                  p[sel] = Offset(p[sel].dx, v.clamp(0, 255));
                  _setPoints(p);
                },
              ),
              const Spacer(),
              IconButton(
                tooltip: l.toneDeletePoint,
                onPressed: sel == null || pts.length <= 2
                    ? null
                    : () {
                        setState(() => _selected = null);
                        _setPoints([...pts]..removeAt(sel));
                      },
                icon: const Icon(Icons.remove_circle_outline_rounded),
              ),
              IconButton(
                tooltip: l.grid,
                isSelected: _fineGrid,
                onPressed: () => setState(() => _fineGrid = !_fineGrid),
                icon: const Icon(Icons.grid_4x4_rounded),
                selectedIcon: const Icon(Icons.grid_on_rounded),
              ),
              IconButton(
                tooltip: l.toneResetChannel,
                onPressed: () {
                  setState(() => _selected = null);
                  _setPoints(ToneCurves.identity);
                },
                icon: const Icon(Icons.restart_alt_rounded),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            l.toneCurveHint,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _CurveGraph extends StatefulWidget {
  const _CurveGraph({
    required this.curves,
    required this.channel,
    required this.selected,
    required this.fineGrid,
    required this.histogram,
    required this.onSelect,
    required this.onChanged,
    required this.onEnd,
  });
  final ToneCurves curves;
  final ToneChannel channel;
  final int? selected;
  final bool fineGrid;
  final List<int>? histogram;
  final ValueChanged<int?> onSelect;
  final void Function(List<Offset> p, {bool live}) onChanged;
  final VoidCallback onEnd;

  @override
  State<_CurveGraph> createState() => _CurveGraphState();
}

class _CurveGraphState extends State<_CurveGraph> {
  int? _drag;
  bool _off = false;
  List<Offset> _pts = const [];

  Offset _toValue(Offset local, Size size) => Offset(
    (local.dx / size.width * 255).clamp(0.0, 255.0),
    ((1 - local.dy / size.height) * 255).clamp(0.0, 255.0),
  );

  Offset _toLocal(Offset v, Size size) =>
      Offset(v.dx / 255 * size.width, (1 - v.dy / 255) * size.height);

  int? _hit(Offset local, Size size, List<Offset> pts) {
    int? best;
    var bestD = 24.0;
    for (var i = 0; i < pts.length; i++) {
      final d = (_toLocal(pts[i], size) - local).distance;
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }

  /// A new point on the curve at [x] (input level).
  (List<Offset>, int)? _insert(double x, List<Offset> pts) {
    if (pts.length >= ToneCurves.maxPoints) return null;
    final y = ToneCurves.sample(pts)[x.round().clamp(0, 255)];
    final p = [...pts];
    var i = p.indexWhere((o) => o.dx > x);
    if (i < 0) i = p.length;
    if ((i > 0 && (x - p[i - 1].dx).abs() < 2) ||
        (i < p.length && (p[i].dx - x).abs() < 2)) {
      return null;
    }
    p.insert(i, Offset(x, y));
    return (p, i);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Directionality(
      // The graph reads left to right in every language, like Photoshop.
      textDirection: TextDirection.ltr,
      child: AspectRatio(
        aspectRatio: 1.25,
        child: LayoutBuilder(
          builder: (context, box) {
            final size = box.biggest;
            final pts = widget.curves.points[widget.channel]!;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) {
                final hit = _hit(d.localPosition, size, pts);
                if (hit != null) {
                  widget.onSelect(hit);
                  return;
                }
                final v = _toValue(d.localPosition, size);
                final ins = _insert(v.dx, pts);
                if (ins == null) return;
                widget.onChanged(ins.$1);
                widget.onSelect(ins.$2);
              },
              onPanStart: (d) {
                var hit = _hit(d.localPosition, size, pts);
                var list = pts;
                if (hit == null) {
                  final v = _toValue(d.localPosition, size);
                  final ins = _insert(v.dx, pts);
                  if (ins == null) return;
                  list = ins.$1;
                  hit = ins.$2;
                }
                _pts = list;
                _drag = hit;
                _off = false;
                widget.onSelect(hit);
              },
              onPanUpdate: (d) {
                final i = _drag;
                if (i == null) return;
                final p = [..._pts];
                final local = d.localPosition;
                // Dragged well off the graph: the point goes (not ends).
                final outside =
                    local.dx < -28 ||
                    local.dy < -28 ||
                    local.dx > size.width + 28 ||
                    local.dy > size.height + 28;
                final end = i == 0 || i == p.length - 1;
                if (outside && !end && p.length > 2) {
                  _off = true;
                  widget.onChanged([...p]..removeAt(i), live: true);
                  return;
                }
                _off = false;
                final v = _toValue(local, size);
                final lo = i == 0 ? 0.0 : p[i - 1].dx + 1;
                final hi = i == p.length - 1 ? 255.0 : p[i + 1].dx - 1;
                p[i] = Offset(v.dx.clamp(lo, hi), v.dy);
                _pts = p;
                widget.onChanged(p, live: true);
              },
              onPanEnd: (_) {
                if (_drag == null) return;
                if (_off) {
                  widget.onSelect(null);
                  widget.onChanged([..._pts]..removeAt(_drag!));
                } else {
                  widget.onChanged(_pts);
                }
                _drag = null;
                widget.onEnd();
              },
              child: CustomPaint(
                size: size,
                painter: _CurvePainter(
                  curves: widget.curves,
                  channel: widget.channel,
                  selected: widget.selected,
                  fineGrid: widget.fineGrid,
                  histogram: widget.histogram,
                  background: scheme.onSurface.withValues(alpha: 0.04),
                  grid: scheme.onSurface.withValues(alpha: 0.12),
                  ink: scheme.onSurface,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CurvePainter extends CustomPainter {
  _CurvePainter({
    required this.curves,
    required this.channel,
    required this.selected,
    required this.fineGrid,
    required this.histogram,
    required this.background,
    required this.grid,
    required this.ink,
  });
  final ToneCurves curves;
  final ToneChannel channel;
  final int? selected;
  final bool fineGrid;
  final List<int>? histogram;
  final Color background, grid, ink;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, const Radius.circular(12)),
      Paint()..color = background,
    );
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(r, const Radius.circular(12)));
    _paintHistogram(
      canvas,
      r,
      histogram,
      (channel == ToneChannel.rgb ? ink : _channelColors[channel]!).withValues(
        alpha: 0.12,
      ),
    );
    // Grid (quarters or tenths) and the untouched diagonal.
    final g = Paint()
      ..color = grid
      ..strokeWidth = 1;
    final n = fineGrid ? 10 : 4;
    for (var i = 1; i < n; i++) {
      final x = size.width * i / n, y = size.height * i / n;
      canvas
        ..drawLine(Offset(x, 0), Offset(x, size.height), g)
        ..drawLine(Offset(0, y), Offset(size.width, y), g);
    }
    canvas.drawLine(Offset(0, size.height), Offset(size.width, 0), g);
    Path curvePath(List<Offset> pts) {
      final s = ToneCurves.sample(pts);
      final path = Path();
      for (var i = 0; i < 256; i++) {
        final o = Offset(i / 255 * size.width, (1 - s[i] / 255) * size.height);
        i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
      }
      return path;
    }

    // In RGB, the channels' own curves show faintly, as in Photoshop.
    if (channel == ToneChannel.rgb) {
      for (final c in ToneChannel.values.skip(1)) {
        final p = curves.points[c]!;
        if (p.length == 2 &&
            p[0] == ToneCurves.identity[0] &&
            p[1] == ToneCurves.identity[1]) {
          continue;
        }
        canvas.drawPath(
          curvePath(p),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = _channelColors[c]!.withValues(alpha: 0.6),
        );
      }
    }
    final pts = curves.points[channel]!;
    final color = channel == ToneChannel.rgb ? ink : _channelColors[channel]!;
    canvas.drawPath(
      curvePath(pts),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
    for (var i = 0; i < pts.length; i++) {
      final o = Offset(
        pts[i].dx / 255 * size.width,
        (1 - pts[i].dy / 255) * size.height,
      );
      final rect = Rect.fromCenter(center: o, width: 11, height: 11);
      canvas.drawRect(
        rect,
        Paint()..color = i == selected ? color : background,
      );
      canvas.drawRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..color = color,
      );
    }
    canvas.restore();
    // Input and output ramps along the edges.
    final ramp = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF000000), Color(0xFFFFFFFF)],
      ).createShader(Rect.fromLTWH(0, size.height - 4, size.width, 4));
    canvas.drawRect(Rect.fromLTWH(0, size.height - 4, size.width, 4), ramp);
  }

  @override
  bool shouldRepaint(_CurvePainter old) =>
      old.curves.encode() != curves.encode() ||
      old.channel != channel ||
      old.selected != selected ||
      old.fineGrid != fineGrid ||
      old.histogram != histogram ||
      old.ink != ink;
}

// ─────────────────────────────── Levels

/// Photoshop's Levels: presets, channel, histogram with input black /
/// grey / white sliders and output sliders, exact values and Auto.
class LevelsEditor extends StatelessWidget {
  const LevelsEditor({super.key, required this.ctx});
  final FxEffectContext ctx;

  ToneChannel get _channel =>
      ToneChannel.values[ctx.effect.number('channel', 0).round().clamp(0, 3)];

  LevelsChannel _levels(ToneChannel c) =>
      ToneLevels.read((k, f) => ctx.effect.number(k, f)).channels[c]!;

  void _set(String field, double v, {bool live = false}) =>
      ctx.set(ToneLevels.param(_channel, field), v, live: live);

  void _apply(ToneChannel c, (double, double, double, double, double) p) {
    final (b, g, w, ob, ow) = p;
    ctx.set(ToneLevels.param(c, 'inBlack'), b, live: true);
    ctx.set(ToneLevels.param(c, 'gamma'), g, live: true);
    ctx.set(ToneLevels.param(c, 'inWhite'), w, live: true);
    ctx.set(ToneLevels.param(c, 'outBlack'), ob, live: true);
    ctx.set(ToneLevels.param(c, 'outWhite'), ow, live: true);
    ctx.commit();
  }

  Future<void> _auto() async {
    final h = await ctx.histogram;
    if (h == null) return;
    final (lo, hi) = ToneLevels.autoPoints(h.luminosity);
    _apply(ToneChannel.rgb, (lo, 1, hi, 0, 255));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final ch = _channel;
    final lv = _levels(ch);
    final presets = {
      'default': l.presetDefault,
      'darker': l.presetDarker,
      'increaseContrast1': l.presetIncreaseContrast1,
      'increaseContrast2': l.presetIncreaseContrast2,
      'increaseContrast3': l.presetIncreaseContrast3,
      'lightenShadows': l.presetLightenShadows,
      'lighter': l.presetLighter,
      'midtonesBrighter': l.presetMidtonesBrighter,
      'midtonesDarker': l.presetMidtonesDarker,
    };
    final master = _levels(ToneChannel.rgb);
    final current = presets.keys.where((k) {
      final (b, g, w, ob, ow) = ToneLevels.presets[k]!;
      return (master.inBlack - b).abs() < 0.5 &&
          (master.gamma - g).abs() < 0.005 &&
          (master.inWhite - w).abs() < 0.5 &&
          (master.outBlack - ob).abs() < 0.5 &&
          (master.outWhite - ow).abs() < 0.5;
    }).firstOrNull;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: PopupMenuButton<String>(
                  tooltip: l.tonePreset,
                  onSelected: (k) =>
                      _apply(ToneChannel.rgb, ToneLevels.presets[k]!),
                  itemBuilder: (_) => [
                    for (final e in presets.entries)
                      PopupMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: l.tonePreset,
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.auto_awesome_rounded, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            current == null ? '—' : presets[current]!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(Icons.arrow_drop_down_rounded),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: ctx.histogram == null ? null : _auto,
                icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                label: Text(l.toneAuto),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _ChannelBar(value: ch, onChanged: (c) => ctx.set('channel', c.index)),
          const SizedBox(height: 12),
          Text(
            l.toneInputLevels,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          _HistogramLoader(
            future: ctx.histogram,
            builder: (h) => _LevelsTrack(
              histogram: h?.of(ch),
              color: _channelColors[ch]!,
              values: [lv.inBlack, lv.inWhite],
              mid: lv.midPosition,
              onChanged: (i, v) => i == 0
                  ? _set('inBlack', v.clamp(0, lv.inWhite - 2), live: true)
                  : _set('inWhite', v.clamp(lv.inBlack + 2, 255), live: true),
              onMid: (pos) =>
                  _set('gamma', LevelsChannel.gammaFor(pos), live: true),
              onEnd: ctx.commit,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _NumField(
                label: '◢',
                value: lv.inBlack,
                onSubmit: (v) => _set('inBlack', v.clamp(0, lv.inWhite - 2)),
              ),
              _NumField(
                label: 'γ',
                value: lv.gamma,
                decimals: 2,
                onSubmit: (v) => _set('gamma', v.clamp(0.01, 9.99)),
              ),
              _NumField(
                label: '◣',
                value: lv.inWhite,
                onSubmit: (v) => _set('inWhite', v.clamp(lv.inBlack + 2, 255)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            l.toneOutputLevels,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          _LevelsTrack(
            histogram: null,
            color: _channelColors[ch]!,
            values: [lv.outBlack, lv.outWhite],
            onChanged: (i, v) =>
                _set(i == 0 ? 'outBlack' : 'outWhite', v, live: true),
            onEnd: ctx.commit,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _NumField(
                label: '◢',
                value: lv.outBlack,
                onSubmit: (v) => _set('outBlack', v.clamp(0, 255)),
              ),
              IconButton(
                tooltip: l.toneResetChannel,
                onPressed: () => _apply(ch, (0, 1, 255, 0, 255)),
                icon: const Icon(Icons.restart_alt_rounded),
              ),
              _NumField(
                label: '◣',
                value: lv.outWhite,
                onSubmit: (v) => _set('outWhite', v.clamp(0, 255)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A black-to-white ramp (with a histogram above for input levels) and
/// triangle sliders: black and white ([values], 0..255) and, when [mid]
/// is given, the grey midtone slider (0..1 between them).
class _LevelsTrack extends StatefulWidget {
  const _LevelsTrack({
    required this.histogram,
    required this.color,
    required this.values,
    required this.onChanged,
    required this.onEnd,
    this.mid,
    this.onMid,
  });
  final List<int>? histogram;
  final Color color;
  final List<double> values;
  final double? mid;
  final void Function(int index, double value) onChanged;
  final ValueChanged<double>? onMid;
  final VoidCallback onEnd;

  @override
  State<_LevelsTrack> createState() => _LevelsTrackState();
}

class _LevelsTrackState extends State<_LevelsTrack> {
  /// 0 black, 1 white, 2 grey.
  int? _drag;

  static const _pad = 12.0;

  double _xOf(double v, double w) => _pad + v / 255 * (w - 2 * _pad);
  double _vOf(double x, double w) =>
      ((x - _pad) / (w - 2 * _pad) * 255).clamp(0.0, 255.0);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final withHist = widget.mid != null;
    final height = withHist ? 118.0 : 40.0;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth;
          final b = widget.values[0], wh = widget.values[1];
          final midX = widget.mid == null
              ? null
              : _xOf(b + (wh - b) * widget.mid!, w);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (d) {
              final x = d.localPosition.dx;
              final cands = <int, double>{
                0: (_xOf(b, w) - x).abs(),
                1: (_xOf(wh, w) - x).abs(),
                if (midX != null) 2: (midX - x).abs(),
              };
              final best = cands.entries.reduce(
                (a, c) => c.value < a.value ? c : a,
              );
              _drag = best.value < 36 ? best.key : null;
            },
            onPanUpdate: (d) {
              final i = _drag;
              if (i == null) return;
              final v = _vOf(d.localPosition.dx, w);
              if (i == 2) {
                final span = math.max(1.0, wh - b);
                widget.onMid?.call(((v - b) / span).clamp(0.001, 0.999));
              } else {
                widget.onChanged(i, v);
              }
            },
            onPanEnd: (_) {
              if (_drag != null) widget.onEnd();
              _drag = null;
            },
            child: CustomPaint(
              size: Size(w, height),
              painter: _TrackPainter(
                histogram: widget.histogram,
                withHistogram: withHist,
                color: widget.color,
                black: _xOf(b, w),
                white: _xOf(wh, w),
                mid: midX,
                pad: _pad,
                background: scheme.onSurface.withValues(alpha: 0.04),
                outline: scheme.onSurface,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TrackPainter extends CustomPainter {
  _TrackPainter({
    required this.histogram,
    required this.withHistogram,
    required this.color,
    required this.black,
    required this.white,
    required this.mid,
    required this.pad,
    required this.background,
    required this.outline,
  });
  final List<int>? histogram;
  final bool withHistogram;
  final Color color, background, outline;
  final double black, white, pad;
  final double? mid;

  @override
  void paint(Canvas canvas, Size size) {
    const rampH = 12.0;
    final rampTop = size.height - 14 - rampH;
    if (withHistogram) {
      final r = Rect.fromLTRB(pad, 0, size.width - pad, rampTop - 4);
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(8)),
        Paint()..color = background,
      );
      _paintHistogram(
        canvas,
        r.deflate(2),
        histogram,
        (color == const Color(0xFF9E9E9E) ? outline : color).withValues(
          alpha: 0.55,
        ),
      );
    }
    final ramp = Rect.fromLTRB(pad, rampTop, size.width - pad, rampTop + rampH);
    canvas.drawRRect(
      RRect.fromRectAndRadius(ramp, const Radius.circular(4)),
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF000000), Color(0xFFFFFFFF)],
        ).createShader(ramp),
    );
    void tri(double x, Color fill) {
      final y = size.height - 1;
      final path = Path()
        ..moveTo(x, rampTop + rampH + 1)
        ..lineTo(x - 8, y)
        ..lineTo(x + 8, y)
        ..close();
      canvas
        ..drawPath(path, Paint()..color = fill)
        ..drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..color = outline.withValues(alpha: 0.7),
        );
    }

    tri(black, const Color(0xFF000000));
    if (mid != null) tri(mid!, const Color(0xFF808080));
    tri(white, const Color(0xFFFFFFFF));
  }

  @override
  bool shouldRepaint(_TrackPainter old) =>
      old.black != black ||
      old.white != white ||
      old.mid != mid ||
      old.histogram != histogram ||
      old.color != color;
}

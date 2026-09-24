import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';

/// A labelled slider row: `Label ━━━━●──── [42]`.
///
/// A custom, soft control: thick rounded track with a gradient fill (from
/// zero for ranges that cross zero), a tick at the default value it gently
/// snaps to, a thumb that grows and shows a value bubble while dragging,
/// and a value pill — tap it to type an exact number, long-press (or
/// double-tap the label) to reset.
///
/// [onChanged] fires continuously (live previews) and [onChangeEnd] once
/// when the finger lifts (commit an undo step).
class PixSlider extends StatefulWidget {
  const PixSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.onChangeEnd,
    this.defaultValue,
    this.format,
    this.icon,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final double? defaultValue;
  final String Function(double v)? format;
  final IconData? icon;

  @override
  State<PixSlider> createState() => _PixSliderState();
}

class _PixSliderState extends State<PixSlider>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
  );
  bool _dragging = false;
  double? _current;
  bool _snapped = false;

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  double get _value =>
      (_current ?? widget.value).clamp(widget.min, widget.max).toDouble();

  String _text(double v) => widget.format?.call(v) ?? v.round().toString();

  double _fromDx(double dx, double width, bool rtl) {
    const pad = _thumbRadius;
    var t = ((dx - pad) / math.max(1, width - 2 * pad)).clamp(0.0, 1.0);
    if (rtl) t = 1 - t;
    var v = widget.min + t * (widget.max - widget.min);
    // Gentle snap to the default value.
    final d = widget.defaultValue;
    if (d != null && d >= widget.min && d <= widget.max) {
      final near = (v - d).abs() <= (widget.max - widget.min) * 0.015;
      if (near) {
        v = d;
        if (!_snapped) HapticFeedback.selectionClick();
      }
      _snapped = near;
    }
    return v;
  }

  void _start(double dx, double width, bool rtl) {
    _dragging = true;
    _press.forward();
    final v = _fromDx(dx, width, rtl);
    setState(() => _current = v);
    widget.onChanged(v);
  }

  void _update(double dx, double width, bool rtl) {
    final v = _fromDx(dx, width, rtl);
    setState(() => _current = v);
    widget.onChanged(v);
  }

  void _end() {
    if (!_dragging) return;
    _dragging = false;
    _press.reverse();
    final v = _value;
    setState(() => _current = null);
    widget.onChangeEnd?.call(v);
  }

  void _reset() {
    final d = widget.defaultValue;
    if (d == null) return;
    HapticFeedback.mediumImpact();
    widget.onChanged(d);
    widget.onChangeEnd?.call(d);
  }

  Future<void> _type() async {
    final l = AppLocalizations.of(context);
    final c = TextEditingController(
      text: _text(_value).replaceAll(RegExp(r'[^0-9.\-]'), ''),
    );
    final r = await showDialog<double>(
      context: context,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        void submit() {
          final v = double.tryParse(c.text.replaceAll(',', '.'));
          if (v != null) Navigator.pop(context, v);
        }

        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Text(widget.label),
          content: TextField(
            controller: c,
            autofocus: true,
            textAlign: TextAlign.center,
            textDirection: TextDirection.ltr,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            style: Theme.of(context).textTheme.headlineSmall,
            decoration: InputDecoration(
              filled: true,
              fillColor: scheme.onSurface.withValues(alpha: 0.05),
              helperText: '${_text(widget.min)} … ${_text(widget.max)}',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
            onSubmitted: (_) => submit(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l.cancel),
            ),
            FilledButton(onPressed: submit, child: Text(l.apply)),
          ],
        );
      },
    );
    c.dispose();
    if (r == null) return;
    // Values shown as percent (0..1 ranges) are typed as percent.
    final percent =
        widget.max <= 1 && (widget.format?.call(1) ?? '').contains('%');
    final v = (percent ? r / 100 : r).clamp(widget.min, widget.max).toDouble();
    widget.onChanged(v);
    widget.onChangeEnd?.call(v);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final v = _value;
    final text = _text(v);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Row(
        children: [
          GestureDetector(
            onDoubleTap: widget.defaultValue == null ? null : _reset,
            child: SizedBox(
              width: 92,
              child: Row(
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, size: 18, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      widget.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.15,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                final w = box.maxWidth;
                return Semantics(
                  slider: true,
                  label: widget.label,
                  value: text,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragStart: (d) =>
                        _start(d.localPosition.dx, w, rtl),
                    onHorizontalDragUpdate: (d) =>
                        _update(d.localPosition.dx, w, rtl),
                    onHorizontalDragEnd: (_) => _end(),
                    onHorizontalDragCancel: _end,
                    onTapUp: (d) {
                      _start(d.localPosition.dx, w, rtl);
                      _end();
                    },
                    child: AnimatedBuilder(
                      animation: _press,
                      builder: (context, _) => CustomPaint(
                        size: Size(w, 44),
                        painter: _SliderPainter(
                          t:
                              (v - widget.min) /
                              math.max(1e-9, widget.max - widget.min),
                          origin: widget.min < 0 && widget.max > 0
                              ? -widget.min / (widget.max - widget.min)
                              : 0,
                          defaultT: widget.defaultValue == null
                              ? null
                              : (widget.defaultValue! - widget.min) /
                                    math.max(1e-9, widget.max - widget.min),
                          press: _press.value,
                          label: text,
                          rtl: rtl,
                          primary: scheme.primary,
                          secondary: Color.lerp(
                            scheme.primary,
                            scheme.tertiary,
                            0.6,
                          )!,
                          track: scheme.onSurface.withValues(alpha: 0.09),
                          thumb: scheme.surface,
                          bubble: scheme.inverseSurface,
                          onBubble: scheme.onInverseSurface,
                          shadow: Colors.black.withValues(alpha: 0.18),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _type,
            onLongPress: widget.defaultValue == null ? null : _reset,
            child: Container(
              constraints: const BoxConstraints(minWidth: 52),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: _dragging
                    ? scheme.primary.withValues(alpha: 0.14)
                    : scheme.onSurface.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(
                text,
                maxLines: 1,
                textDirection: TextDirection.ltr,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                  fontWeight: FontWeight.w700,
                  color: _dragging ? scheme.primary : scheme.onSurface,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const double _thumbRadius = 11;

class _SliderPainter extends CustomPainter {
  _SliderPainter({
    required this.t,
    required this.origin,
    required this.defaultT,
    required this.press,
    required this.label,
    required this.rtl,
    required this.primary,
    required this.secondary,
    required this.track,
    required this.thumb,
    required this.bubble,
    required this.onBubble,
    required this.shadow,
  });

  final double t;
  final double origin;
  final double? defaultT;
  final double press;
  final String label;
  final bool rtl;
  final Color primary, secondary, track, thumb, bubble, onBubble, shadow;

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    const pad = _thumbRadius;
    final w = size.width - 2 * pad;
    double x(double f) => pad + (rtl ? 1 - f : f) * w;
    const h = 8.0;

    // Track.
    final trackRect = RRect.fromLTRBR(
      pad - h / 2,
      cy - h / 2,
      size.width - pad + h / 2,
      cy + h / 2,
      const Radius.circular(h),
    );
    canvas.drawRRect(trackRect, Paint()..color = track);

    // Active part: from zero (bipolar) or from the start.
    final a = x(origin), b = x(t.clamp(0.0, 1.0));
    final left = math.min(a, b), right = math.max(a, b);
    if (right - left > 0.5) {
      final r = Rect.fromLTRB(
        left - h / 2,
        cy - h / 2,
        right + h / 2,
        cy + h / 2,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(h)),
        Paint()
          ..shader = LinearGradient(
            colors: rtl ? [primary, secondary] : [secondary, primary],
          ).createShader(r),
      );
    }

    // Default tick.
    if (defaultT != null && defaultT! > 0.001 && defaultT! < 0.999) {
      canvas.drawCircle(
        Offset(x(defaultT!), cy),
        2.2,
        Paint()..color = primary.withValues(alpha: 0.55),
      );
    }

    // Thumb.
    final tx = x(t.clamp(0.0, 1.0));
    final r = _thumbRadius + 3 * press;
    canvas
      ..drawCircle(
        Offset(tx, cy + 1.5),
        r + 1,
        Paint()
          ..color = shadow
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      )
      ..drawCircle(Offset(tx, cy), r, Paint()..color = thumb)
      ..drawCircle(
        Offset(tx, cy),
        r - 1.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = primary,
      )
      ..drawCircle(Offset(tx, cy), 3 + 1.5 * press, Paint()..color = primary);

    // Value bubble while dragging.
    if (press > 0.01) {
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: onBubble,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final bw = tp.width + 16, bh = tp.height + 8;
      final by = cy - r - 8 - bh;
      final rect = Rect.fromCenter(
        center: Offset(tx.clamp(bw / 2, size.width - bw / 2), by + bh / 2),
        width: bw,
        height: bh,
      );
      canvas.save();
      canvas.translate(rect.center.dx, rect.bottom);
      canvas.scale(press, press);
      canvas.translate(-rect.center.dx, -rect.bottom);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(8)),
        Paint()..color = bubble,
      );
      tp.paint(canvas, rect.topLeft + const Offset(8, 4));
      canvas.restore();
      tp.dispose();
    }
  }

  @override
  bool shouldRepaint(_SliderPainter old) =>
      old.t != t ||
      old.press != press ||
      old.label != label ||
      old.primary != primary ||
      old.rtl != rtl ||
      old.track != track;
}

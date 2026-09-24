import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/units/units.dart';
import '../../../l10n/app_localizations.dart';

class CanvasSizeResult {
  const CanvasSizeResult(
    this.width,
    this.height, {
    this.transparent = false,
    this.scaleContent = true,
    this.dpi = 72,
  });

  /// Size in pixels.
  final double width;
  final double height;
  final bool transparent;
  final bool scaleContent;
  final double dpi;
}

/// Canvas size in any unit (px, cm, mm, in, pt) with resolution and ratio
/// lock. Used for new projects and for resizing an open canvas ([resizing]
/// shows "scale content" instead of the background choice).
Future<CanvasSizeResult?> showNewCanvasDialog(
  BuildContext context, {
  double width = 1080,
  double height = 1080,
  double dpi = 72,
  bool resizing = false,
}) => showDialog<CanvasSizeResult>(
  context: context,
  builder: (_) => _NewCanvasDialog(
    width: width,
    height: height,
    dpi: dpi,
    resizing: resizing,
  ),
);

class _NewCanvasDialog extends StatefulWidget {
  const _NewCanvasDialog({
    required this.width,
    required this.height,
    required this.dpi,
    required this.resizing,
  });
  final double width;
  final double height;
  final double dpi;
  final bool resizing;

  @override
  State<_NewCanvasDialog> createState() => _NewCanvasDialogState();
}

class _NewCanvasDialogState extends State<_NewCanvasDialog> {
  static const _units = [
    MeasureUnit.px,
    MeasureUnit.cm,
    MeasureUnit.mm,
    MeasureUnit.inch,
    MeasureUnit.pt,
  ];
  static const _maxPx = 16384.0;

  MeasureUnit _unit = MeasureUnit.px;
  late double _dpi = widget.dpi;
  late final _w = TextEditingController(text: _fmt(widget.width));
  late final _h = TextEditingController(text: _fmt(widget.height));
  late final _d = TextEditingController(text: _dpi.round().toString());
  bool _lock = true;
  late double _ratio = widget.width / widget.height;
  bool _transparent = false;
  bool _scale = true;

  String _fmt(double px) => _unit.format(_unit.fromPx(px, _dpi));

  @override
  void dispose() {
    _w.dispose();
    _h.dispose();
    _d.dispose();
    super.dispose();
  }

  double? _px(TextEditingController c) {
    final v = double.tryParse(c.text.replaceAll(',', '.'));
    if (v == null || v <= 0) return null;
    final px = _unit.toPx(v, _dpi).roundToDouble();
    if (px < 1 || px > _maxPx) return null;
    return px;
  }

  void _setUnit(MeasureUnit u) {
    final w = _px(_w), h = _px(_h);
    setState(() {
      _unit = u;
      if (w != null) _w.text = _fmt(w);
      if (h != null) _h.text = _fmt(h);
    });
  }

  void _setDpi(double dpi) {
    // Keep the physical size when the unit is physical, else the pixels.
    final w = _px(_w), h = _px(_h);
    final physical = _unit != MeasureUnit.px;
    final wu = physical ? double.tryParse(_w.text) : null;
    final hu = physical ? double.tryParse(_h.text) : null;
    setState(() {
      _dpi = dpi;
      _d.text = dpi.round().toString();
      if (!physical) {
        if (w != null) _w.text = _fmt(w);
        if (h != null) _h.text = _fmt(h);
      } else {
        if (wu != null) _w.text = _unit.format(wu);
        if (hu != null) _h.text = _unit.format(hu);
      }
    });
  }

  void _linked(TextEditingController changed) {
    if (!_lock) {
      final w = _px(_w), h = _px(_h);
      if (w != null && h != null) _ratio = w / h;
      setState(() {});
      return;
    }
    final v = double.tryParse(changed.text.replaceAll(',', '.'));
    if (v == null) {
      setState(() {});
      return;
    }
    final other = identical(changed, _w) ? _h : _w;
    final ov = identical(changed, _w) ? v / _ratio : v * _ratio;
    other.text = _unit.format(ov);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final w = _px(_w), h = _px(_h);
    final valid = w != null && h != null && _dpi >= 1;

    Widget field(TextEditingController c, String label) => Expanded(
      child: TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
        ],
        decoration: InputDecoration(
          labelText: label,
          suffixText: _unit.suffix,
          filled: true,
          fillColor: scheme.onSurface.withValues(alpha: 0.04),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
        onChanged: (_) => _linked(c),
      ),
    );

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.aspect_ratio_rounded, color: scheme.primary),
                  const SizedBox(width: 10),
                  Text(
                    widget.resizing ? l.canvasSize : l.customSize,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(l.units, style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              SegmentedButton<MeasureUnit>(
                showSelectedIcon: false,
                segments: [
                  for (final u in _units)
                    ButtonSegment(value: u, label: Text(u.suffix)),
                ],
                selected: {_unit},
                onSelectionChanged: (s) => _setUnit(s.first),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  field(_w, l.width),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: IconButton(
                      tooltip: l.keepRatio,
                      isSelected: _lock,
                      onPressed: () => setState(() {
                        _lock = !_lock;
                        if (w != null && h != null) _ratio = w / h;
                      }),
                      icon: const Icon(Icons.link_off_rounded),
                      selectedIcon: Icon(
                        Icons.link_rounded,
                        color: scheme.primary,
                      ),
                    ),
                  ),
                  field(_h, l.height),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  SizedBox(
                    width: 110,
                    child: TextField(
                      controller: _d,
                      keyboardType: TextInputType.number,
                      textDirection: TextDirection.ltr,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: l.resolution,
                        suffixText: 'dpi',
                        filled: true,
                        fillColor: scheme.onSurface.withValues(alpha: 0.04),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (v) {
                        final d = double.tryParse(v);
                        if (d != null && d >= 1 && d <= 9600) _setDpi(d);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final d in const [72.0, 150.0, 300.0])
                          ChoiceChip(
                            label: Text('${d.round()}'),
                            selected: _dpi == d,
                            onSelected: (_) => _setDpi(d),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: valid
                      ? scheme.primary.withValues(alpha: 0.08)
                      : scheme.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(
                      valid ? Icons.crop_square_rounded : Icons.error_outline,
                      size: 18,
                      color: valid ? scheme.primary : scheme.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        valid
                            ? '${w.round()} × ${h.round()} px'
                            : l.sizeLimit(_maxPx.round()),
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.start,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: valid ? scheme.primary : scheme.error,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (valid && _unit == MeasureUnit.px)
                      Text(
                        '${MeasureUnit.cm.format(MeasureUnit.cm.fromPx(w, _dpi))} × '
                        '${MeasureUnit.cm.format(MeasureUnit.cm.fromPx(h, _dpi))} cm',
                        textDirection: TextDirection.ltr,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              if (widget.resizing)
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _scale,
                  title: Text(l.scaleContent),
                  onChanged: (v) => setState(() => _scale = v),
                )
              else
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _transparent,
                  title: Text(l.transparent),
                  onChanged: (v) => setState(() => _transparent = v),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 50),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: Text(l.cancel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 50),
                      ),
                      onPressed: !valid
                          ? null
                          : () => Navigator.pop(
                              context,
                              CanvasSizeResult(
                                math.max(1, w),
                                math.max(1, h),
                                transparent: _transparent,
                                scaleContent: _scale,
                                dpi: _dpi,
                              ),
                            ),
                      child: Text(widget.resizing ? l.apply : l.create),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

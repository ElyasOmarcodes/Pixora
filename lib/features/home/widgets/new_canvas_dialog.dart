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
}) => showModalBottomSheet<CanvasSizeResult>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
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

  void _setRatio(double r) {
    final w = _px(_w) ?? widget.width;
    var h = (w / r).roundToDouble();
    var ww = w;
    if (h > _maxPx) {
      h = _maxPx;
      ww = (h * r).roundToDouble();
    }
    setState(() {
      _lock = true;
      _ratio = r;
      _w.text = _fmt(ww);
      _h.text = _fmt(h);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final w = _px(_w), h = _px(_h);
    final valid = w != null && h != null && _dpi >= 1;
    final fieldFill = scheme.onSurface.withValues(alpha: 0.05);
    OutlineInputBorder border() => OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide.none,
    );

    Widget section(String title) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    Widget field(TextEditingController c, String label) => Expanded(
      // Numbers and units read left-to-right in every language.
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
          decoration: InputDecoration(
            labelText: label,
            floatingLabelAlignment: FloatingLabelAlignment.center,
            suffixText: _unit.suffix,
            filled: true,
            fillColor: fieldFill,
            border: border(),
          ),
          onChanged: (_) => _linked(c),
        ),
      ),
    );

    // Live preview of the proportions.
    final ratio = valid ? w / h : _ratio;
    const box = 76.0;
    final pw = ratio >= 1 ? box : box * ratio;
    final ph = ratio >= 1 ? box / ratio : box;

    const ratios = <(String, double)>[
      ('1:1', 1),
      ('4:5', 4 / 5),
      ('9:16', 9 / 16),
      ('16:9', 16 / 9),
      ('3:2', 3 / 2),
      ('2:3', 2 / 3),
      ('4:3', 4 / 3),
      ('A4', 210 / 297),
    ];

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header: title, and the size at a glance with a preview.
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.resizing ? l.canvasSize : l.customSize,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        valid
                            ? '${w.round()} × ${h.round()} px'
                            : l.sizeLimit(_maxPx.round()),
                        textDirection: TextDirection.ltr,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: valid ? scheme.primary : scheme.error,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (valid)
                        Text(
                          '${MeasureUnit.cm.format(MeasureUnit.cm.fromPx(w, _dpi))}'
                          ' × '
                          '${MeasureUnit.cm.format(MeasureUnit.cm.fromPx(h, _dpi))}'
                          ' cm · ${_dpi.round()} dpi',
                          textDirection: TextDirection.ltr,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(
                  width: box + 8,
                  height: box + 8,
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      width: pw.clamp(6.0, box),
                      height: ph.clamp(6.0, box),
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.12),
                        border: Border.all(color: scheme.primary, width: 2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            section(l.aspectRatio),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final (name, r) in ratios)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 6),
                      child: ChoiceChip(
                        label: Text(name),
                        selected: _lock && (_ratio - r).abs() < 0.002,
                        onSelected: (_) => _setRatio(r),
                      ),
                    ),
                ],
              ),
            ),
            section(l.units),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<MeasureUnit>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: [
                  for (final u in _units)
                    ButtonSegment(value: u, label: Text(u.suffix)),
                ],
                selected: {_unit},
                onSelectionChanged: (s) => _setUnit(s.first),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                field(_w, l.width),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: IconButton.filledTonal(
                    tooltip: l.keepRatio,
                    isSelected: _lock,
                    onPressed: () => setState(() {
                      _lock = !_lock;
                      if (w != null && h != null) _ratio = w / h;
                    }),
                    icon: const Icon(Icons.link_off_rounded),
                    selectedIcon: const Icon(Icons.link_rounded),
                  ),
                ),
                field(_h, l.height),
              ],
            ),
            section(l.resolution),
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<double>(
                    showSelectedIcon: false,
                    emptySelectionAllowed: true,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                    segments: [
                      for (final d in const [72.0, 150.0, 300.0])
                        ButtonSegment(value: d, label: Text('${d.round()}')),
                    ],
                    selected: {
                      if (const [72.0, 150.0, 300.0].contains(_dpi)) _dpi,
                    },
                    onSelectionChanged: (s) {
                      if (s.isNotEmpty) _setDpi(s.first);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 104,
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: TextField(
                      controller: _d,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        isDense: true,
                        suffixText: 'dpi',
                        filled: true,
                        fillColor: fieldFill,
                        border: border(),
                      ),
                      onChanged: (v) {
                        final d = double.tryParse(v);
                        if (d != null && d >= 1 && d <= 9600) _setDpi(d);
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: fieldFill,
                borderRadius: BorderRadius.circular(16),
              ),
              child: widget.resizing
                  ? SwitchListTile.adaptive(
                      value: _scale,
                      secondary: const Icon(Icons.open_in_full_rounded),
                      title: Text(l.scaleContent),
                      onChanged: (v) => setState(() => _scale = v),
                    )
                  : SwitchListTile.adaptive(
                      value: _transparent,
                      secondary: const Icon(Icons.grid_4x4_rounded),
                      title: Text(l.transparent),
                      onChanged: (v) => setState(() => _transparent = v),
                    ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 52),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: Text(l.cancel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 52),
                    ),
                    icon: const Icon(Icons.check_rounded),
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
                    label: Text(widget.resizing ? l.apply : l.create),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

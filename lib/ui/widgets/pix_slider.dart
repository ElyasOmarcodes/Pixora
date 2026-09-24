import 'package:flutter/material.dart';

/// A labelled slider row: `Label ───●─── 42`.
///
/// [onChanged] fires continuously (use it for live previews) and
/// [onChangeEnd] once when the finger lifts (use it to commit an undo step).
/// Double-tapping the label resets to [defaultValue].
class PixSlider extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = value.clamp(min, max).toDouble();
    final text = format?.call(v) ?? v.round().toString();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          GestureDetector(
            onDoubleTap: defaultValue == null
                ? null
                : () {
                    onChanged(defaultValue!);
                    onChangeEnd?.call(defaultValue!);
                  },
            child: SizedBox(
              width: 96,
              child: Row(
                children: [
                  if (icon != null) ...[
                    Icon(
                      icon,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Slider(
              value: v,
              min: min,
              max: max,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              text,
              textAlign: TextAlign.end,
              style: theme.textTheme.labelLarge?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../document/model/layer.dart';
import '../../../editor/editor_controller.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui/widgets/pix_slider.dart';
import 'panel_common.dart';

/// Font families offered for text layers. `System` uses the platform font.
const List<(String, String)> kFontFamilies = [
  ('Vazirmatn', 'Vazirmatn'),
  ('System', 'System'),
  ('serif', 'Serif'),
  ('monospace', 'Mono'),
];

class FontPanel extends StatelessWidget {
  const FontPanel({super.key, required this.editor, required this.layer});
  final EditorController editor;
  final TextLayer layer;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    void edit(TextLayer Function(TextLayer t) f, {bool live = false}) =>
        editor.editSelected<TextLayer>(f, live: live, label: 'text');
    void commit([_]) => editor.commit('text');

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: [
              for (final (family, name) in kFontFamilies)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(
                      name,
                      style: TextStyle(
                        fontFamily: family == 'System' ? null : family,
                      ),
                    ),
                    selected: layer.fontFamily == family,
                    onSelected: (_) =>
                        edit((t) => t.copyWith(fontFamily: family)),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              _Toggle(
                icon: Icons.format_bold_rounded,
                selected: layer.fontWeight >= 700,
                onTap: () => edit(
                  (t) =>
                      t.copyWith(fontWeight: t.fontWeight >= 700 ? 400 : 700),
                ),
              ),
              _Toggle(
                icon: Icons.format_italic_rounded,
                selected: layer.italic,
                onTap: () => edit((t) => t.copyWith(italic: !t.italic)),
              ),
              _Toggle(
                icon: Icons.format_underline_rounded,
                selected: layer.underline,
                onTap: () => edit((t) => t.copyWith(underline: !t.underline)),
              ),
              const Spacer(),
              SegmentedButton<PixTextAlign>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: const [
                  ButtonSegment(
                    value: PixTextAlign.start,
                    icon: Icon(Icons.format_align_left_rounded),
                  ),
                  ButtonSegment(
                    value: PixTextAlign.center,
                    icon: Icon(Icons.format_align_center_rounded),
                  ),
                  ButtonSegment(
                    value: PixTextAlign.end,
                    icon: Icon(Icons.format_align_right_rounded),
                  ),
                ],
                selected: {layer.align},
                onSelectionChanged: (s) =>
                    edit((t) => t.copyWith(align: s.first)),
              ),
            ],
          ),
        ),
        PixSlider(
          label: l.fontSize,
          value: layer.fontSize,
          min: 8,
          max: 600,
          onChanged: (v) =>
              edit((t) => t.copyWith(fontSize: v.roundToDouble()), live: true),
          onChangeEnd: commit,
        ),
        PixSlider(
          label: l.weight,
          value: layer.fontWeight.toDouble(),
          min: 400,
          max: 900,
          format: (v) => ((v / 100).round() * 100).toString(),
          onChanged: (v) => edit(
            (t) => t.copyWith(fontWeight: (v / 100).round() * 100),
            live: true,
          ),
          onChangeEnd: commit,
        ),
        PixSlider(
          label: l.letterSpacing,
          value: layer.letterSpacing,
          min: -10,
          max: 60,
          defaultValue: 0,
          onChanged: (v) =>
              edit((t) => t.copyWith(letterSpacing: v), live: true),
          onChangeEnd: commit,
        ),
        PixSlider(
          label: l.lineHeight,
          value: layer.lineHeight,
          min: 0.7,
          max: 3,
          defaultValue: 1.3,
          format: (v) => v.toStringAsFixed(1),
          onChanged: (v) => edit((t) => t.copyWith(lineHeight: v), live: true),
          onChangeEnd: commit,
        ),
        SizedBox(height: theme.visualDensity == VisualDensity.compact ? 4 : 8),
      ],
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: IconButton.filledTonal(
      isSelected: selected,
      onPressed: onTap,
      icon: Icon(icon),
    ),
  );
}

import 'package:flutter/material.dart';

import '../../../document/model/fill.dart';
import '../../../document/model/layer.dart';
import '../../../editor/editor_controller.dart';
import '../../../l10n/app_localizations.dart';
import '../../../document/render/text_layout.dart';
import '../../../ui/widgets/fill_picker.dart';
import '../../../ui/widgets/pix_slider.dart';
import 'panel_common.dart';

void _edit(
  EditorController editor,
  TextLayer Function(TextLayer t) f, {
  bool live = false,
}) => editor.editSelected<TextLayer>(f, live: live, label: 'text');

/// Alignment, weight, italic, underline, strike-through and letter case.
class TextStylePanel extends StatelessWidget {
  const TextStylePanel({super.key, required this.editor, required this.layer});
  final EditorController editor;
  final TextLayer layer;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    void edit(TextLayer Function(TextLayer t) f, {bool live = false}) =>
        _edit(editor, f, live: live);

    Widget toggle(IconData icon, String tip, bool on, VoidCallback onTap) =>
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: IconButton.filledTonal(
            tooltip: tip,
            isSelected: on,
            onPressed: onTap,
            icon: Icon(icon),
          ),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: SegmentedButton<PixTextAlign>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: PixTextAlign.start,
                icon: const Icon(Icons.format_align_left_rounded),
                tooltip: l.alignStart,
              ),
              ButtonSegment(
                value: PixTextAlign.center,
                icon: const Icon(Icons.format_align_center_rounded),
                tooltip: l.alignCenter,
              ),
              ButtonSegment(
                value: PixTextAlign.end,
                icon: const Icon(Icons.format_align_right_rounded),
                tooltip: l.alignEnd,
              ),
              ButtonSegment(
                value: PixTextAlign.justify,
                icon: const Icon(Icons.format_align_justify_rounded),
                tooltip: l.justify,
              ),
            ],
            selected: {layer.align},
            onSelectionChanged: (s) => edit((t) => t.copyWith(align: s.first)),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          child: Row(
            children: [
              toggle(
                Icons.format_bold_rounded,
                l.bold,
                layer.fontWeight >= 700,
                () => edit(
                  (t) =>
                      t.copyWith(fontWeight: t.fontWeight >= 700 ? 400 : 700),
                ),
              ),
              toggle(
                Icons.format_italic_rounded,
                l.italic,
                layer.italic,
                () => edit((t) => t.copyWith(italic: !t.italic)),
              ),
              toggle(
                Icons.format_underline_rounded,
                l.underline,
                layer.underline,
                () => edit((t) => t.copyWith(underline: !t.underline)),
              ),
              toggle(
                Icons.format_strikethrough_rounded,
                l.strikethrough,
                layer.strike,
                () => edit((t) => t.copyWith(strike: !t.strike)),
              ),
              const SizedBox(width: 8),
              for (final (c, label) in [
                (PixTextCase.none, 'Aa'),
                (PixTextCase.upper, 'AA'),
                (PixTextCase.lower, 'aa'),
                (PixTextCase.title, 'Ab'),
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: ChoiceChip(
                    label: Text(label, textDirection: TextDirection.ltr),
                    tooltip: switch (c) {
                      PixTextCase.none => l.caseNone,
                      PixTextCase.upper => l.caseUpper,
                      PixTextCase.lower => l.caseLower,
                      PixTextCase.title => l.caseTitle,
                    },
                    selected: layer.textCase == c,
                    onSelected: (_) => edit((t) => t.copyWith(textCase: c)),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        PixSlider(
          label: l.weight,
          value: layer.fontWeight.toDouble(),
          min: 100,
          max: 900,
          format: (v) => ((v / 100).round() * 100).toString(),
          onChanged: (v) => edit(
            (t) => t.copyWith(fontWeight: (v / 100).round() * 100),
            live: true,
          ),
          onChangeEnd: (_) => editor.commit('text'),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Bends the text along an arc.
class CurvePanel extends StatelessWidget {
  const CurvePanel({super.key, required this.editor, required this.layer});
  final EditorController editor;
  final TextLayer layer;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PixSlider(
          label: l.curve,
          value: layer.curve,
          min: -360,
          max: 360,
          defaultValue: 0,
          format: (v) => '${v.round()}°',
          onChanged: (v) => _edit(
            editor,
            (t) => t.copyWith(curve: v.roundToDouble()),
            live: true,
          ),
          onChangeEnd: (_) => editor.commit('text'),
        ),
        TileRow(
          children: [
            for (final (v, icon) in [
              (-180.0, Icons.sentiment_satisfied_rounded),
              (-90.0, Icons.expand_more_rounded),
              (0.0, Icons.horizontal_rule_rounded),
              (90.0, Icons.expand_less_rounded),
              (180.0, Icons.panorama_fish_eye_rounded),
              (360.0, Icons.circle_outlined),
            ])
              PanelTile(
                icon: icon,
                label: '${v.round()}°',
                selected: layer.curve == v,
                onTap: () => _edit(editor, (t) => t.copyWith(curve: v)),
              ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Coloured box behind the text: colour, padding and corner roundness.
class TextBackgroundPanel extends StatelessWidget {
  const TextBackgroundPanel({
    super.key,
    required this.editor,
    required this.layer,
  });
  final EditorController editor;
  final TextLayer layer;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final bg = layer.background;
    void edit(TextLayer Function(TextLayer t) f, {bool live = false}) =>
        _edit(editor, f, live: live);
    void commit([_]) => editor.commit('text');
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SwitchListTile.adaptive(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          title: Text(
            l.textBackground,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          value: bg != null,
          onChanged: (on) => edit(
            (t) => on
                ? t.copyWith(
                    // A box that contrasts with the text colour.
                    background: PixFill.color(
                      t.fill.primary.computeLuminance() > 0.5
                          ? const Color(0xFF111827)
                          : const Color(0xFFFFE066),
                    ),
                  )
                : t.copyWith(noBackground: true),
          ),
        ),
        if (bg != null) ...[
          FillPicker(
            value: bg,
            aspect: () {
              final z = TextLayoutCache.instance.sizeOf(layer);
              return z.height <= 0 ? 1.0 : z.width / z.height;
            }(),
            onChanged: (f, {required live}) {
              if (f != null) {
                edit((t) => t.copyWith(background: f), live: live);
              }
            },
          ),
          PixSlider(
            label: l.paddingH,
            value: layer.bgPadX,
            min: 0,
            max: 2,
            defaultValue: 0.3,
            format: (v) => '${(v * 100).round()}%',
            onChanged: (v) => edit((t) => t.copyWith(bgPadX: v), live: true),
            onChangeEnd: commit,
          ),
          PixSlider(
            label: l.paddingV,
            value: layer.bgPadY,
            min: 0,
            max: 2,
            defaultValue: 0.15,
            format: (v) => '${(v * 100).round()}%',
            onChanged: (v) => edit((t) => t.copyWith(bgPadY: v), live: true),
            onChangeEnd: commit,
          ),
          PixSlider(
            label: l.corners,
            value: layer.bgRadius,
            min: 0,
            max: 2,
            defaultValue: 0.2,
            format: (v) => '${(v * 100).round()}%',
            onChanged: (v) => edit((t) => t.copyWith(bgRadius: v), live: true),
            onChangeEnd: commit,
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Letter, word and line spacing.
class SpacingPanel extends StatelessWidget {
  const SpacingPanel({super.key, required this.editor, required this.layer});
  final EditorController editor;
  final TextLayer layer;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final fs = layer.fontSize;
    void commit([_]) => editor.commit('text');
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PixSlider(
          label: l.letterSpacing,
          value: layer.letterSpacing,
          min: -fs * 0.2,
          max: fs,
          defaultValue: 0,
          onChanged: (v) => _edit(
            editor,
            (t) => t.copyWith(letterSpacing: v.roundToDouble()),
            live: true,
          ),
          onChangeEnd: commit,
        ),
        PixSlider(
          label: l.wordSpacing,
          value: layer.wordSpacing,
          min: -fs * 0.3,
          max: fs * 2,
          defaultValue: 0,
          onChanged: (v) => _edit(
            editor,
            (t) => t.copyWith(wordSpacing: v.roundToDouble()),
            live: true,
          ),
          onChangeEnd: commit,
        ),
        PixSlider(
          label: l.lineHeight,
          value: layer.lineHeight,
          min: 0.6,
          max: 3,
          defaultValue: 1.3,
          format: (v) => v.toStringAsFixed(2),
          onChanged: (v) =>
              _edit(editor, (t) => t.copyWith(lineHeight: v), live: true),
          onChangeEnd: commit,
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

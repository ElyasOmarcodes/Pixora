import 'package:flutter/material.dart';

import '../../../document/model/fill.dart';
import '../../../document/model/layer.dart';
import '../../../editor/editor_controller.dart';
import '../../../l10n/app_localizations.dart';
import '../../../projects/canvas_presets.dart';
import '../../../ui/widgets/color_picker.dart';
import '../../../ui/widgets/pix_slider.dart';
import '../../../ui/widgets/pressable.dart';
import 'panel_common.dart';

/// Pick a shape to add.
class AddShapePanel extends StatelessWidget {
  const AddShapePanel({super.key, required this.editor, required this.onAdded});
  final EditorController editor;
  final VoidCallback onAdded;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return TileRow(
      children: [
        for (final k in ShapeKind.values)
          PanelTile(
            icon: shapeIcon(k),
            label: shapeLabel(l, k),
            onTap: () {
              editor.addShape(
                k,
                name: l.shape,
                color: Theme.of(context).colorScheme.primary,
              );
              onAdded();
            },
          ),
      ],
    );
  }
}

/// Solid / gradient / transparent background of the canvas.
class BackgroundPanel extends StatelessWidget {
  const BackgroundPanel({super.key, required this.editor});
  final EditorController editor;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final bg = editor.document.background;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PanelLabel(l.solid),
        ColorStrip(
          value: bg == null ? null : (bg.isGradient ? null : bg.primary),
          allowTransparent: true,
          onChanged: (c, {required live}) {
            editor.setBackground(
              c == null ? null : PixFill.color(c),
              live: live,
            );
          },
        ),
        PanelLabel(l.gradient),
        GradientStrip(selected: bg, onSelected: (f) => editor.setBackground(f)),
        if (bg != null && bg.kind == FillKind.linear && bg.isGradient)
          PixSlider(
            label: l.angle,
            value: bg.angle,
            min: 0,
            max: 360,
            defaultValue: 135,
            format: (v) => '${v.round()}°',
            onChanged: (v) =>
                editor.setBackground(bg.copyWith(angle: v), live: true),
            onChangeEnd: (_) => editor.commit('background'),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Row of gradient presets.
class GradientStrip extends StatelessWidget {
  const GradientStrip({
    super.key,
    required this.selected,
    required this.onSelected,
  });
  final PixFill? selected;
  final ValueChanged<PixFill> onSelected;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final angle = selected?.kind == FillKind.linear ? selected!.angle : 135.0;
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final g in kBackgroundGradients)
            Builder(
              builder: (context) {
                final fill = PixFill.linear(g, angle: angle);
                final isSel =
                    selected != null &&
                    selected!.isGradient &&
                    selected!.colors.length == g.length &&
                    selected!.colors.first.toARGB32() == g.first.toARGB32() &&
                    selected!.colors.last.toARGB32() == g.last.toARGB32();
                return Pressable(
                  scale: 0.9,
                  onTap: () => onSelected(fill),
                  child: Container(
                    width: 48,
                    height: 48,
                    margin: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSel ? accent : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                    padding: const EdgeInsets.all(2),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: g,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

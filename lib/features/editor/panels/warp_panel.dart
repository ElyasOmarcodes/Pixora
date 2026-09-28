import 'package:flutter/material.dart';

import '../../../document/model/layer.dart';
import '../../../document/model/warp.dart';
import '../../../editor/editor_controller.dart';
import '../../../editor/tools/warp_tool.dart';
import '../../../l10n/app_localizations.dart';

/// Edit ▸ Transform: Distort, Perspective and Warp (the handles are on the
/// canvas), plus resetting or removing the warp.
class WarpPanel extends StatelessWidget {
  const WarpPanel({
    super.key,
    required this.editor,
    required this.layer,
    required this.state,
  });
  final EditorController editor;
  final Layer layer;
  final WarpState state;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final has = warpOf(layer) != null;
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
            child: SegmentedButton<WarpMode>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: WarpMode.distort,
                  icon: const Icon(Icons.crop_rotate_rounded, size: 18),
                  label: Text(l.distort, maxLines: 1),
                ),
                ButtonSegment(
                  value: WarpMode.perspective,
                  icon: const Icon(Icons.view_in_ar_rounded, size: 18),
                  label: Text(l.perspective, maxLines: 1),
                ),
                ButtonSegment(
                  value: WarpMode.warp,
                  icon: const Icon(Icons.gesture_rounded, size: 18),
                  label: Text(l.warp, maxLines: 1),
                ),
              ],
              selected: {state.mode},
              onSelectionChanged: (s) => state.mode = s.first,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
            child: Text(
              switch (state.mode) {
                WarpMode.distort => l.distortHint,
                WarpMode.perspective => l.perspectiveHint,
                WarpMode.warp => l.warpHint,
              },
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: has
                        ? () => editor.updateLayer(
                            layer.id,
                            (x) => withWarp(
                              x,
                              WarpGeometry.of(
                                warpOf(x)!.copyWith(params: const {}),
                              ),
                              state.mode,
                            ),
                            label: 'warp',
                          )
                        : null,
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: Text(l.resetShape),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: has
                        ? () => editor.updateLayer(
                            layer.id,
                            (x) => x.withProps(
                              x.props.copyWith(
                                effects: [
                                  for (final e in x.props.effects)
                                    if (e.type != 'warp') e,
                                ],
                              ),
                            ),
                            label: 'warp',
                          )
                        : null,
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: Text(l.delete),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

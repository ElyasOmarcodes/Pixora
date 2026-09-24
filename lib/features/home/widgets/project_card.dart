import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../app/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../projects/project_store.dart';
import '../../../ui/widgets/checkerboard.dart';
import '../../../ui/widgets/soft_card.dart';
import '../../../projects/project_share.dart';
import 'text_prompt.dart';

enum _Menu { rename, duplicate, export, delete }

class ProjectCard extends StatefulWidget {
  const ProjectCard({super.key, required this.summary, required this.onOpen});

  final ProjectSummary summary;
  final VoidCallback onOpen;

  @override
  State<ProjectCard> createState() => _ProjectCardState();
}

class _ProjectCardState extends State<ProjectCard> {
  final _menuKey = GlobalKey<PopupMenuButtonState<_Menu>>();

  ProjectSummary get summary => widget.summary;

  Future<void> _menu(BuildContext context, _Menu action) async {
    final l = AppLocalizations.of(context);
    final repo = AppScope.of(context).projects;
    switch (action) {
      case _Menu.rename:
        final name = await showTextPrompt(
          context,
          title: l.rename,
          label: l.projectName,
          initial: summary.name,
        );
        if (name != null && name.trim().isNotEmpty) {
          await repo.rename(summary.id, name.trim());
        }
      case _Menu.duplicate:
        await repo.duplicate(summary.id, nameSuffix: l.copySuffix);
      case _Menu.export:
        final platform = AppScope.of(context).platform;
        final bytes = await repo.exportArchive(summary.id);
        if (bytes != null && context.mounted) {
          await deliverProjectFile(context, platform, bytes, summary.name);
        }
      case _Menu.delete:
        final ok = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l.deleteProjectTitle),
            content: Text(l.deleteProjectBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l.cancel),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: () => Navigator.pop(context, true),
                child: Text(l.delete),
              ),
            ],
          ),
        );
        if (ok ?? false) await repo.delete(summary.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final pix = PixColors.of(context);
    return SoftCard(
      onTap: widget.onOpen,
      onLongPress: () => _menuKey.currentState?.showButtonMenu(),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(PixTokens.radiusM),
                child: ColoredBox(
                  color: pix.canvasBackdrop,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: summary.width / summary.height,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CheckerboardBox(
                              a: pix.checkerA,
                              b: pix.checkerB,
                              cell: 6,
                            ),
                            if (summary.thumbnail != null)
                              Image.memory(
                                summary.thumbnail!,
                                fit: BoxFit.contain,
                                gaplessPlayback: true,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(start: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          summary.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${summary.width.round()} × ${summary.height.round()}',
                          textDirection: TextDirection.ltr,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                PopupMenuButton<_Menu>(
                  key: _menuKey,
                  tooltip: l.more,
                  icon: const Icon(Icons.more_horiz_rounded),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(PixTokens.radiusM),
                  ),
                  onSelected: (a) => unawaited(_menu(context, a)),
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: _Menu.rename,
                      child: ListTile(
                        leading: const Icon(Icons.edit_rounded),
                        title: Text(l.rename),
                      ),
                    ),
                    PopupMenuItem(
                      value: _Menu.duplicate,
                      child: ListTile(
                        leading: const Icon(Icons.copy_rounded),
                        title: Text(l.duplicate),
                      ),
                    ),
                    PopupMenuItem(
                      value: _Menu.export,
                      child: ListTile(
                        leading: const Icon(Icons.inventory_2_rounded),
                        title: Text(l.exportProject),
                      ),
                    ),
                    PopupMenuItem(
                      value: _Menu.delete,
                      child: ListTile(
                        leading: Icon(
                          Icons.delete_outline_rounded,
                          color: theme.colorScheme.error,
                        ),
                        title: Text(
                          l.delete,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

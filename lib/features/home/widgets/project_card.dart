import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../../ui/widgets/confirm_dialog.dart';

import '../../../app/app_scope.dart';
import '../../../app/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../projects/project_store.dart';
import '../../../ui/widgets/checkerboard.dart';
import '../../../ui/widgets/soft_card.dart';
import '../../../projects/project_share.dart';
import 'text_prompt.dart';

enum _Menu { favorite, rename, duplicate, export, delete }

class ProjectCard extends StatefulWidget {
  const ProjectCard({
    super.key,
    required this.summary,
    required this.onOpen,
    this.list = false,
    this.favorite = false,
  });

  final ProjectSummary summary;
  final VoidCallback onOpen;

  /// A wide row (list view) instead of a tile.
  final bool list;

  /// Starred on the projects page.
  final bool favorite;

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
      case _Menu.favorite:
        AppScope.of(context).settings.toggleFavorite(summary.id);
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
        final ok = await showConfirmDialog(
          context,
          title: l.deleteProjectTitle,
          message: l.deleteProjectBody,
        );
        if (ok) await repo.delete(summary.id);
    }
  }

  Widget _thumb(PixColors pix, {double pad = 8}) => ClipRRect(
    borderRadius: BorderRadius.circular(PixTokens.radiusM),
    child: ColoredBox(
      color: pix.canvasBackdrop,
      child: Padding(
        padding: EdgeInsets.all(pad),
        child: Center(
          child: AspectRatio(
            aspectRatio: summary.width / summary.height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CheckerboardBox(a: pix.checkerA, b: pix.checkerB, cell: 6),
                if (summary.thumbnail != null)
                  Image.memory(
                    summary.thumbnail!,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                    // Decoded at card size, not the stored size: large
                    // decodes on scroll were a source of jank.
                    cacheWidth: 360,
                    filterQuality: FilterQuality.medium,
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _menuButton(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return PopupMenuButton<_Menu>(
      key: _menuKey,
      tooltip: l.more,
      icon: const Icon(Icons.more_horiz_rounded),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      onSelected: (a) => unawaited(_menu(context, a)),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _Menu.favorite,
          child: ListTile(
            leading: Icon(
              widget.favorite ? Icons.star_rounded : Icons.star_outline_rounded,
              color: const Color(0xFFFFB300),
            ),
            title: Text(widget.favorite ? l.removeFavorite : l.addFavorite),
          ),
        ),
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
    );
  }

  String _date(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    try {
      return DateFormat.yMMMd(locale).add_Hm().format(summary.updatedAt);
    } catch (_) {
      return DateFormat.yMMMd().add_Hm().format(summary.updatedAt);
    }
  }

  Widget _star() => AnimatedScale(
    scale: widget.favorite ? 1 : 0,
    duration: const Duration(milliseconds: 380),
    curve: Curves.elasticOut,
    child: const Icon(Icons.star_rounded, size: 18, color: Color(0xFFFFB300)),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pix = PixColors.of(context);
    final size = Text(
      '${summary.width.round()} × ${summary.height.round()}',
      textDirection: TextDirection.ltr,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
    final name = Text(
      summary.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
    );
    if (widget.list) {
      return SoftCard(
        onTap: widget.onOpen,
        onLongPress: () => _menuKey.currentState?.showButtonMenu(),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              SizedBox(width: 76, height: 76, child: _thumb(pix, pad: 5)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(child: name),
                        const SizedBox(width: 4),
                        _star(),
                      ],
                    ),
                    const SizedBox(height: 4),
                    size,
                    const SizedBox(height: 2),
                    Text(
                      _date(context),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _menuButton(context),
            ],
          ),
        ),
      );
    }
    return SoftCard(
      onTap: widget.onOpen,
      onLongPress: () => _menuKey.currentState?.showButtonMenu(),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _thumb(pix),
                  PositionedDirectional(top: 6, start: 6, child: _star()),
                ],
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
                      children: [name, size],
                    ),
                  ),
                ),
                _menuButton(context),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

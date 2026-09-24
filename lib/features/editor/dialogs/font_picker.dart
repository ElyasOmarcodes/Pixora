import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/app_scope.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/fonts/font_catalog.dart';
import '../../../document/render/text_layout.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui/widgets/confirm_dialog.dart';

/// Opens the full-page font picker. Returns the chosen family, or null.
Future<String?> showFontPicker(
  BuildContext context, {
  required String current,
  String sample = '',
}) => Navigator.of(context).push<String>(
  PageRouteBuilder(
    fullscreenDialog: true,
    transitionDuration: PixTokens.medium,
    reverseTransitionDuration: PixTokens.fast,
    pageBuilder: (_, _, _) => _FontPickerPage(current: current, sample: sample),
    transitionsBuilder: (_, a, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: a, curve: PixTokens.emphasized)),
        child: child,
      ),
    ),
  ),
);

enum _Tab { pixora, mine, recent, favorites }

class _FontPickerPage extends StatefulWidget {
  const _FontPickerPage({required this.current, required this.sample});
  final String current;
  final String sample;

  @override
  State<_FontPickerPage> createState() => _FontPickerPageState();
}

class _FontPickerPageState extends State<_FontPickerPage> {
  late String _selected = widget.current;
  _Tab _tab = _Tab.pixora;
  FontScript? _script;
  String _query = '';

  String get _sample {
    final t = widget.sample.trim().replaceAll('\n', ' ');
    if (t.isEmpty) return 'پیکسورا Pixora';
    return t.length > 40 ? '${t.substring(0, 40)}…' : t;
  }

  List<String> _families(FontCatalog c) {
    final list = switch (_tab) {
      _Tab.pixora => [
        for (final f in FontCatalog.bundled)
          if (_script == null || f.script == _script) f.family,
      ],
      _Tab.mine => [for (final f in c.userFonts) f.family],
      _Tab.recent => c.recent.where(c.isAvailable).toList(),
      _Tab.favorites => c.favorites.where(c.isAvailable).toList(),
    };
    final q = _query.trim().toLowerCase();
    return q.isEmpty
        ? list
        : list.where((f) => f.toLowerCase().contains(q)).toList();
  }

  void _apply(FontCatalog catalog, String family) {
    catalog.markUsed(family);
    Navigator.pop(context, family);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final catalog = AppScope.of(context).fonts;
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 1000 ? 4 : (width >= 640 ? 3 : 2);

    return ListenableBuilder(
      listenable: catalog,
      builder: (context, _) {
        final families = _families(catalog);
        final showImport = _tab == _Tab.mine;
        return Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          body: CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: 210,
                backgroundColor: scheme.surface,
                surfaceTintColor: Colors.transparent,
                leading: IconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
                title: Text(
                  l.font,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                actions: [
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 12),
                    child: FilledButton.icon(
                      onPressed: () => _apply(catalog, _selected),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: Text(l.apply),
                    ),
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  collapseMode: CollapseMode.pin,
                  background: _Preview(sample: _sample, family: _selected),
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _TabsHeader(
                  height: 124,
                  child: Container(
                    color: theme.scaffoldBackgroundColor,
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                    child: Column(
                      children: [
                        _TabBar(
                          selected: _tab,
                          labels: {
                            _Tab.pixora: (
                              Icons.auto_awesome_rounded,
                              l.fontsApp,
                            ),
                            _Tab.mine: (
                              Icons.folder_special_rounded,
                              l.fontsMine,
                            ),
                            _Tab.recent: (Icons.history_rounded, l.fontsRecent),
                            _Tab.favorites: (
                              Icons.favorite_rounded,
                              l.fontsFavorites,
                            ),
                          },
                          onChanged: (t) => setState(() => _tab = t),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          onChanged: (v) => setState(() => _query = v),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: l.searchFonts,
                            prefixIcon: const Icon(Icons.search_rounded),
                            filled: true,
                            fillColor: scheme.onSurface.withValues(alpha: 0.05),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_tab == _Tab.pixora)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 48,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: [
                        for (final (s, label) in [
                          (null, l.filterAll),
                          (FontScript.arabic, l.fontsArabicScript),
                          (FontScript.latin, l.fontsLatin),
                        ])
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 6,
                            ),
                            child: ChoiceChip(
                              label: Text(label),
                              selected: _script == s,
                              onSelected: (_) => setState(() => _script = s),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              if (families.isEmpty && !showImport)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _Empty(
                    icon: switch (_tab) {
                      _Tab.recent => Icons.history_rounded,
                      _Tab.favorites => Icons.favorite_border_rounded,
                      _ => Icons.search_off_rounded,
                    },
                    text: l.nothingHereYet,
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 32),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 1.35,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      childCount: families.length + (showImport ? 1 : 0),
                      (context, i) {
                        if (showImport && i == 0) {
                          return _ImportCard(
                            hint: families.isEmpty ? l.noUserFonts : null,
                            label: l.importFont,
                            onTap: () async {
                              final added = await catalog.import();
                              if (added.isNotEmpty && mounted) {
                                setState(() => _selected = added.first);
                              }
                            },
                          );
                        }
                        final f = families[i - (showImport ? 1 : 0)];
                        final user = catalog.userFonts
                            .where((u) => u.family == f)
                            .firstOrNull;
                        return _FontCard(
                          family: f,
                          sample: _sample,
                          selected: f == _selected,
                          favorite: catalog.isFavorite(f),
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _selected = f);
                          },
                          onDoubleTap: () => _apply(catalog, f),
                          onFavorite: () => catalog.toggleFavorite(f),
                          onDelete: user == null
                              ? null
                              : () async {
                                  if (await showConfirmDialog(
                                    context,
                                    title: l.deleteFontTitle(f),
                                  )) {
                                    await catalog.remove(user);
                                  }
                                },
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.sample, required this.family});
  final String sample;
  final String family;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [
            scheme.primary.withValues(alpha: 0.20),
            scheme.tertiary.withValues(alpha: 0.14),
            scheme.surface,
          ],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(24, 96, 24, 18),
      alignment: Alignment.center,
      child: AnimatedSwitcher(
        duration: PixTokens.fast,
        child: Column(
          key: ValueKey(family),
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                sample,
                maxLines: 1,
                textDirection: detectTextDirection(sample),
                style: TextStyle(
                  fontFamily: family == 'System' ? null : family,
                  fontFamilyFallback: FontCatalog.fallback,
                  fontSize: 40,
                  height: 1.3,
                  color: scheme.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                family,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({
    required this.selected,
    required this.labels,
    required this.onChanged,
  });
  final _Tab selected;
  final Map<_Tab, (IconData, String)> labels;
  final ValueChanged<_Tab> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          for (final e in labels.entries)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(e.key),
                child: AnimatedContainer(
                  duration: PixTokens.fast,
                  curve: PixTokens.curve,
                  decoration: BoxDecoration(
                    color: e.key == selected
                        ? scheme.surface
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: e.key == selected
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        e.value.$1,
                        size: 16,
                        color: e.key == selected
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          e.value.$2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: e.key == selected
                                ? FontWeight.w800
                                : FontWeight.w500,
                            color: e.key == selected
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TabsHeader extends SliverPersistentHeaderDelegate {
  _TabsHeader({required this.child, required this.height});
  final Widget child;
  final double height;

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      child;

  @override
  bool shouldRebuild(_TabsHeader old) => true;
}

class _FontCard extends StatelessWidget {
  const _FontCard({
    required this.family,
    required this.sample,
    required this.selected,
    required this.favorite,
    required this.onTap,
    required this.onDoubleTap,
    required this.onFavorite,
    this.onDelete,
  });

  final String family;
  final String sample;
  final bool selected;
  final bool favorite;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final VoidCallback onFavorite;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AnimatedContainer(
      duration: PixTokens.fast,
      curve: PixTokens.curve,
      decoration: BoxDecoration(
        color: selected
            ? scheme.primary.withValues(alpha: 0.10)
            : scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: selected ? 0.08 : 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          onDoubleTap: onDoubleTap,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            sample,
                            maxLines: 1,
                            textDirection: detectTextDirection(sample),
                            style: TextStyle(
                              fontFamily: family == 'System' ? null : family,
                              fontFamilyFallback: FontCatalog.fallback,
                              fontSize: 26,
                              height: 1.3,
                              color: scheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Text(
                      family,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: selected
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                        fontWeight: selected ? FontWeight.w800 : null,
                      ),
                    ),
                  ],
                ),
              ),
              PositionedDirectional(
                top: 2,
                end: 2,
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 20,
                  onPressed: onFavorite,
                  icon: Icon(
                    favorite
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: favorite
                        ? const Color(0xFFFF5A7A)
                        : scheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                ),
              ),
              if (onDelete != null)
                PositionedDirectional(
                  top: 2,
                  start: 2,
                  child: IconButton(
                    visualDensity: VisualDensity.compact,
                    iconSize: 20,
                    onPressed: onDelete,
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              if (selected)
                PositionedDirectional(
                  bottom: 8,
                  end: 8,
                  child: CircleAvatar(
                    radius: 10,
                    backgroundColor: scheme.primary,
                    child: Icon(
                      Icons.check_rounded,
                      size: 14,
                      color: scheme.onPrimary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImportCard extends StatelessWidget {
  const _ImportCard({required this.label, required this.onTap, this.hint});
  final String label;
  final String? hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.primary.withValues(alpha: 0.06),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: scheme.primary.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: scheme.primary,
                child: Icon(Icons.add_rounded, color: scheme.onPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                '.ttf · .otf',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 40, color: scheme.primary),
          ),
          const SizedBox(height: 14),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

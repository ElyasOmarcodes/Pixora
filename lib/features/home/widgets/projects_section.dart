import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/app_scope.dart';
import '../../../app/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../projects/project_store.dart';
import 'project_card.dart';

enum _When { any, today, week, month }

enum _Shape { any, square, portrait, landscape }

/// Sort orders, in the order the menu lists them (stored by index).
enum ProjectSort { recent, oldest, nameAz, nameZa, largest }

/// "My projects": a header with the count, sort and view switch, a pinned
/// search field with filter chips (date, shape, favourites), and the
/// projects as a grid or a list that animates as the filters change.
class ProjectsSection extends StatefulWidget {
  const ProjectsSection({
    super.key,
    required this.projects,
    required this.onOpen,
    required this.pad,
    required this.empty,
  });

  final Future<List<ProjectSummary>>? projects;
  final void Function(ProjectSummary p) onOpen;
  final double pad;

  /// Shown when there are no projects at all.
  final Widget empty;

  @override
  State<ProjectsSection> createState() => _ProjectsSectionState();
}

class _ProjectsSectionState extends State<ProjectsSection> {
  final _search = TextEditingController();
  _When _when = _When.any;
  _Shape _shape = _Shape.any;
  bool _favorites = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool get _filtering =>
      _search.text.trim().isNotEmpty ||
      _when != _When.any ||
      _shape != _Shape.any ||
      _favorites;

  List<ProjectSummary> _apply(
    List<ProjectSummary> all,
    Set<String> favs,
    ProjectSort sort,
  ) {
    final q = _search.text.trim().toLowerCase();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final since = switch (_when) {
      _When.any => null,
      _When.today => today,
      _When.week => today.subtract(const Duration(days: 7)),
      _When.month => today.subtract(const Duration(days: 30)),
    };
    final out = [
      for (final p in all)
        if ((q.isEmpty || p.name.toLowerCase().contains(q)) &&
            (since == null || !p.updatedAt.isBefore(since)) &&
            (!_favorites || favs.contains(p.id)) &&
            switch (_shape) {
              _Shape.any => true,
              _Shape.square => (p.width / p.height - 1).abs() < 0.02,
              _Shape.portrait => p.height > p.width * 1.02,
              _Shape.landscape => p.width > p.height * 1.02,
            })
          p,
    ];
    int byName(ProjectSummary a, ProjectSummary b) =>
        a.name.toLowerCase().compareTo(b.name.toLowerCase());
    out.sort(
      (a, b) => switch (sort) {
        ProjectSort.recent => b.updatedAt.compareTo(a.updatedAt),
        ProjectSort.oldest => a.updatedAt.compareTo(b.updatedAt),
        ProjectSort.nameAz => byName(a, b),
        ProjectSort.nameZa => byName(b, a),
        ProjectSort.largest => (b.width * b.height).compareTo(
          a.width * a.height,
        ),
      },
    );
    // Starred projects first (within the chosen order).
    final starred = [
      for (final p in out)
        if (favs.contains(p.id)) p,
    ];
    return [
      ...starred,
      for (final p in out)
        if (!favs.contains(p.id)) p,
    ];
  }

  void _clearFilters() => setState(() {
    _search.clear();
    _when = _When.any;
    _shape = _Shape.any;
    _favorites = false;
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final settings = AppScope.of(context).settings;
    final pad = widget.pad;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => FutureBuilder<List<ProjectSummary>>(
        future: widget.projects,
        builder: (context, snap) {
          final all = snap.data ?? const <ProjectSummary>[];
          final loading =
              snap.connectionState != ConnectionState.done && all.isEmpty;
          final favs = settings.favoriteProjects;
          final sort =
              ProjectSort.values[settings.projectSort.clamp(
                0,
                ProjectSort.values.length - 1,
              )];
          final items = _apply(all, favs, sort);
          final list = settings.projectListView;
          // Re-keys the results so they animate in again on a new filter.
          final signature = Object.hash(
            _search.text,
            _when,
            _shape,
            _favorites,
            sort,
            list,
          );

          Widget results;
          if (loading) {
            results = const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator.adaptive()),
              ),
            );
          } else if (all.isEmpty) {
            results = SliverToBoxAdapter(child: widget.empty);
          } else if (items.isEmpty) {
            results = SliverToBoxAdapter(
              child: _NoResults(onClear: _clearFilters),
            );
          } else if (list) {
            results = SliverPadding(
              padding: EdgeInsets.fromLTRB(pad, 4, pad, 32),
              sliver: SliverList.builder(
                itemCount: items.length,
                itemBuilder: (context, i) => _Appear(
                  key: ValueKey((signature, items[i].id)),
                  index: i,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: ProjectCard(
                      summary: items[i],
                      list: true,
                      favorite: favs.contains(items[i].id),
                      onOpen: () => widget.onOpen(items[i]),
                    ),
                  ),
                ),
              ),
            );
          } else {
            results = SliverPadding(
              padding: EdgeInsets.fromLTRB(pad, 4, pad, 32),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 230,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 0.78,
                ),
                itemCount: items.length,
                itemBuilder: (context, i) => _Appear(
                  key: ValueKey((signature, items[i].id)),
                  index: i,
                  child: ProjectCard(
                    summary: items[i],
                    favorite: favs.contains(items[i].id),
                    onOpen: () => widget.onOpen(items[i]),
                  ),
                ),
              ),
            );
          }

          return SliverMainAxisGroup(
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(pad, 28, pad - 8, 4),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      Text(
                        l.myProjects,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 8),
                      AnimatedSwitcher(
                        duration: PixTokens.fast,
                        transitionBuilder: (c, a) =>
                            ScaleTransition(scale: a, child: c),
                        child: all.isEmpty
                            ? const SizedBox.shrink()
                            : Container(
                                key: ValueKey('${items.length}/${all.length}'),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary.withValues(
                                    alpha: 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  _filtering
                                      ? '${items.length} / ${all.length}'
                                      : '${all.length}',
                                  textDirection: TextDirection.ltr,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                      ),
                      const Spacer(),
                      if (all.isNotEmpty) ...[
                        _SortButton(
                          value: sort,
                          onChanged: (v) => settings.projectSort = v.index,
                        ),
                        IconButton(
                          tooltip: list ? l.gridView : l.listView,
                          onPressed: () {
                            HapticFeedback.selectionClick();
                            settings.projectListView = !list;
                          },
                          icon: AnimatedSwitcher(
                            duration: PixTokens.fast,
                            transitionBuilder: (c, a) => RotationTransition(
                              turns: Tween(begin: 0.75, end: 1.0).animate(a),
                              child: FadeTransition(opacity: a, child: c),
                            ),
                            child: Icon(
                              list
                                  ? Icons.grid_view_rounded
                                  : Icons.view_agenda_rounded,
                              key: ValueKey(list),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (all.isNotEmpty)
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _FilterBarDelegate(
                    pad: pad,
                    background: theme.scaffoldBackgroundColor,
                    child: _FilterBar(
                      search: _search,
                      onSearch: () => setState(() {}),
                      when: _when,
                      shape: _shape,
                      favorites: _favorites,
                      onWhen: (v) => setState(() => _when = v),
                      onShape: (v) => setState(() => _shape = v),
                      onFavorites: (v) => setState(() => _favorites = v),
                    ),
                  ),
                ),
              results,
            ],
          );
        },
      ),
    );
  }
}

class _SortButton extends StatelessWidget {
  const _SortButton({required this.value, required this.onChanged});
  final ProjectSort value;
  final ValueChanged<ProjectSort> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    String label(ProjectSort s) => switch (s) {
      ProjectSort.recent => l.sortRecent,
      ProjectSort.oldest => l.sortOldest,
      ProjectSort.nameAz => l.sortNameAz,
      ProjectSort.nameZa => l.sortNameZa,
      ProjectSort.largest => l.sortLargest,
    };
    IconData icon(ProjectSort s) => switch (s) {
      ProjectSort.recent => Icons.schedule_rounded,
      ProjectSort.oldest => Icons.history_rounded,
      ProjectSort.nameAz => Icons.sort_by_alpha_rounded,
      ProjectSort.nameZa => Icons.sort_by_alpha_rounded,
      ProjectSort.largest => Icons.photo_size_select_large_rounded,
    };
    return PopupMenuButton<ProjectSort>(
      tooltip: l.sortBy,
      initialValue: value,
      onSelected: onChanged,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      icon: const Icon(Icons.swap_vert_rounded),
      itemBuilder: (context) => [
        for (final s in ProjectSort.values)
          PopupMenuItem(
            value: s,
            child: Row(
              children: [
                Icon(
                  icon(s),
                  size: 20,
                  color: s == value
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(label(s))),
                if (s == value)
                  Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _FilterBarDelegate extends SliverPersistentHeaderDelegate {
  _FilterBarDelegate({
    required this.child,
    required this.pad,
    required this.background,
  });
  final Widget child;
  final double pad;
  final Color background;

  static const double height = 118;

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrink, bool overlaps) =>
      AnimatedContainer(
        duration: PixTokens.fast,
        decoration: BoxDecoration(
          color: background,
          boxShadow: [
            if (overlaps)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        padding: EdgeInsets.symmetric(horizontal: pad - 4),
        child: child,
      );

  @override
  bool shouldRebuild(_FilterBarDelegate old) =>
      old.child != child || old.pad != pad || old.background != background;
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.search,
    required this.onSearch,
    required this.when,
    required this.shape,
    required this.favorites,
    required this.onWhen,
    required this.onShape,
    required this.onFavorites,
  });
  final TextEditingController search;
  final VoidCallback onSearch;
  final _When when;
  final _Shape shape;
  final bool favorites;
  final ValueChanged<_When> onWhen;
  final ValueChanged<_Shape> onShape;
  final ValueChanged<bool> onFavorites;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    Widget chip({
      required String label,
      required bool selected,
      required VoidCallback onTap,
      IconData? icon,
    }) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: FilterChip(
        showCheckmark: false,
        avatar: icon == null
            ? null
            : Icon(
                icon,
                size: 16,
                color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
              ),
        label: Text(label),
        selected: selected,
        selectedColor: scheme.primary,
        labelStyle: TextStyle(
          color: selected ? scheme.onPrimary : null,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        onSelected: (_) {
          HapticFeedback.selectionClick();
          onTap();
        },
      ),
    );
    Widget divider() => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      child: VerticalDivider(width: 1, color: scheme.outlineVariant),
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
          child: TextField(
            controller: search,
            onChanged: (_) => onSearch(),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: l.searchProjects,
              filled: true,
              fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: AnimatedSwitcher(
                duration: PixTokens.fast,
                child: search.text.isEmpty
                    ? const SizedBox.shrink()
                    : IconButton(
                        key: const ValueKey('clear'),
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          search.clear();
                          onSearch();
                        },
                      ),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide(color: scheme.primary, width: 1.5),
              ),
            ),
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(vertical: 4),
            children: [
              chip(
                label: l.favorites,
                icon: favorites
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
                selected: favorites,
                onTap: () => onFavorites(!favorites),
              ),
              divider(),
              for (final (w, label) in [
                (_When.today, l.filterToday),
                (_When.week, l.filterWeek),
                (_When.month, l.filterMonth),
              ])
                chip(
                  label: label,
                  selected: when == w,
                  onTap: () => onWhen(when == w ? _When.any : w),
                ),
              divider(),
              for (final (s, label, icon) in [
                (_Shape.square, l.filterSquare, Icons.crop_square_rounded),
                (
                  _Shape.portrait,
                  l.filterPortrait,
                  Icons.crop_portrait_rounded,
                ),
                (
                  _Shape.landscape,
                  l.filterLandscape,
                  Icons.crop_landscape_rounded,
                ),
              ])
                chip(
                  label: label,
                  icon: icon,
                  selected: shape == s,
                  onTap: () => onShape(shape == s ? _Shape.any : s),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Fades and rises in, a little later for each [index] (capped), when a
/// result first shows.
class _Appear extends StatefulWidget {
  const _Appear({super.key, required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  State<_Appear> createState() => _AppearState();
}

class _AppearState extends State<_Appear> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 460),
  );
  late final Animation<double> _a = CurvedAnimation(
    parent: _c,
    curve: Curves.easeOutCubic,
  );

  @override
  void initState() {
    super.initState();
    final delay = Duration(milliseconds: 40 * widget.index.clamp(0, 8));
    Future.delayed(delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _a,
    builder: (context, child) => Opacity(
      opacity: _a.value,
      child: Transform.translate(
        offset: Offset(0, 18 * (1 - _a.value)),
        child: Transform.scale(scale: 0.96 + 0.04 * _a.value, child: child),
      ),
    ),
    child: widget.child,
  );
}

class _NoResults extends StatelessWidget {
  const _NoResults({required this.onClear});
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
      child: Column(
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 56,
            color: theme.colorScheme.primary.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 12),
          Text(
            l.noSearchResults,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: onClear,
            icon: const Icon(Icons.filter_alt_off_rounded),
            label: Text(l.clearFilters),
          ),
        ],
      ),
    );
  }
}

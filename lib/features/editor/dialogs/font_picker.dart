import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/fonts/font_catalog.dart';
import '../../../document/render/text_layout.dart';
import '../../../l10n/app_localizations.dart';

/// Opens the font picker. Returns the chosen family, or null if cancelled.
Future<String?> showFontPicker(
  BuildContext context, {
  required String current,
  String sample = '',
}) => showDialog<String>(
  context: context,
  builder: (_) => _FontPicker(current: current, sample: sample),
);

enum _Tab { pixora, mine, recent, favorites }

class _FontPicker extends StatefulWidget {
  const _FontPicker({required this.current, required this.sample});
  final String current;
  final String sample;

  @override
  State<_FontPicker> createState() => _FontPickerState();
}

class _FontPickerState extends State<_FontPicker> {
  late String _selected = widget.current;
  _Tab _tab = _Tab.pixora;
  FontScript? _script;
  String _query = '';

  String get _sample {
    final t = widget.sample.trim().replaceAll('\n', ' ');
    if (t.isEmpty) return 'پیکسورا Pixora';
    return t.length > 32 ? '${t.substring(0, 32)}…' : t;
  }

  List<String> _families(FontCatalog c) {
    final all = <String>[
      for (final f in FontCatalog.bundled)
        if (_script == null || f.script == _script) f.family,
    ];
    final list = switch (_tab) {
      _Tab.pixora => all,
      _Tab.mine => [for (final f in c.userFonts) f.family],
      _Tab.recent => c.recent.where(c.isAvailable).toList(),
      _Tab.favorites => c.favorites.where(c.isAvailable).toList(),
    };
    final q = _query.trim().toLowerCase();
    return q.isEmpty
        ? list
        : list.where((f) => f.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final catalog = AppScope.of(context).fonts;
    final size = MediaQuery.sizeOf(context);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: size.height * 0.9,
        ),
        child: ListenableBuilder(
          listenable: catalog,
          builder: (context, _) {
            final families = _families(catalog);
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Live preview.
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        scheme.primary.withValues(alpha: 0.14),
                        scheme.tertiary.withValues(alpha: 0.10),
                      ],
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        _sample,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        textDirection: detectTextDirection(_sample),
                        style: TextStyle(
                          fontFamily: _selected == 'System' ? null : _selected,
                          fontSize: 34,
                          height: 1.35,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _selected,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: SegmentedButton<_Tab>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                    segments: [
                      ButtonSegment(
                        value: _Tab.pixora,
                        label: Text(l.fontsApp),
                      ),
                      ButtonSegment(value: _Tab.mine, label: Text(l.fontsMine)),
                      ButtonSegment(
                        value: _Tab.recent,
                        icon: const Icon(Icons.history_rounded, size: 18),
                        tooltip: l.fontsRecent,
                      ),
                      ButtonSegment(
                        value: _Tab.favorites,
                        icon: const Icon(Icons.favorite_rounded, size: 18),
                        tooltip: l.fontsFavorites,
                      ),
                    ],
                    selected: {_tab},
                    onSelectionChanged: (s) => setState(() => _tab = s.first),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          onChanged: (v) => setState(() => _query = v),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: l.searchFonts,
                            prefixIcon: const Icon(Icons.search_rounded),
                            filled: true,
                            fillColor: scheme.onSurface.withValues(alpha: 0.05),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      if (_tab == _Tab.mine) ...[
                        const SizedBox(width: 8),
                        FilledButton.tonalIcon(
                          onPressed: () async {
                            final added = await catalog.import();
                            if (added.isNotEmpty && mounted) {
                              setState(() => _selected = added.first);
                            }
                          },
                          icon: const Icon(Icons.upload_file_rounded),
                          label: Text(l.importFont),
                        ),
                      ],
                    ],
                  ),
                ),
                if (_tab == _Tab.pixora)
                  SizedBox(
                    height: 44,
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
                              vertical: 4,
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
                Flexible(
                  child: families.isEmpty
                      ? _Empty(
                          icon: switch (_tab) {
                            _Tab.mine => Icons.font_download_off_rounded,
                            _Tab.recent => Icons.history_rounded,
                            _Tab.favorites => Icons.favorite_border_rounded,
                            _Tab.pixora => Icons.search_off_rounded,
                          },
                          text: switch (_tab) {
                            _Tab.mine => l.noUserFonts,
                            _ => l.nothingHereYet,
                          },
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                          itemCount: families.length,
                          itemBuilder: (context, i) {
                            final f = families[i];
                            final user = catalog.userFonts
                                .where((u) => u.family == f)
                                .firstOrNull;
                            return _FontTile(
                              family: f,
                              sample: _sample,
                              selected: f == _selected,
                              favorite: catalog.isFavorite(f),
                              onTap: () => setState(() => _selected = f),
                              onDoubleTap: () => _apply(catalog, f),
                              onFavorite: () => catalog.toggleFavorite(f),
                              onDelete: user == null
                                  ? null
                                  : () => catalog.remove(user),
                            );
                          },
                        ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(l.cancel),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => _apply(catalog, _selected),
                          child: Text(l.apply),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _apply(FontCatalog catalog, String family) {
    catalog.markUsed(family);
    Navigator.pop(context, family);
  }
}

class _FontTile extends StatelessWidget {
  const _FontTile({
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
    final fontFamily = family == 'System' ? null : family;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: selected
            ? scheme.primary.withValues(alpha: 0.12)
            : scheme.onSurface.withValues(alpha: 0.035),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PixTokens.radiusM),
          side: BorderSide(
            color: selected ? scheme.primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(PixTokens.radiusM),
          onTap: onTap,
          onDoubleTap: onDoubleTap,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 4, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sample,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: detectTextDirection(sample),
                        style: TextStyle(
                          fontFamily: fontFamily,
                          fontSize: 22,
                          height: 1.3,
                          color: scheme.onSurface,
                        ),
                      ),
                      Text(
                        family,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onDelete != null)
                  IconButton(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                IconButton(
                  onPressed: onFavorite,
                  icon: Icon(
                    favorite
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: favorite ? const Color(0xFFFF5A7A) : null,
                  ),
                ),
              ],
            ),
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
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: scheme.onSurfaceVariant),
          const SizedBox(height: 10),
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

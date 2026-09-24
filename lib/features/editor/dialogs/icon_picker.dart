import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/icons/icon_catalog.dart';
import '../../../document/model/layer.dart';
import '../../../document/render/svg_path.dart';
import '../../../l10n/app_localizations.dart';

/// Full-page icon browser: thousands of Material Symbols with search,
/// style (outlined / rounded / sharp), fill and weight. Returns the chosen
/// icon with its path data, or null.
Future<IconPick?> showIconPicker(BuildContext context, {IconPick? current}) =>
    Navigator.of(context).push<IconPick>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _IconPickerPage(current: current),
      ),
    );

class _IconPickerPage extends StatefulWidget {
  const _IconPickerPage({this.current});
  final IconPick? current;

  @override
  State<_IconPickerPage> createState() => _IconPickerPageState();
}

class _IconPickerPageState extends State<_IconPickerPage> {
  List<String>? _sorted;
  final _catalog = IconCatalog.instance;
  Map<String, String>? _icons;
  String _query = '';
  bool _popular = true;
  late String? _selected = widget.current?.name;
  late IconStyle _style = widget.current?.style ?? IconStyle.outlined;
  late bool _filled = widget.current?.filled ?? false;
  late int _weight = widget.current?.weight ?? 400;
  String? _preview;
  bool _loading = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _catalog.load().then((m) {
      if (mounted) setState(() => _icons = m);
      _refreshPreview();
    });
  }

  List<String> get _names {
    final icons = _icons;
    if (icons == null) return const [];
    final q = _query.trim().toLowerCase().replaceAll(' ', '_');
    if (q.isEmpty && _popular) {
      return [
        for (final n in IconCatalog.popular)
          if (icons.containsKey(n)) n,
      ];
    }
    final all = _sorted ??= (icons.keys.toList()..sort());
    return q.isEmpty ? all : all.where((n) => n.contains(q)).toList();
  }

  Future<void> _refreshPreview() async {
    final name = _selected;
    if (name == null) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    final d = await _catalog.pathFor(
      name,
      style: _style,
      filled: _filled,
      weight: _weight,
    );
    if (!mounted || name != _selected) return;
    setState(() {
      _loading = false;
      _failed = d == null;
      _preview = d ?? _catalog.outlined(name);
    });
  }

  void _add() {
    final name = _selected, d = _preview;
    if (name == null || d == null) return;
    Navigator.pop(
      context,
      IconPick(
        name: name,
        pathData: d,
        style: _failed ? IconStyle.outlined : _style,
        filled: !_failed && _filled,
        weight: _failed ? 400 : _weight,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final names = _names;
    final width = MediaQuery.sizeOf(context).width;
    final cols = (width / 72).floor().clamp(4, 12);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close_rounded),
        ),
        title: Text(
          l.icons,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: FilledButton.icon(
              onPressed: _selected == null || _preview == null ? null : _add,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(l.add),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                isDense: true,
                hintText: l.searchIcons,
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: scheme.onSurface.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          if (_query.isEmpty)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final (pop, label) in [
                    (true, l.popular),
                    (false, l.allIcons(_icons?.length ?? 0)),
                  ])
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
                      child: ChoiceChip(
                        label: Text(label),
                        selected: _popular == pop,
                        onSelected: (_) => setState(() => _popular = pop),
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: _icons == null
                ? const Center(child: CircularProgressIndicator())
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      mainAxisSpacing: 6,
                      crossAxisSpacing: 6,
                    ),
                    itemCount: names.length,
                    itemBuilder: (context, i) {
                      final n = names[i];
                      final sel = n == _selected;
                      return Tooltip(
                        message: n.replaceAll('_', ' '),
                        waitDuration: const Duration(milliseconds: 600),
                        child: Material(
                          color: sel
                              ? scheme.primary.withValues(alpha: 0.14)
                              : scheme.onSurface.withValues(alpha: 0.04),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: sel ? scheme.primary : Colors.transparent,
                              width: 1.5,
                            ),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            // Instant: no double-tap detector (it delays
                            // every tap). Tap the selected icon again to add.
                            onTap: () {
                              HapticFeedback.selectionClick();
                              if (sel && !_loading) {
                                _add();
                                return;
                              }
                              setState(() {
                                _selected = n;
                                _preview = _icons![n];
                              });
                              _refreshPreview();
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: _StyledIcon(
                                name: n,
                                style: _style,
                                filled: _filled,
                                weight: _weight,
                                color: sel ? scheme.primary : scheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          // Style bar with the live preview of the selected icon.
          Container(
            decoration: BoxDecoration(
              color: theme.bottomSheetTheme.backgroundColor ?? scheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(PixTokens.radiusL),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 20,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: _loading
                        ? const Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                              ),
                            ),
                          )
                        : _preview == null
                        ? Icon(
                            Icons.touch_app_rounded,
                            color: scheme.onSurfaceVariant,
                          )
                        : SvgIcon(_preview!, color: scheme.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SegmentedButton<IconStyle>(
                          showSelectedIcon: false,
                          style: const ButtonStyle(
                            visualDensity: VisualDensity.compact,
                          ),
                          segments: [
                            ButtonSegment(
                              value: IconStyle.outlined,
                              label: Text(l.iconOutlined),
                            ),
                            ButtonSegment(
                              value: IconStyle.rounded,
                              label: Text(l.iconRounded),
                            ),
                            ButtonSegment(
                              value: IconStyle.sharp,
                              label: Text(l.iconSharp),
                            ),
                          ],
                          selected: {_style},
                          onSelectionChanged: (s) {
                            setState(() => _style = s.first);
                            _refreshPreview();
                          },
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            FilterChip(
                              label: Text(l.filled),
                              selected: _filled,
                              onSelected: (v) {
                                setState(() => _filled = v);
                                _refreshPreview();
                              },
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<int>(
                                  isExpanded: true,
                                  value: _weight,
                                  borderRadius: BorderRadius.circular(16),
                                  items: [
                                    for (final w in const [
                                      100,
                                      200,
                                      300,
                                      400,
                                      500,
                                      600,
                                      700,
                                    ])
                                      DropdownMenuItem(
                                        value: w,
                                        child: Text('${l.weight} $w'),
                                      ),
                                  ],
                                  onChanged: (w) {
                                    if (w == null) return;
                                    setState(() => _weight = w);
                                    _refreshPreview();
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_failed)
                          Text(
                            l.iconOffline,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.error,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A grid preview in the chosen style. Shows the bundled outlined icon at
/// once and swaps in the downloaded style when it arrives, so previews are
/// always visible — even offline or on a slow connection.
class _StyledIcon extends StatefulWidget {
  const _StyledIcon({
    required this.name,
    required this.style,
    required this.filled,
    required this.weight,
    required this.color,
  });
  final String name;
  final IconStyle style;
  final bool filled;
  final int weight;
  final Color color;

  @override
  State<_StyledIcon> createState() => _StyledIconState();
}

class _StyledIconState extends State<_StyledIcon> {
  final _catalog = IconCatalog.instance;
  bool _pending = false;

  String? get _ready => _catalog.cached(
    widget.name,
    style: widget.style,
    filled: widget.filled,
    weight: widget.weight,
  );

  int _token = 0;

  void _fetch() {
    final token = ++_token;
    if (_ready != null) {
      _pending = false;
      return;
    }
    final w = widget;
    _pending = true;
    _catalog
        .pathFor(
          w.name,
          style: w.style,
          filled: w.filled,
          weight: w.weight,
          wanted: () =>
              mounted &&
              widget.name == w.name &&
              widget.style == w.style &&
              widget.filled == w.filled &&
              widget.weight == w.weight,
        )
        .then((_) {
          // Only the latest request decides; older ones just repaint.
          if (!mounted) return;
          setState(() {
            if (token == _token) _pending = false;
          });
        });
  }

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void didUpdateWidget(_StyledIcon old) {
    super.didUpdateWidget(old);
    if (old.name != widget.name ||
        old.style != widget.style ||
        old.filled != widget.filled ||
        old.weight != widget.weight) {
      _fetch();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _ready;
    final d = ready ?? _catalog.outlined(widget.name);
    if (d == null) return const SizedBox.expand();
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: ready == null && _pending ? 0.55 : 1,
      child: SvgIcon(d, color: widget.color),
    );
  }
}

/// Draws Material Symbols path data (viewBox 0 -960 960 960).
class SvgIcon extends StatelessWidget {
  const SvgIcon(this.pathData, {super.key, required this.color});
  final String pathData;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _SvgIconPainter(pathData, color),
    child: const SizedBox.expand(),
  );
}

class _SvgIconPainter extends CustomPainter {
  _SvgIconPainter(this.d, this.color);
  final String d;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 960;
    canvas
      ..save()
      ..translate(
        (size.width - 960 * s) / 2,
        (size.height - 960 * s) / 2 + 960 * s,
      )
      ..scale(s);
    canvas.drawPath(
      SvgPathCache.get(d),
      Paint()
        ..color = color
        ..isAntiAlias = true,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SvgIconPainter old) => old.d != d || old.color != color;
}

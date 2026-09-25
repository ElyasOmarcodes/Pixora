import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_theme.dart';
import '../../core/patterns/pattern_library.dart';
import '../../document/model/fill.dart';
import '../../document/model/patterns.dart';
import '../../l10n/app_localizations.dart';
import 'color_picker.dart';
import 'confirm_dialog.dart';
import 'pattern_source.dart';
import 'pix_slider.dart';
import 'pressable.dart';

/// The Pattern side of the colour control (Photoshop's pattern fill /
/// Pattern Overlay): "+" makes a new pattern, then the user's own patterns
/// and the built-in ones; below, the pattern's colours (built-ins), scale,
/// angle, offset and a seamless (mirrored) option.
class PatternPicker extends StatelessWidget {
  const PatternPicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final PixFill? value;
  final void Function(PixFill fill, {required bool live}) onChanged;

  PixFill? get _pattern => value != null && value!.isPattern ? value : null;

  /// A new pattern fill keeps the current placement and colours.
  PixFill _with(String id, {bool? mirror}) {
    final v = _pattern;
    Color fg, bg;
    if (v != null) {
      fg = v.colors.first;
      bg = v.colors.length > 1 ? v.colors[1] : const Color(0x00000000);
    } else {
      // From a flat colour: keep it as the background and draw the
      // pattern in a contrasting colour, so the layer keeps its look.
      bg = value?.primary ?? const Color(0xFFFFFFFF);
      fg = bg.computeLuminance() > 0.5
          ? const Color(0xFF1F2937)
          : const Color(0xFFFFFFFF);
    }
    return PixFill.pattern(
      id,
      fg: fg,
      bg: bg,
      angle: v?.angle ?? 0,
      scale: v?.scale ?? 1,
      center: v?.center ?? Offset.zero,
      mirror: mirror ?? v?.mirror ?? false,
    );
  }

  Future<void> _useMine(BuildContext context, MyPattern p) async {
    final src = PatternSource.maybeOf(context);
    if (src != null) await PatternLibrary.ensureIn(src.assets, p);
    await HapticFeedback.selectionClick();
    onChanged(_with(p.patternId), live: false);
  }

  Future<void> _create(BuildContext context) async {
    final made = await showNewPatternSheet(context);
    if (made == null || !context.mounted) return;
    await _useMine(context, made.$1);
    final v = _pattern;
    if (v != null && v.mirror != made.$2) {
      onChanged(v.copyWith(mirror: made.$2), live: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final v = _pattern;
    final fg = v?.colors.first ?? value?.primary ?? const Color(0xFF000000);
    final bg = v != null && v.colors.length > 1
        ? v.colors[1]
        : const Color(0x00000000);
    final builtinSelected = v != null && !Patterns.isAsset(v.pattern!);

    void live(PixFill f) => onChanged(f, live: true);
    void done(PixFill f) => onChanged(f, live: false);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 56,
          child: ListenableBuilder(
            listenable: PatternLibrary.instance,
            builder: (context, _) {
              final mine = PatternLibrary.instance.items;
              return ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _Tile(
                    selected: false,
                    tooltip: l.newPattern,
                    onTap: () => _create(context),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.add_rounded, color: scheme.primary),
                    ),
                  ),
                  for (final p in mine)
                    _Tile(
                      selected: v?.pattern == p.patternId,
                      onTap: () => _useMine(context, p),
                      onLongPress: () async {
                        if (await showConfirmDialog(
                          context,
                          title: l.deletePattern,
                          confirmLabel: l.delete,
                        )) {
                          PatternLibrary.instance.remove(p.id);
                        }
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            image: DecorationImage(
                              image: MemoryImage(p.bytes),
                              repeat: ImageRepeat.repeat,
                              scale: 4,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (mine.isNotEmpty)
                    Center(
                      child: Container(
                        width: 1.5,
                        height: 28,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        color: scheme.outlineVariant,
                      ),
                    ),
                  for (final id in Patterns.builtins)
                    _Tile(
                      selected: v?.pattern == id,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        done(_with(id));
                      },
                      child: CustomPaint(
                        painter: _PatternSwatch(
                          _preview(id, v == null ? null : fg, bg),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        if (v != null) ...[
          if (builtinSelected) ...[
            _Label(l.patternColor),
            ColorStrip(
              value: fg,
              onChanged: (c, {required live}) {
                if (c == null) return;
                onChanged(v.copyWith(colors: [c, bg]), live: live);
              },
            ),
            _Label(l.background),
            ColorStrip(
              value: bg,
              allowTransparent: true,
              onChanged: (c, {required live}) => onChanged(
                v.copyWith(colors: [fg, c ?? const Color(0x00000000)]),
                live: live,
              ),
            ),
          ],
          PixSlider(
            label: l.scale,
            value: v.scale.clamp(0.1, 8),
            min: 0.1,
            max: 8,
            defaultValue: 1,
            format: (x) => '${(x * 100).round()}%',
            onChanged: (x) => live(v.copyWith(scale: x)),
            onChangeEnd: (x) => done(v.copyWith(scale: x)),
          ),
          PixSlider(
            label: l.angle,
            value: v.angle % 360,
            min: 0,
            max: 360,
            defaultValue: 0,
            format: (x) => '${x.round()}°',
            onChanged: (x) => live(v.copyWith(angle: x)),
            onChangeEnd: (x) => done(v.copyWith(angle: x)),
          ),
          PixSlider(
            label: l.offsetX,
            value: v.center.dx.clamp(-1, 1),
            min: -1,
            max: 1,
            defaultValue: 0,
            format: (x) => '${(x * 100).round()}%',
            onChanged: (x) => live(v.copyWith(center: Offset(x, v.center.dy))),
            onChangeEnd: (x) =>
                done(v.copyWith(center: Offset(x, v.center.dy))),
          ),
          PixSlider(
            label: l.offsetY,
            value: v.center.dy.clamp(-1, 1),
            min: -1,
            max: 1,
            defaultValue: 0,
            format: (x) => '${(x * 100).round()}%',
            onChanged: (x) => live(v.copyWith(center: Offset(v.center.dx, x))),
            onChangeEnd: (x) =>
                done(v.copyWith(center: Offset(v.center.dx, x))),
          ),
          SwitchListTile.adaptive(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            secondary: const Icon(Icons.flip_rounded),
            title: Text(l.seamless),
            subtitle: Text(l.seamlessHint),
            value: v.mirror,
            onChanged: (m) => done(v.copyWith(mirror: m)),
          ),
        ],
      ],
    );
  }
}

/// Swatch colours: the pattern's own when they read well, otherwise dark
/// on light.
PixFill _preview(String id, Color? fg, Color bg) {
  final back = bg.a < 0.05 ? const Color(0xFFF3F4F6) : bg;
  var front = fg ?? const Color(0xFF374151);
  if ((front.computeLuminance() - back.computeLuminance()).abs() < 0.25 ||
      front.a < 0.2) {
    front = back.computeLuminance() > 0.5
        ? const Color(0xFF374151)
        : const Color(0xFFF9FAFB);
  }
  return PixFill.pattern(id, fg: front, bg: back, scale: 0.5);
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.child,
    required this.selected,
    required this.onTap,
    this.onLongPress,
    this.tooltip,
  });
  final Widget child;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    Widget tile = GestureDetector(
      onLongPress: onLongPress,
      child: Pressable(
        scale: 0.9,
        onTap: onTap,
        child: AnimatedContainer(
          duration: PixTokens.fast,
          width: 48,
          height: 48,
          margin: const EdgeInsets.all(4),
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? accent : Colors.transparent,
              width: 2.5,
            ),
          ),
          child: child,
        ),
      ),
    );
    if (tooltip != null) tile = Tooltip(message: tooltip, child: tile);
    return tile;
  }
}

class _PatternSwatch extends CustomPainter {
  _PatternSwatch(this.fill);
  final PixFill fill;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, const Radius.circular(10)),
      fill.applyTo(Paint()..isAntiAlias = true, r),
    );
  }

  @override
  bool shouldRepaint(_PatternSwatch old) => old.fill != fill;
}

// ---------------------------------------------------------------- new pattern

/// Photoshop's Define Pattern: take a photo, the selected layer or the
/// current selection, preview it repeating (optionally mirrored so its
/// edges meet), and save it to "My patterns". Returns the pattern and
/// whether it should be mirrored.
Future<(MyPattern, bool)?> showNewPatternSheet(BuildContext context) =>
    showModalBottomSheet<(MyPattern, bool)>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _NewPatternSheet(source: PatternSource.maybeOf(context)),
    );

class _NewPatternSheet extends StatefulWidget {
  const _NewPatternSheet({required this.source});
  final PatternSource? source;

  @override
  State<_NewPatternSheet> createState() => _NewPatternSheetState();
}

class _NewPatternSheetState extends State<_NewPatternSheet> {
  Uint8List? _bytes;
  bool _mirror = false;
  bool _busy = false;
  double _preview = 0.35;

  Future<void> _take(Future<Uint8List?> Function()? f) async {
    if (f == null) return;
    setState(() => _busy = true);
    try {
      final b = await f();
      if (b != null && mounted) setState(() => _bytes = b);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final b = _bytes;
    if (b == null) return;
    setState(() => _busy = true);
    final p = await PatternLibrary.instance.add(b);
    if (mounted) Navigator.pop(context, (p, _mirror));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final src = widget.source;
    Widget source(
      IconData icon,
      String label,
      Future<Uint8List?> Function()? f,
    ) => Expanded(
      child: Pressable(
        scale: 0.95,
        onTap: f == null || _busy ? null : () => _take(f),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: f == null ? 0.03 : 0.1),
            borderRadius: BorderRadius.circular(PixTokens.radiusM),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: f == null
                    ? scheme.onSurface.withValues(alpha: 0.3)
                    : scheme.primary,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: f == null
                      ? scheme.onSurface.withValues(alpha: 0.35)
                      : null,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.newPattern,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l.newPatternHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              source(Icons.photo_library_rounded, l.fromPhoto, src?.pickImage),
              const SizedBox(width: 8),
              source(
                Icons.layers_rounded,
                l.fromLayer,
                src != null && src.hasLayer() ? src.fromLayer : null,
              ),
              const SizedBox(width: 8),
              source(
                Icons.highlight_alt_rounded,
                l.fromSelection,
                src != null && src.hasSelection() ? src.fromSelection : null,
              ),
            ],
          ),
          const SizedBox(height: 12),
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(PixTokens.radiusM),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.onSurface.withValues(alpha: 0.05),
                ),
                child: _busy
                    ? const Center(child: CircularProgressIndicator())
                    : _bytes == null
                    ? Center(
                        child: Icon(
                          Icons.texture_rounded,
                          size: 48,
                          color: scheme.onSurface.withValues(alpha: 0.25),
                        ),
                      )
                    : _RepeatPreview(
                        bytes: _bytes!,
                        mirror: _mirror,
                        scale: _preview,
                      ),
              ),
            ),
          ),
          if (_bytes != null) ...[
            PixSlider(
              label: l.scale,
              value: _preview,
              min: 0.1,
              max: 1.5,
              defaultValue: 0.35,
              format: (x) => '${(x * 100).round()}%',
              onChanged: (x) => setState(() => _preview = x),
            ),
            SwitchListTile.adaptive(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              secondary: const Icon(Icons.flip_rounded),
              title: Text(l.seamless),
              subtitle: Text(l.seamlessHint),
              value: _mirror,
              onChanged: (v) => setState(() => _mirror = v),
            ),
          ],
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _bytes == null || _busy ? null : _save,
            icon: const Icon(Icons.bookmark_add_rounded),
            label: Text(l.savePattern),
          ),
        ],
      ),
    );
  }
}

/// The picked image repeated (and mirrored) as it will tile.
class _RepeatPreview extends StatelessWidget {
  const _RepeatPreview({
    required this.bytes,
    required this.mirror,
    required this.scale,
  });
  final Uint8List bytes;
  final bool mirror;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final cell = box.maxHeight * scale;
        final image = Image.memory(
          bytes,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        );
        final cols = (box.maxWidth / cell).ceil() + 1;
        final rows = (box.maxHeight / cell).ceil() + 1;
        return Stack(
          children: [
            for (var y = 0; y < rows; y++)
              for (var x = 0; x < cols; x++)
                Positioned(
                  left: x * cell,
                  top: y * cell,
                  width: cell,
                  height: cell,
                  child: Transform.scale(
                    scaleX: mirror && x.isOdd ? -1 : 1,
                    scaleY: mirror && y.isOdd ? -1 : 1,
                    child: image,
                  ),
                ),
          ],
        );
      },
    );
  }
}

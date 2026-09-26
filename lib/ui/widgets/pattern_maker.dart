import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../core/patterns/pattern_library.dart';
import '../../l10n/app_localizations.dart';
import 'checkerboard.dart';
import 'color_picker.dart';
import 'pattern_source.dart';
import 'pix_slider.dart';
import 'pressable.dart';

/// How motifs are laid out in a pattern tile.
enum PatternArrangement { grid, brick, halfDrop }

/// Everything the pattern maker can change.
@immutable
class PatternMakerOptions {
  const PatternMakerOptions({
    this.arrangement = PatternArrangement.grid,
    this.scale = 1,
    this.spacing = 0,
    this.rotation = 0,
    this.mirror = false,
    this.background,
    this.recolor = false,
    this.invert = false,
    this.byBrightness = false,
  });

  final PatternArrangement arrangement;

  /// Size of the motif relative to the source picture.
  final double scale;

  /// Gap around each motif, as a fraction of its size.
  final double spacing;

  /// Degrees the motif turns inside its cell.
  final double rotation;

  /// Mirror the tile 2×2 so its edges always meet.
  final bool mirror;

  /// Colour behind the motifs (null = transparent).
  final Color? background;

  /// Keep only the motif's shape (dark = ink; [invert]: light = ink), to be
  /// drawn later in the fill's own colours.
  final bool recolor;
  final bool invert;

  /// Stencil from brightness (photos) rather than the motif's own shape
  /// (its transparency — layers, cut-outs).
  final bool byBrightness;

  PatternMakerOptions copyWith({
    PatternArrangement? arrangement,
    double? scale,
    double? spacing,
    double? rotation,
    bool? mirror,
    Color? background,
    bool clearBackground = false,
    bool? recolor,
    bool? invert,
    bool? byBrightness,
  }) => PatternMakerOptions(
    arrangement: arrangement ?? this.arrangement,
    scale: scale ?? this.scale,
    spacing: spacing ?? this.spacing,
    rotation: rotation ?? this.rotation,
    mirror: mirror ?? this.mirror,
    background: clearBackground ? null : (background ?? this.background),
    recolor: recolor ?? this.recolor,
    invert: invert ?? this.invert,
    byBrightness: byBrightness ?? this.byBrightness,
  );
}

/// Builds the repeating tile for [src] with [o] (at most [maxSide] px).
ui.Image buildPatternTile(
  ui.Image src,
  PatternMakerOptions o, {
  double maxSide = 1024,
}) {
  var sw = src.width * o.scale, sh = src.height * o.scale;
  final a = o.rotation * math.pi / 180;
  final ca = math.cos(a).abs(), sa = math.sin(a).abs();
  var bw = sw * ca + sh * sa, bh = sw * sa + sh * ca;
  var cw = bw * (1 + o.spacing), ch = bh * (1 + o.spacing);
  var tw = cw, th = ch;
  switch (o.arrangement) {
    case PatternArrangement.grid:
      break;
    case PatternArrangement.brick:
      th = ch * 2;
    case PatternArrangement.halfDrop:
      tw = cw * 2;
  }
  final mirrorF = o.mirror ? 2 : 1;
  // Keep the finished tile within maxSide.
  final fit = math.min(1.0, maxSide / (math.max(tw, th) * mirrorF));
  sw *= fit;
  sh *= fit;
  bw *= fit;
  bh *= fit;
  cw *= fit;
  ch *= fit;
  tw = math.max(1, tw * fit).roundToDouble();
  th = math.max(1, th * fit).roundToDouble();

  final motif = Paint()..filterQuality = FilterQuality.high;
  if (o.recolor) {
    // Alpha from brightness (dark = ink), white ink.
    motif.colorFilter = ColorFilter.matrix(
      !o.byBrightness
          ? (o.invert
                ? const [
                    0, 0, 0, 0, 255, //
                    0, 0, 0, 0, 255, //
                    0, 0, 0, 0, 255, //
                    0, 0, 0, -1, 255, //
                  ]
                : const [
                    0, 0, 0, 0, 255, //
                    0, 0, 0, 0, 255, //
                    0, 0, 0, 0, 255, //
                    0, 0, 0, 1, 0, //
                  ])
          : o.invert
          ? const [
              0, 0, 0, 0, 255, //
              0, 0, 0, 0, 255, //
              0, 0, 0, 0, 255, //
              0.2126, 0.7152, 0.0722, 1, -255, //
            ]
          : const [
              0, 0, 0, 0, 255, //
              0, 0, 0, 0, 255, //
              0, 0, 0, 0, 255, //
              -0.2126, -0.7152, -0.0722, 1, 0, //
            ],
    );
  }
  final srcRect = Rect.fromLTWH(
    0,
    0,
    src.width.toDouble(),
    src.height.toDouble(),
  );
  void motifAt(Canvas c, Offset center) {
    c
      ..save()
      ..translate(center.dx, center.dy)
      ..rotate(a)
      ..drawImageRect(
        src,
        srcRect,
        Rect.fromCenter(center: Offset.zero, width: sw, height: sh),
        motif,
      )
      ..restore();
  }

  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  final tile = Rect.fromLTWH(0, 0, tw, th);
  c.clipRect(tile);
  if (o.background != null && !o.recolor) {
    c.drawRect(tile, Paint()..color = o.background!);
  }
  // Each motif is drawn with its wrapped copies so tiles meet.
  final centers = switch (o.arrangement) {
    PatternArrangement.grid => [Offset(cw / 2, ch / 2)],
    PatternArrangement.brick => [
      Offset(cw / 2, ch / 2),
      Offset(0, ch * 1.5),
      Offset(cw, ch * 1.5),
    ],
    PatternArrangement.halfDrop => [
      Offset(cw / 2, ch / 2),
      Offset(cw * 1.5, 0),
      Offset(cw * 1.5, ch),
    ],
  };
  for (final ctr in centers) {
    for (final dx in [-tw, 0.0, tw]) {
      for (final dy in [-th, 0.0, th]) {
        motifAt(c, ctr + Offset(dx, dy));
      }
    }
  }
  final pic = rec.endRecording();
  var out = pic.toImageSync(tw.toInt(), th.toInt());
  pic.dispose();
  if (o.mirror) {
    final w = tw, h = th;
    final r2 = ui.PictureRecorder();
    final c2 = Canvas(r2);
    for (final (fx, fy) in [
      (false, false),
      (true, false),
      (false, true),
      (true, true),
    ]) {
      c2
        ..save()
        ..translate(fx ? 2 * w : 0, fy ? 2 * h : 0)
        ..scale(fx ? -1 : 1, fy ? -1 : 1)
        ..drawImage(out, Offset.zero, Paint())
        ..restore();
    }
    final p2 = r2.endRecording();
    final m = p2.toImageSync((w * 2).toInt(), (h * 2).toInt());
    p2.dispose();
    out.dispose();
    out = m;
  }
  return out;
}

/// Pattern maker (Photoshop's Define Pattern, with a pattern designer):
/// take a photo, the selected layer or the selection, then lay it out —
/// grid, brick or half-drop, size, spacing, rotation, seamless mirror,
/// background, or a stencil in the fill's own colours — with a live
/// repeating preview, and save it to "My patterns". Returns the pattern
/// and whether it is a stencil.
Future<(MyPattern, bool)?> showPatternMaker(BuildContext context) =>
    Navigator.of(context).push<(MyPattern, bool)>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) =>
            _PatternMakerPage(source: PatternSource.maybeOf(context)),
      ),
    );

class _PatternMakerPage extends StatefulWidget {
  const _PatternMakerPage({required this.source});
  final PatternSource? source;

  @override
  State<_PatternMakerPage> createState() => _PatternMakerPageState();
}

class _PatternMakerPageState extends State<_PatternMakerPage> {
  ui.Image? _src;
  ui.Image? _tile;
  bool _busy = false;
  PatternMakerOptions _o = const PatternMakerOptions();
  double _zoom = 0.5;

  @override
  void dispose() {
    _src?.dispose();
    _tile?.dispose();
    super.dispose();
  }

  Future<void> _take(Future<Uint8List?> Function()? f) async {
    if (f == null) return;
    setState(() => _busy = true);
    try {
      final b = await f();
      if (b == null || !mounted) return;
      final codec = await ui.instantiateImageCodec(b);
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      _src?.dispose();
      _src = frame.image;
      // Big photos start smaller so the pattern repeats visibly.
      final side = math.max(_src!.width, _src!.height);
      _o = _o.copyWith(scale: side > 512 ? 512 / side : 1);
      _rebuild();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _set(PatternMakerOptions o) {
    _o = o;
    _rebuild();
  }

  void _rebuild() {
    final src = _src;
    if (src == null) return;
    final t = buildPatternTile(src, _o);
    setState(() {
      _tile?.dispose();
      _tile = t;
    });
  }

  Future<void> _save() async {
    final t = _tile;
    if (t == null) return;
    setState(() => _busy = true);
    final data = await t.toByteData(format: ui.ImageByteFormat.png);
    if (data == null || !mounted) return;
    final p = await PatternLibrary.instance.add(data.buffer.asUint8List());
    if (mounted) Navigator.pop(context, (p, _o.recolor));
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
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
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
              const SizedBox(height: 4),
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

    Widget label(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
      child: Text(
        t,
        style: theme.textTheme.labelLarge?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    final has = _tile != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.patternMaker),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: FilledButton.icon(
              onPressed: !has || _busy ? null : _save,
              icon: const Icon(Icons.bookmark_add_rounded),
              label: Text(l.savePattern),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Text(
            l.newPatternHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
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
            aspectRatio: 4 / 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(PixTokens.radiusM),
              child: _busy && !has
                  ? const Center(child: CircularProgressIndicator())
                  : !has
                  ? ColoredBox(
                      color: scheme.onSurface.withValues(alpha: 0.05),
                      child: Icon(
                        Icons.texture_rounded,
                        size: 48,
                        color: scheme.onSurface.withValues(alpha: 0.25),
                      ),
                    )
                  : CustomPaint(
                      painter: _TilePreview(
                        _tile!,
                        _zoom,
                        _o.recolor ? scheme.onSurface : null,
                      ),
                    ),
            ),
          ),
          if (has) ...[
            PixSlider(
              label: l.zoom,
              value: _zoom,
              min: 0.1,
              max: 2,
              defaultValue: 0.5,
              format: (x) => '${(x * 100).round()}%',
              onChanged: (x) => setState(() => _zoom = x),
            ),
            label(l.arrangement),
            SegmentedButton<PatternArrangement>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: PatternArrangement.grid,
                  icon: const Icon(Icons.grid_view_rounded, size: 18),
                  label: Text(l.arrGrid),
                ),
                ButtonSegment(
                  value: PatternArrangement.brick,
                  icon: const Icon(Icons.view_week_rounded, size: 18),
                  label: Text(l.arrBrick),
                ),
                ButtonSegment(
                  value: PatternArrangement.halfDrop,
                  icon: const Icon(Icons.view_column_rounded, size: 18),
                  label: Text(l.arrHalfDrop),
                ),
              ],
              selected: {_o.arrangement},
              onSelectionChanged: (v) =>
                  _set(_o.copyWith(arrangement: v.first)),
            ),
            PixSlider(
              label: l.size,
              value: _o.scale.clamp(0.05, 2),
              min: 0.05,
              max: 2,
              defaultValue: 1,
              format: (x) => '${(x * 100).round()}%',
              onChanged: (x) => setState(() => _o = _o.copyWith(scale: x)),
              onChangeEnd: (x) => _set(_o.copyWith(scale: x)),
            ),
            PixSlider(
              label: l.spacing,
              value: _o.spacing,
              min: 0,
              max: 2,
              defaultValue: 0,
              format: (x) => '${(x * 100).round()}%',
              onChanged: (x) => _set(_o.copyWith(spacing: x)),
            ),
            PixSlider(
              label: l.tileRotation,
              value: _o.rotation,
              min: -180,
              max: 180,
              defaultValue: 0,
              format: (x) => '${x.round()}°',
              onChanged: (x) => _set(_o.copyWith(rotation: x.roundToDouble())),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.flip_rounded),
              title: Text(l.mirrorTile),
              value: _o.mirror,
              onChanged: (v) => _set(_o.copyWith(mirror: v)),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.format_color_fill_rounded),
              title: Text(l.recolor),
              subtitle: Text(l.recolorHint),
              value: _o.recolor,
              onChanged: (v) => _set(_o.copyWith(recolor: v)),
            ),
            if (_o.recolor)
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: false,
                    icon: const Icon(Icons.category_rounded, size: 18),
                    label: Text(l.shape),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: const Icon(Icons.brightness_6_rounded, size: 18),
                    label: Text(l.brightness),
                  ),
                ],
                selected: {_o.byBrightness},
                onSelectionChanged: (v) =>
                    _set(_o.copyWith(byBrightness: v.first)),
              ),
            if (_o.recolor)
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.invert_colors_rounded),
                title: Text(l.invertColors),
                value: _o.invert,
                onChanged: (v) => _set(_o.copyWith(invert: v)),
              )
            else ...[
              label(l.patternBackground),
              ColorStrip(
                value: _o.background ?? const Color(0x00000000),
                allowTransparent: true,
                onChanged: (c, {required live}) => _set(
                  c == null || c.a == 0
                      ? _o.copyWith(clearBackground: true)
                      : _o.copyWith(background: c),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// The tile repeated over the preview (stencils shown in [ink]).
class _TilePreview extends CustomPainter {
  _TilePreview(this.tile, this.zoom, this.ink);
  final ui.Image tile;
  final double zoom;
  final Color? ink;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    paintCheckerboard(
      canvas,
      r,
      const Color(0xFFFFFFFF),
      const Color(0xFFE5E7EB),
      cell: 10,
    );
    final z = zoom;
    canvas.drawRect(
      r,
      Paint()
        ..colorFilter = ink == null
            ? null
            : ColorFilter.mode(ink!, BlendMode.srcIn)
        ..shader = ImageShader(
          tile,
          TileMode.repeated,
          TileMode.repeated,
          Float64List.fromList([
            z, 0, 0, 0, //
            0, z, 0, 0, //
            0, 0, 1, 0, //
            0, 0, 0, 1, //
          ]),
          filterQuality: FilterQuality.medium,
        ),
    );
  }

  @override
  bool shouldRepaint(_TilePreview old) =>
      old.tile != tile || old.zoom != zoom || old.ink != ink;
}

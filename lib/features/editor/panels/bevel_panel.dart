import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/patterns/pattern_library.dart';
import '../../../document/effects/effect_registry.dart';
import '../../../document/model/effect.dart';
import '../../../document/model/fill.dart';
import '../../../document/model/layer.dart';
import '../../../document/model/patterns.dart';
import '../../../document/render/bevel_engine.dart';
import '../../../editor/editor_controller.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui/widgets/color_picker.dart';
import '../../../ui/widgets/pattern_source.dart';
import '../../../ui/widgets/pix_slider.dart';
import 'panel_common.dart';

enum _Section { structure, shading, contour, texture }

/// Photoshop's Bevel & Emboss with every option: Structure (style,
/// technique, depth, direction, size, soften), Shading (light angle and
/// altitude on a globe, gloss contour, highlight and shadow modes, colours
/// and opacities), Contour (profile and range) and Texture (pattern,
/// scale, depth, invert).
class BevelPanel extends StatefulWidget {
  const BevelPanel({super.key, required this.editor, required this.layer});
  final EditorController editor;
  final Layer layer;

  @override
  State<BevelPanel> createState() => _BevelPanelState();
}

class _BevelPanelState extends State<BevelPanel> {
  _Section _section = _Section.structure;

  EditorController get editor => widget.editor;
  Layer get layer => widget.layer;

  LayerEffect? get _fx => editor.effectOf(layer.id, 'bevel');

  /// Sets params, converting an older bevel to the current settings first.
  void _set(Map<String, Object> params, {bool live = false}) {
    final fx = _fx;
    if (fx == null) return;
    final base = fx.number('v', 0) < 2
        ? BevelParams.of(fx).toParams()
        : fx.params;
    editor.updateProps(
      layer.id,
      (p) => p.copyWith(
        effects: [
          for (final e in p.effects)
            e.id == fx.id ? e.copyWith(params: {...base, ...params}) : e,
        ],
      ),
      label: 'bevel',
      live: live,
    );
  }

  void _toggle(bool on) {
    if (on) {
      editor.updateProps(
        layer.id,
        (p) => p.copyWith(
          effects: [
            for (final e in p.effects)
              if (e.type != 'bevel') e,
            EffectRegistry.instance['bevel']!.create(),
          ],
        ),
        label: 'effect',
      );
    } else {
      editor.removeEffectType(layer.id, 'bevel');
    }
  }

  Widget _slider(
    String key,
    String label,
    double value, {
    required double min,
    required double max,
    required double def,
    String Function(double)? format,
  }) => PixSlider(
    label: label,
    value: value.clamp(min, max).toDouble(),
    min: min,
    max: max,
    defaultValue: def,
    format: format ?? (v) => '${v.round()}',
    onChanged: (v) => _set({key: v}, live: true),
    onChangeEnd: (_) => editor.commit('bevel'),
  );

  Widget _segments<T>(
    List<(T, String)> items,
    T value,
    ValueChanged<T> onChanged,
  ) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
    child: SizedBox(
      width: double.infinity,
      child: SegmentedButton<T>(
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        segments: [
          for (final (v, label) in items)
            ButtonSegment(value: v, label: Text(label, maxLines: 1)),
        ],
        selected: {value},
        onSelectionChanged: (s) => onChanged(s.first),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final fx = _fx;
    final on = fx != null && fx.enabled;
    final p = fx == null ? const BevelParams() : BevelParams.of(fx);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile.adaptive(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          title: Text(
            l.bevelEmboss,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          value: on,
          onChanged: _toggle,
        ),
        if (on) ...[
          _segments<_Section>(
            [
              (_Section.structure, l.bevelStructure),
              (_Section.shading, l.bevelShading),
              (_Section.contour, l.bevelContour),
              (_Section.texture, l.bevelTexture),
            ],
            _section,
            (s) => setState(() => _section = s),
          ),
          switch (_section) {
            _Section.structure => _structure(l, p),
            _Section.shading => _shading(l, p),
            _Section.contour => _contour(l, p),
            _Section.texture => _texture(context, l, p),
          },
        ],
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _structure(AppLocalizations l, BevelParams p) {
    final styles = [
      (BevelKind.inner, l.innerBevel),
      (BevelKind.outer, l.outerBevel),
      (BevelKind.emboss, l.emboss),
      (BevelKind.pillow, l.pillowEmboss),
      (BevelKind.strokeEmboss, l.strokeEmboss),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final (k, label) in styles)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: p.kind == k,
                    onSelected: (_) => _set({'style': k.index}),
                  ),
                ),
            ],
          ),
        ),
        if (p.kind == BevelKind.strokeEmboss && layer.props.stroke == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text(
              l.strokeEmbossHint,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.error),
            ),
          ),
        _segments<BevelTechnique>(
          [
            (BevelTechnique.smooth, l.techSmooth),
            (BevelTechnique.chiselHard, l.techChiselHard),
            (BevelTechnique.chiselSoft, l.techChiselSoft),
          ],
          p.technique,
          (t) => _set({'technique': t.index}),
        ),
        _slider(
          'depth',
          l.depth,
          p.depth * 100,
          min: 1,
          max: 1000,
          def: 100,
          format: (v) => '${v.round()}%',
        ),
        _segments<bool>(
          [(true, l.dirUp), (false, l.dirDown)],
          p.up,
          (up) => _set({'direction': up ? 0 : 1}),
        ),
        _slider('size', l.size, p.size, min: 0, max: 250, def: 5),
        _slider('soften', l.soften, p.soften, min: 0, max: 16, def: 0),
      ],
    );
  }

  Widget _shading(AppLocalizations l, BevelParams p) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Row(
            children: [
              _LightGlobe(
                angle: p.angle,
                altitude: p.altitude,
                onChanged: (a, alt, {required live}) =>
                    _set({'angle': a, 'altitude': alt}, live: live),
                onEnd: () => editor.commit('bevel'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  children: [
                    _slider(
                      'angle',
                      l.angle,
                      p.angle,
                      min: -180,
                      max: 180,
                      def: 120,
                      format: (v) => '${v.round()}°',
                    ),
                    _slider(
                      'altitude',
                      l.altitude,
                      p.altitude,
                      min: 0,
                      max: 90,
                      def: 30,
                      format: (v) => '${v.round()}°',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        PanelLabel(l.glossContour),
        _ContourRow(value: p.gloss, onChanged: (c) => _set({'gloss': c.index})),
        SwitchListTile.adaptive(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          title: Text(l.antiAliased),
          value: p.antiAlias,
          onChanged: (v) => _set({'antiAlias': v ? 1 : 0}),
        ),
        PanelLabel(l.highlight),
        BlendModeRow(
          label: l.blendMode,
          value: p.highlightMode,
          onChanged: (m) => _set({'highlightMode': m.index}),
        ),
        ColorStrip(
          value: p.highlight,
          onChanged: (c, {required live}) {
            if (c != null) _set({'highlight': c.toARGB32()}, live: live);
          },
        ),
        _slider(
          'highlightOpacity',
          l.opacity,
          p.highlightOpacity,
          min: 0,
          max: 1,
          def: 0.75,
          format: (v) => '${(v * 100).round()}%',
        ),
        PanelLabel(l.shade),
        BlendModeRow(
          label: l.blendMode,
          value: p.shadowMode,
          onChanged: (m) => _set({'shadowMode': m.index}),
        ),
        ColorStrip(
          value: p.shadow,
          onChanged: (c, {required live}) {
            if (c != null) _set({'shadowColor': c.toARGB32()}, live: live);
          },
        ),
        _slider(
          'shadowOpacity',
          l.opacity,
          p.shadowOpacity,
          min: 0,
          max: 1,
          def: 0.75,
          format: (v) => '${(v * 100).round()}%',
        ),
      ],
    );
  }

  Widget _contour(AppLocalizations l, BevelParams p) {
    final on = p.contour != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile.adaptive(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          title: Text(l.bevelContour),
          subtitle: Text(l.bevelContourHint),
          value: on,
          onChanged: (v) => _set({'contourOn': v ? 1 : 0}),
        ),
        if (on) ...[
          _ContourRow(
            value: p.contour!,
            onChanged: (c) => _set({'contour': c.index}),
          ),
          _slider(
            'contourRange',
            l.contourRange,
            p.contourRange * 100,
            min: 1,
            max: 100,
            def: 50,
            format: (v) => '${v.round()}%',
          ),
        ],
      ],
    );
  }

  Widget _texture(BuildContext context, AppLocalizations l, BevelParams p) {
    final on = p.texture != null;
    final scheme = Theme.of(context).colorScheme;
    Widget tile(String id, Widget child) => GestureDetector(
      onTap: () => _set({'texture': id, 'textureOn': 1}),
      child: Container(
        width: 48,
        height: 48,
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: p.texture == id ? scheme.primary : scheme.outlineVariant,
            width: p.texture == id ? 2.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile.adaptive(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          title: Text(l.bevelTexture),
          subtitle: Text(l.bevelTextureHint),
          value: on,
          onChanged: (v) => _set({'textureOn': v ? 1 : 0}),
        ),
        if (on) ...[
          SizedBox(
            height: 58,
            child: ListenableBuilder(
              listenable: PatternLibrary.instance,
              builder: (context, _) => ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final m in PatternLibrary.instance.items)
                    GestureDetector(
                      onTap: () async {
                        final src = PatternSource.maybeOf(context);
                        if (src != null) {
                          await PatternLibrary.ensureIn(src.assets, m);
                        }
                        _set({'texture': m.patternId, 'textureOn': 1});
                      },
                      child: Container(
                        width: 48,
                        height: 48,
                        margin: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: p.texture == m.patternId
                                ? scheme.primary
                                : scheme.outlineVariant,
                            width: p.texture == m.patternId ? 2.5 : 1,
                          ),
                          image: DecorationImage(
                            image: MemoryImage(m.bytes),
                            repeat: ImageRepeat.repeat,
                            scale: 4,
                          ),
                        ),
                      ),
                    ),
                  for (final id in Patterns.builtins)
                    tile(
                      id,
                      CustomPaint(
                        painter: _TextureSwatch(
                          PixFill.pattern(
                            id,
                            fg: const Color(0xFF374151),
                            bg: const Color(0xFFF3F4F6),
                            scale: 0.5,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          _slider(
            'textureScale',
            l.scale,
            p.textureScale * 100,
            min: 1,
            max: 1000,
            def: 100,
            format: (v) => '${v.round()}%',
          ),
          _slider(
            'textureDepth',
            l.depth,
            p.textureDepth * 100,
            min: -1000,
            max: 1000,
            def: 100,
            format: (v) => '${v.round()}%',
          ),
          SwitchListTile.adaptive(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            title: Text(l.invert),
            value: p.textureInvert,
            onChanged: (v) => _set({'textureInvert': v ? 1 : 0}),
          ),
        ],
      ],
    );
  }
}

class _TextureSwatch extends CustomPainter {
  _TextureSwatch(this.fill);
  final PixFill fill;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRect(r, fill.applyTo(Paint(), r));
  }

  @override
  bool shouldRepaint(_TextureSwatch old) => old.fill != fill;
}

/// Contour presets as small curve thumbnails.
class _ContourRow extends StatelessWidget {
  const _ContourRow({required this.value, required this.onChanged});
  final ContourPreset value;
  final ValueChanged<ContourPreset> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 58,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final c in ContourPreset.values)
            GestureDetector(
              onTap: () => onChanged(c),
              child: Container(
                width: 48,
                height: 48,
                margin: const EdgeInsets.all(4),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: scheme.onSurface.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: c == value ? scheme.primary : Colors.transparent,
                    width: 2.5,
                  ),
                ),
                child: CustomPaint(painter: _CurvePainter(c, scheme.onSurface)),
              ),
            ),
        ],
      ),
    );
  }
}

class _CurvePainter extends CustomPainter {
  _CurvePainter(this.c, this.color);
  final ContourPreset c;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    for (var i = 0; i <= 40; i++) {
      final t = i / 40;
      final p = Offset(t * size.width, (1 - c.apply(t)) * size.height);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas
      ..drawPath(fill, Paint()..color = color.withValues(alpha: 0.12))
      ..drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..color = color,
      );
  }

  @override
  bool shouldRepaint(_CurvePainter old) => old.c != c || old.color != color;
}

/// Photoshop's lighting globe: the dot's direction from the centre is the
/// light angle, its distance the altitude (centre = 90°, rim = 0°).
class _LightGlobe extends StatelessWidget {
  const _LightGlobe({
    required this.angle,
    required this.altitude,
    required this.onChanged,
    required this.onEnd,
  });
  final double angle;
  final double altitude;
  final void Function(double angle, double altitude, {required bool live})
  onChanged;
  final VoidCallback onEnd;

  static const _size = 96.0;

  void _update(Offset local, {required bool live}) {
    const c = Offset(_size / 2, _size / 2);
    final d = local - c;
    final r = (d.distance / (_size / 2)).clamp(0.0, 1.0);
    var a = math.atan2(-d.dy, d.dx) * 180 / math.pi;
    a = a.roundToDouble();
    final alt = ((1 - r) * 90).roundToDouble();
    onChanged(a, alt, live: live);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onPanStart: (d) => _update(d.localPosition, live: true),
      onPanUpdate: (d) => _update(d.localPosition, live: true),
      onPanEnd: (_) => onEnd(),
      onTapUp: (d) => _update(d.localPosition, live: false),
      child: CustomPaint(
        size: const Size(_size, _size),
        painter: _GlobePainter(angle, altitude, scheme),
      ),
    );
  }
}

class _GlobePainter extends CustomPainter {
  _GlobePainter(this.angle, this.altitude, this.scheme);
  final double angle;
  final double altitude;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 2;
    final th = angle * math.pi / 180;
    final dist = r * (1 - altitude / 90);
    final dot = c + Offset(math.cos(th), -math.sin(th)) * dist;
    canvas
      ..drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            center: Alignment(
              math.cos(th) * 0.5 * (1 - altitude / 90),
              -math.sin(th) * 0.5 * (1 - altitude / 90),
            ),
            colors: [Colors.white, scheme.primary.withValues(alpha: 0.35)],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      )
      ..drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = scheme.outline,
      );
    for (final f in [1 / 3, 2 / 3]) {
      canvas.drawCircle(
        c,
        r * f,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = scheme.outlineVariant,
      );
    }
    canvas
      ..drawLine(
        c,
        dot,
        Paint()
          ..color = scheme.primary
          ..strokeWidth = 1.5,
      )
      ..drawCircle(dot, 7, Paint()..color = Colors.white)
      ..drawCircle(
        dot,
        7,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = scheme.primary,
      );
  }

  @override
  bool shouldRepaint(_GlobePainter old) =>
      old.angle != angle || old.altitude != altitude;
}

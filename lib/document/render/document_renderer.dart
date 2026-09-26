import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../assets/asset_store.dart';
import '../effects/effect_registry.dart';
import '../model/blend.dart';
import '../model/document.dart';
import '../model/effect.dart';
import '../model/layer.dart';
import '../model/layer_stroke.dart';
import 'bevel_engine.dart';
import 'mask_jobs.dart';
import '../model/patterns.dart';
import '../model/layer_transform.dart';
import '../model/mask.dart';
import 'brush_paint.dart';
import 'color_matrix.dart';
import 'filter_engine.dart';
import 'glow_engine.dart';
import 'extrude_engine.dart';
import 'layer_cache.dart';
import 'shape_paths.dart';
import 'text_layout.dart';
import 'vector_paths.dart';

/// Size of a layer's local box (before its transform is applied).
Size layerLocalSize(Layer layer) => layerLocalRect(layer).size;

/// The layer's box in its local space. Leaf layers are centred on their
/// origin; a group's box is the union of its children (its transform is
/// always identity, so local space == document space).
Rect layerLocalRect(Layer layer) {
  Rect centred(double w, double h) =>
      Rect.fromCenter(center: Offset.zero, width: w, height: h);
  return switch (layer) {
    RasterLayer l => centred(l.width, l.height),
    TextLayer l => () {
      final s = TextLayoutCache.instance.sizeOf(l);
      return centred(s.width, s.height);
    }(),
    ShapeLayer l => centred(l.width, l.height),
    IconLayer l => centred(l.width, l.height),
    PathLayer l => pathLayerRect(l),
    DrawingLayer l => drawingRect(l),
    GroupLayer g => unionBounds(g.children),
  };
}

/// Asset ids used by [layer] and, for groups, its descendants.
Set<String> assetsOf(Layer layer) => {
  ...layer.props.maskAssets,
  ...layer.fillAssets,
  ...switch (layer) {
    RasterLayer l => {l.assetId, ?l.sourceAssetId},
    GroupLayer g => {for (final c in g.children) ...assetsOf(c)},
    _ => const <String>{},
  },
};

/// Looks up a decoded asset image (null while it is still decoding).
typedef MaskImageLookup = ui.Image? Function(String assetId);

/// Union of the document-space bounds of [layers] (Rect.zero if empty).
Rect unionBounds(Iterable<Layer> layers) {
  Rect? r;
  for (final l in layers) {
    if (l is GroupLayer && l.children.isEmpty) continue;
    final b = layerDocumentBounds(l);
    r = r == null ? b : r.expandToInclude(b);
  }
  return r ?? Rect.zero;
}

/// Four corners of the layer's box in document space (TL, TR, BR, BL).
List<Offset> layerCorners(Layer layer) {
  final r = layerLocalRect(layer);
  final t = layer.props.transform;
  return [
    t.toDocument(r.topLeft),
    t.toDocument(r.topRight),
    t.toDocument(r.bottomRight),
    t.toDocument(r.bottomLeft),
  ];
}

/// Axis-aligned bounds of the transformed layer in document space.
Rect layerDocumentBounds(Layer layer) {
  final c = layerCorners(layer);
  var l = c[0].dx, t = c[0].dy, r = l, b = t;
  for (final p in c.skip(1)) {
    l = math.min(l, p.dx);
    r = math.max(r, p.dx);
    t = math.min(t, p.dy);
    b = math.max(b, p.dy);
  }
  return Rect.fromLTRB(l, t, r, b);
}

bool hitTestLayer(Layer layer, Offset docPoint, {double tolerance = 0}) {
  if (layer is GroupLayer) {
    return layer.children.any(
      (c) => c.props.visible && hitTestLayer(c, docPoint, tolerance: tolerance),
    );
  }
  final local = layer.props.transform.toLocal(docPoint);
  final t = layer.props.transform;
  final tol =
      tolerance / math.max(0.0001, math.min(t.scaleX.abs(), t.scaleY.abs()));
  return layerLocalRect(layer).inflate(tol).contains(local);
}

/// Paints documents. The one renderer used for the on-screen canvas,
/// thumbnails and export, so what you see is exactly what you get.
class DocumentRenderer {
  const DocumentRenderer(
    this.assets, {
    this.effects,
    this.cache,
    this.pixelScale = 1,
  });

  /// When set, expensive layers are drawn from cached bitmaps (on-screen
  /// canvas). Export and thumbnails render without it, at full quality.
  final LayerRasterCache? cache;

  /// Output pixels per document pixel (zoom × device pixel ratio on screen,
  /// the export scale otherwise). Sets the resolution of cached bitmaps
  /// and of pre-rendered effect silhouettes.
  final double pixelScale;

  final AssetStore assets;
  final EffectRegistry? effects;

  EffectRegistry get _fx => effects ?? EffectRegistry.instance;

  /// Paints [doc] in document coordinates (0,0)-(width,height).
  void paint(Canvas canvas, PixDocument doc, {Set<String> hidden = const {}}) {
    final bounds = doc.bounds;
    canvas
      ..save()
      ..clipRect(bounds)
      // Isolate the document so blend modes never mix with the UI behind.
      ..saveLayer(bounds, Paint());
    final bg = doc.background;
    if (bg != null) {
      canvas.drawRect(bounds, bg.applyTo(Paint(), bounds));
    }
    paintLayers(canvas, doc.layers, hidden: hidden);
    canvas
      ..restore()
      ..restore();
  }

  /// Paints a bottom→top list of sibling layers, resolving clipping masks:
  /// consecutive layers with `clip` are clipped to the layer below them.
  void paintLayers(
    Canvas canvas,
    List<Layer> list, {
    Set<String> hidden = const {},
  }) {
    bool shown(Layer l) => l.props.visible && !hidden.contains(l.id);
    var i = 0;
    while (i < list.length) {
      final base = list[i];
      var j = i + 1;
      final clipped = <Layer>[];
      while (j < list.length && list[j].props.clip) {
        if (shown(list[j])) clipped.add(list[j]);
        j++;
      }
      // Like Photoshop, hiding the base hides everything clipped to it.
      if (shown(base)) {
        if (clipped.isEmpty) {
          paintLayer(canvas, base, hidden: hidden);
        } else {
          canvas.saveLayer(
            null,
            Paint()..blendMode = base.props.blendMode.engine,
          );
          paintLayer(canvas, base, hidden: hidden, asClipBase: true);
          canvas.saveLayer(null, Paint()..blendMode = BlendMode.srcATop);
          for (final c in clipped) {
            paintLayer(canvas, c, hidden: hidden);
          }
          canvas
            ..restore()
            ..restore();
        }
      }
      i = j;
    }
  }

  /// Paints one layer (and, for groups, its subtree). With [asClipBase] the
  /// layer's blend mode is skipped because the enclosing clip group applies
  /// it to the combined result.
  ///
  /// Like Photoshop, each layer style is composited onto the layers beneath
  /// with its own blend mode (a Multiply shadow darkens what is under it),
  /// in order: shadows, outer glows, 3D, the layer itself (with its inner
  /// effects, in the layer's blend mode), stroke, bevel.
  void paintLayer(
    Canvas canvas,
    Layer layer, {
    Set<String> hidden = const {},
    bool asClipBase = false,
  }) {
    final props = layer.props;
    if (props.opacity <= 0) return;
    final blend = asClipBase ? BlendMode.srcOver : props.blendMode.engine;

    if (cache != null && layer is! GroupLayer && _isExpensive(layer)) {
      final hit = _cachedBitmap(layer, blend);
      if (hit != null) {
        final t = props.transform;
        final dst = hit.rect.shift(Offset(t.x, t.y));
        for (final part in hit.parts) {
          final img = part.image;
          canvas.drawImageRect(
            img,
            Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
            dst,
            Paint()
              ..color = Color.fromRGBO(
                0,
                0,
                0,
                (props.opacity * part.alpha).clamp(0.0, 1.0),
              )
              ..blendMode = part.mode
              ..filterQuality = FilterQuality.medium
              ..isAntiAlias = true,
          );
        }
        return;
      }
    }

    final plan = _plan(layer, hidden);
    canvas.save();
    props.transform.applyTo(canvas);
    plan.paint(canvas, blend: blend, opacity: props.opacity);
    canvas.restore();
    plan.dispose();
  }

  /// Everything [layer] draws, as parts in layer space (see [paintLayer]).
  /// Dispose the plan once its parts are painted.
  _LayerPlan _plan(Layer layer, Set<String> hidden) {
    final props = layer.props;
    List<double>? matrix;
    var blur = 0.0;
    final shadows = <ShadowSpec>[];
    final inners = <ShadowSpec>[];
    final bevels = <BevelParams>[];
    final extrudes = <(LayerEffect, ExtrudeSpec)>[];
    final satins = <SatinSpec>[];
    final glows = <(LayerEffect, GlowParams)>[];
    // Shadows with Spread / Choke: masks from the glow engine.
    final spreadShadows = <(LayerEffect, ShadowSpec)>[];
    final local = layerLocalRect(layer);
    for (final e in props.effects) {
      if (!e.enabled) continue;
      if (e.type == 'glow' || e.type == 'innerGlow') {
        final g = GlowParams.of(e);
        if (g.size > 0 && g.opacity > 0) glows.add((e, g));
        continue;
      }
      if (e.type == 'bevel') {
        bevels.add(BevelParams.of(e));
        continue;
      }
      if (e.type == 'satin') {
        satins.add(SatinSpec.of(e));
        continue;
      }
      final def = _fx[e.type];
      if (def == null || def.filter != null) continue;
      if ((e.type == 'shadow' || e.type == 'innerShadow') &&
          e.number('spread', 0) > 0) {
        final spec = (def.shadow ?? def.inner)?.call(e);
        if (spec != null) spreadShadows.add((e, spec));
        continue;
      }
      final m = def.colorMatrix?.call(e);
      if (m != null) {
        matrix = matrix == null ? m : ColorMatrix.concat(matrix, m);
      }
      blur += def.blurSigma?.call(e) ?? 0;
      if (def.shadow?.call(e) case final s?) shadows.add(s);
      if (def.inner?.call(e) case final s?) inners.add(s);
      if (def.extrude?.call(e) case final x?) extrudes.add((e, x));
    }
    if (matrix != null && ColorMatrix.isIdentity(matrix)) matrix = null;

    final isGroup = layer is GroupLayer;
    final t = props.transform;
    final ms = _minScale(t);
    final src = _ShapeSource.of(this, layer, hidden);
    var margin = blur * 3 + src.reach;
    for (final s in shadows) {
      margin = math.max(margin, s.blur * 3 + s.offset.distance / ms);
    }
    for (final b in bevels) {
      margin = math.max(margin, b.reach + 2);
    }
    for (final (_, x) in extrudes) {
      margin = math.max(margin, _extrudeReach(x, local, ms) + 4);
    }
    for (final s in satins) {
      margin = math.max(margin, s.size * 1.5 + s.distance / ms);
    }
    for (final (_, g) in glows) {
      margin = math.max(margin, g.reach + 2);
    }
    for (final (_, sp) in spreadShadows) {
      margin = math.max(margin, sp.blur * 1.5 + sp.offset.distance / ms + 4);
    }
    final stroke = !isGroup && (props.stroke?.visible ?? false)
        ? props.stroke
        : null;
    // Outer effects start from the stroke's edge.
    if (stroke != null) margin += stroke.outside + 2;
    // Children of a group may carry their own effects, so a group's layer
    // is left unbounded rather than risk clipping them.
    final Rect? layerBounds = isGroup ? null : local.inflate(margin + 2);

    // Photoshop's "Layer Mask Hides Effects": styles come from the whole
    // layer and the mask is applied to the finished result.
    final maskAfter = props.maskHidesEffects && props.hasMask;

    // The layer's shape (filtered content with its mask) — what effects
    // derive from.
    void shape(Canvas c) => maskAfter
        ? src.draw(c)
        : _paintMasked(c, layer, hidden, layerBounds, content: src.draw);

    // Effects redraw the shape many times; stamp one pre-rendered bitmap
    // of it instead (the visible content itself stays vector).
    final passes =
        shadows.length +
        inners.length +
        satins.length * 4 +
        glows.length * 2 +
        spreadShadows.length * 2 +
        bevels.length * 4 +
        extrudes.length * 2 +
        (stroke == null ? 0 : 8);
    final stamp = !isGroup && passes >= 2
        ? _Stamp.of(layer, shape, pixelScale, extra: src.reach)
        : null;
    void effectShape(Canvas c) => stamp == null ? shape(c) : stamp.draw(c);

    // The stroke band, coloured, rendered once: exact vector outlines for
    // shapes, icons and flat text; otherwise grown from the layer's pixels.
    final band = stroke == null || stamp == null
        ? null
        : ((src.reach > 0 ? null : _vectorBand(layer, stroke, stamp, local)) ??
              stamp.strokeBand(stroke, local));

    // Outer effects (shadows, glows) follow the layer and its stroke.
    void outerShape(Canvas c) {
      effectShape(c);
      band?.draw(c);
    }

    // Styles computed in the background (bevels, precise glows…).
    final jobs =
        bevels.isEmpty &&
            spreadShadows.isEmpty &&
            glows.every((g) => g.$2.fast) &&
            extrudes.every((x) => !x.$2.lit)
        ? const <_StyleJob>[]
        : _styleJobs(layer, pixelScale, shape, band);
    final area = layerBounds ?? local.inflate(4000);
    MaskResult? jobFor(LayerEffect e) {
      for (final j in jobs) {
        if (j.effectId == e.id) return j.result;
      }
      return null;
    }

    // Effect offsets are in document space; undo rotation/scale so they
    // always fall the same way.
    Offset toLocal(Offset o) {
      final c = math.cos(-t.rotation), sn = math.sin(-t.rotation);
      return Offset(
        (o.dx * c - o.dy * sn) / (t.scaleX == 0 ? 1 : t.scaleX),
        (o.dx * sn + o.dy * c) / (t.scaleY == 0 ? 1 : t.scaleY),
      );
    }

    final parts = <_Part>[];
    void part(BlendMode mode, void Function(Canvas c) draw, [double a = 1]) =>
        parts.add(_Part(mode, a, draw));

    // Drop shadows.
    for (final s in shadows) {
      final lo = toLocal(s.offset);
      part(s.blend.engine, (canvas) {
        canvas.saveLayer(
          layerBounds,
          Paint()
            ..colorFilter = ColorFilter.mode(s.color, BlendMode.srcIn)
            ..imageFilter = s.blur > 0
                ? ui.ImageFilter.blur(
                    sigmaX: s.blur / 2,
                    sigmaY: s.blur / 2,
                    tileMode: TileMode.decal,
                  )
                : null,
        );
        canvas.translate(lo.dx, lo.dy);
        outerShape(canvas);
        canvas.restore();
      });
    }

    void spreadShadow(
      Canvas canvas,
      LayerEffect e,
      ShadowSpec sp, {
      required bool inner,
    }) {
      final r = jobFor(e);
      if (r == null) return;
      final m = r.masks[0];
      final o = toLocal(sp.offset);
      final paint = Paint()
        ..filterQuality = FilterQuality.medium
        ..colorFilter = ColorFilter.mode(sp.color, BlendMode.srcIn);
      final from = Rect.fromLTWH(0, 0, m.width.toDouble(), m.height.toDouble());
      if (!inner) {
        canvas.drawImageRect(m, from, r.rect.shift(o), paint);
        return;
      }
      canvas
        ..saveLayer(area, Paint()..blendMode = sp.blend.engine)
        ..drawImageRect(m, from, r.rect.shift(o), paint)
        ..saveLayer(area, Paint()..blendMode = BlendMode.dstIn);
      shape(canvas);
      canvas
        ..restore()
        ..restore();
    }

    for (final (e, sp) in spreadShadows) {
      if (e.type == 'shadow') {
        part(sp.blend.engine, (c) => spreadShadow(c, e, sp, inner: false));
      }
    }

    void glow(Canvas canvas, LayerEffect e, GlowParams g, {BlendMode? mode}) {
      if (g.fast) {
        _paintGlow(
          canvas,
          g,
          area,
          g.inner ? effectShape : outerShape,
          mode: mode,
        );
        return;
      }
      final r = jobFor(e);
      if (r != null) _paintGlowMask(canvas, r, g, mode: mode);
    }

    // Outer glows above drop shadows (Photoshop's order).
    for (final (e, g) in glows) {
      if (!g.inner) {
        part(g.blend.engine, (c) => glow(c, e, g, mode: BlendMode.srcOver));
      }
    }

    // 3D extrusions. Rotated in 3D, a solid facing away from the viewer
    // shows its back: then the extrusion covers the layer instead.
    final extrudeStamp = extrudes.isEmpty
        ? null
        : (stamp ?? _Stamp.of(layer, shape, pixelScale, extra: src.reach));
    final solid = t.hasTilt;
    final facing = !solid || t.axes.$3[2] >= 0;
    final lateParts = <_Part>[];
    for (final (e, x) in extrudes) {
      final p = _Part(
        BlendMode.srcOver,
        1,
        (c) => _paintExtrude(
          c,
          x,
          layer,
          layerBounds,
          toLocal,
          extrudeStamp!,
          normals: jobFor(e),
          content: shape,
        ),
      );
      facing ? parts.add(p) : lateParts.add(p);
    }

    final hasInner =
        inners.isNotEmpty ||
        spreadShadows.any((x) => x.$1.type == 'innerShadow') ||
        satins.isNotEmpty ||
        glows.any((g) => g.$2.inner);
    // Fill opacity fades the layer's own pixels only. With "Blend interior
    // effects as group" the inner effects fade with them; otherwise they
    // keep full strength, clipped to the unfaded shape (Photoshop).
    final fill = props.fillOpacity.clamp(0.0, 1.0);
    final faded = fill < 1;
    final interiorFades = faded && props.blendInterior;

    void content(Canvas canvas) {
      if (matrix != null || blur > 0) {
        canvas.saveLayer(
          layerBounds,
          Paint()
            ..colorFilter = matrix == null ? null : ColorFilter.matrix(matrix)
            ..imageFilter = blur > 0
                ? ui.ImageFilter.blur(
                    sigmaX: blur,
                    sigmaY: blur,
                    tileMode: TileMode.decal,
                  )
                : null,
        );
        shape(canvas);
        canvas.restore();
      } else {
        shape(canvas);
      }
    }

    void innerEffects(Canvas canvas, {required bool clipToShape}) {
      // Satin sits beneath inner glows and shadows (Photoshop's order).
      for (final s in satins) {
        _paintSatin(canvas, s, area, toLocal(s.offset), effectShape);
      }
      // Then inner glows, then inner shadows.
      for (final (e, g) in glows) {
        if (g.inner) glow(canvas, e, g);
      }
      for (final s in inners) {
        _paintInner(
          canvas,
          toLocal(s.offset),
          s.blur,
          s.color,
          area,
          shape,
          clipToShape: clipToShape,
          mode: s.blend.engine,
        );
      }
      for (final (e, sp) in spreadShadows) {
        if (e.type == 'innerShadow') {
          spreadShadow(canvas, e, sp, inner: true);
        }
      }
    }

    // The layer itself with its interior effects, in the layer's mode.
    final fadePaint = Paint()..color = Color.fromRGBO(0, 0, 0, fill);
    parts.add(
      _Part(BlendMode.srcOver, 1, body: true, (canvas) {
        if (!faded || interiorFades) {
          // Content and inner effects together (faded as one when needed).
          if (faded) canvas.saveLayer(layerBounds, fadePaint);
          if (hasInner) canvas.saveLayer(layerBounds, Paint());
          content(canvas);
          if (hasInner) {
            innerEffects(canvas, clipToShape: false);
            canvas.restore();
          }
          if (faded) canvas.restore();
        } else {
          canvas.saveLayer(layerBounds, fadePaint);
          content(canvas);
          canvas.restore();
          if (hasInner) {
            canvas.saveLayer(layerBounds, Paint());
            innerEffects(canvas, clipToShape: true);
            canvas.restore();
          }
        }
      }),
    );

    // A 3D-rotated extrusion lights its front face too.
    if (solid && facing) {
      for (final (_, x) in extrudes) {
        if (!x.lit) continue;
        final l = _lightVector(x);
        final az = t.axes.$3;
        final f =
            x.ambient +
            x.intensity *
                math.max(0.0, az[0] * l[0] + az[1] * l[1] + az[2] * l[2]);
        if (f >= 0.995) continue;
        final g = (f.clamp(0.0, 1.0) * 255).round();
        part(BlendMode.multiply, (c) {
          c.saveLayer(
            layerBounds,
            Paint()
              ..colorFilter = ColorFilter.mode(
                Color.fromARGB(255, g, g, g),
                BlendMode.srcIn,
              ),
          );
          effectShape(c);
          c.restore();
        });
      }
    }

    // Stroke on top, with its own opacity and blend mode; Fill opacity
    // does not fade it.
    if (band != null) {
      part(
        stroke!.blend.engine,
        (c) => band.draw(
          c,
          Offset.zero,
          Paint()..filterQuality = FilterQuality.medium,
        ),
        stroke.opacity.clamp(0.0, 1.0),
      );
    }

    // Bevel & Emboss on top: shadow and highlight layers from the bevel
    // engine, each with its own blend mode (computed in the background;
    // the canvas repaints when they are ready).
    for (final job in jobs) {
      final r = job.result;
      final q = job.bevel;
      if (r == null || q == null) continue;
      final hl = r.masks[0], sh = r.masks[1];
      final from = Rect.fromLTWH(
        0,
        0,
        sh.width.toDouble(),
        sh.height.toDouble(),
      );
      void mask(Canvas c, ui.Image img, Color color, double opacity) =>
          c.drawImageRect(
            img,
            from,
            r.rect,
            Paint()
              ..filterQuality = FilterQuality.medium
              ..colorFilter = ColorFilter.mode(
                color.withValues(alpha: color.a * opacity),
                BlendMode.srcIn,
              ),
          );
      part(q.shadowMode.engine, (c) => mask(c, sh, q.shadow, q.shadowOpacity));
      part(
        q.highlightMode.engine,
        (c) => mask(c, hl, q.highlight, q.highlightOpacity),
      );
    }

    parts.addAll(lateParts);
    return _LayerPlan(
      parts,
      layerBounds,
      isolate: isGroup || maskAfter,
      applyMask: maskAfter ? (c) => _applyMask(c, layer, layerBounds) : null,
      onDispose: () {
        band?.dispose();
        if (!identical(extrudeStamp, stamp)) extrudeStamp?.dispose();
        stamp?.dispose();
        src.dispose();
      },
    );
  }

  /// The layer styles of [layer] computed in the background — bevels and
  /// glows the GPU cannot draw exactly — with their cache keys and the
  /// best result at hand: the exact one, else a quick low-resolution
  /// preview, else the last result for the same effect (so a style never
  /// vanishes while a slider moves). Missing work is started from the
  /// layer's shape (plus its stroke for outer glows; the stroke alone for
  /// Stroke Emboss) rendered at the job's resolution; with [now] (export)
  /// it runs at once, at full resolution only.
  List<_StyleJob> _styleJobs(
    Layer layer,
    double pixelScale,
    void Function(Canvas) shape,
    _Stamp? band, {
    bool start = true,
    bool now = false,
  }) {
    final jobs = <_StyleJob>[];
    final local = layerLocalRect(layer);
    final strokeOut = layer.props.stroke?.visible ?? false
        ? layer.props.stroke!.outside
        : 0.0;
    for (final e in layer.props.effects) {
      if (!e.enabled) continue;
      if (e.type == 'bevel') {
        final p = BevelParams.of(e);
        if (p.size <= 0) continue;
        final emboss = p.kind == BevelKind.strokeEmboss;
        if (emboss && band == null && start) continue;
        final box = (emboss && band != null ? band.rect : local).inflate(
          p.reach + 4,
        );
        // Texture heights ride along in the red channel.
        final tile = p.texture == null
            ? null
            : Patterns.tile(
                p.texture!,
                fg: const Color(0xFFFFFFFF),
                bg: const Color(0xFF000000),
              );
        final job = _job(
          layer: layer,
          effect: e,
          box: box,
          capBox: local.inflate(p.reach + strokeOut + 4),
          pixelScale: pixelScale,
          shapeKey: _bevelShape(layer, emboss),
          computeKey: p.computeKey,
          draw: (c) {
            if (emboss) {
              band!.draw(c);
            } else {
              shape(c);
            }
            if (tile != null) {
              final k = p.textureScale;
              c.drawRect(
                box,
                Paint()
                  ..blendMode = BlendMode.srcATop
                  ..shader = ImageShader(
                    tile,
                    TileMode.repeated,
                    TileMode.repeated,
                    Float64List.fromList([
                      k, 0, 0, 0, //
                      0, k, 0, 0, //
                      0, 0, 1, 0, //
                      0, 0, 0, 1, //
                    ]),
                  ),
              );
            }
          },
          compute: (r) => BevelEngine.job(p, r),
          start: start,
          now: now,
        );
        if (job != null) jobs.add(job..bevel = p);
      } else if ((e.type == 'shadow' || e.type == 'innerShadow') &&
          e.number('spread', 0) > 0) {
        final inner = e.type == 'innerShadow';
        final p = GlowParams.shadow(
          inner: inner,
          blur: e.number('blur', inner ? 10 : 16).clamp(0.0, 1000.0),
          spread: e.number('spread', 0).clamp(0, 100) / 100,
        );
        final base = !inner && band != null
            ? band.rect.expandToInclude(local)
            : local;
        // Inner shadows move the mask, so it covers the move as well.
        final dist = inner ? e.number('distance', 8).abs() : 0.0;
        final job = _job(
          layer: layer,
          effect: e,
          box: base.inflate(p.size + dist + 4),
          capBox: local.inflate(p.size + dist + (inner ? 0 : strokeOut) + 4),
          pixelScale: pixelScale,
          shapeKey: _bevelShape(layer, !inner),
          computeKey: p.computeKey,
          draw: (c) {
            shape(c);
            if (!inner) band?.draw(c);
          },
          compute: (r) => GlowEngine.job(p, r),
          start: start,
          now: now,
        );
        if (job != null) jobs.add(job);
      } else if (e.type == 'extrude' && ExtrudeSpec.of(e).lit) {
        // Side normals: smooth, so a modest resolution is plenty.
        final box = local.inflate(4);
        final job = _job(
          layer: layer,
          effect: e,
          box: box,
          capBox: box,
          pixelScale: math.min(
            pixelScale,
            512 /
                math.max(1, box.longestSide) /
                math.max(
                  0.01,
                  math.max(
                    layer.props.transform.scaleX.abs(),
                    layer.props.transform.scaleY.abs(),
                  ),
                ),
          ),
          shapeKey: _bevelShape(layer, false),
          computeKey: 'normals',
          draw: shape,
          compute: (_) => ExtrudeEngine.normals(),
          start: start,
          now: now,
        );
        if (job != null) jobs.add(job);
      } else if (e.type == 'glow' || e.type == 'innerGlow') {
        final p = GlowParams.of(e);
        if (p.fast || p.size <= 0) continue;
        final outer = !p.inner;
        final base = outer && band != null
            ? band.rect.expandToInclude(local)
            : local;
        final job = _job(
          layer: layer,
          effect: e,
          box: base.inflate(p.reach + 4),
          capBox: local.inflate(p.reach + (outer ? strokeOut : 0) + 4),
          pixelScale: pixelScale,
          shapeKey: _bevelShape(layer, outer),
          computeKey: p.computeKey,
          draw: (c) {
            shape(c);
            if (outer) band?.draw(c);
          },
          compute: (r) => GlowEngine.job(p, r),
          start: start,
          now: now,
        );
        if (job != null) jobs.add(job..glow = p);
      }
    }
    return jobs;
  }

  /// One background style job (see [_styleJobs]).
  _StyleJob? _job({
    required Layer layer,
    required LayerEffect effect,
    required Rect box,
    required Rect capBox,
    required double pixelScale,
    required Object shapeKey,
    required Object computeKey,
    required void Function(Canvas c) draw,
    required MaskCompute Function(double res) compute,
    required bool start,
    required bool now,
  }) {
    if (box.isEmpty || !box.isFinite) return null;
    final t = layer.props.transform;
    // Resolution in quarter-octave buckets (at most ~19% above what the
    // screen needs, so work stays close to the minimum); capped for speed
    // by a box that does not depend on the stroke band being at hand, so
    // every caller agrees on the key.
    final want = (pixelScale * math.max(t.scaleX.abs(), t.scaleY.abs())).clamp(
      1 / 16,
      8.0,
    );
    var res = math
        .pow(2, (math.log(want) / math.ln2 * 4).ceil() / 4)
        .toDouble();
    final longest = math.max(capBox.width, capBox.height);
    res = math.min(res, 1536 / longest);
    final key = (effect.type, shapeKey, computeKey, res);
    final cache = MaskJobCache.instance;
    final slot = (effect.type, layer.id, effect.id);

    ui.Image alphaAt(double r) {
      final w = math.max(1, (box.width * r).ceil());
      final h = math.max(1, (box.height * r).ceil());
      final recorder = ui.PictureRecorder();
      final c = Canvas(recorder)
        ..scale(w / box.width, h / box.height)
        ..translate(-box.left, -box.top)
        ..saveLayer(box, Paint());
      draw(c);
      c.restore();
      final pic = recorder.endRecording();
      final img = pic.toImageSync(w, h);
      pic.dispose();
      return img;
    }

    var result = cache.lookup(key);
    final exact = result != null;
    if (result == null) {
      final pixels = box.width * box.height * res * res;
      if (now || pixels <= _livePixels) {
        // Small enough to compute at full resolution on every change:
        // the last result stays sharp on screen until the next lands.
        if (start && !cache.isPending(key)) {
          cache.request(
            key,
            slot,
            alphaAt(res),
            box,
            compute(res),
            lane: now ? MaskLane.now : MaskLane.preview,
          );
        }
        result = now ? null : cache.latest(slot);
      } else {
        // Big: a quick version at a reduced (but not blurry) resolution
        // follows sliders live; full resolution once they rest.
        final pres = res * math.sqrt(_livePixels / pixels);
        final pkey = (effect.type, shapeKey, computeKey, pres);
        final quick = cache.lookup(pkey);
        if (start) {
          if (quick == null && !cache.isPending(pkey)) {
            cache.request(
              pkey,
              slot,
              alphaAt(pres),
              box,
              compute(pres),
              lane: MaskLane.preview,
            );
          }
          if (!cache.isPending(key)) {
            cache.request(
              key,
              slot,
              alphaAt(res),
              box,
              compute(res),
              lane: MaskLane.full,
            );
          }
        }
        result = quick ?? cache.latest(slot);
      }
    }
    return _StyleJob(key, result, exact: exact, effectId: effect.id);
  }

  /// Background styles up to this many pixels recompute at full
  /// resolution live; bigger ones show a reduced version while editing.
  static const _livePixels = 640000.0;

  /// What a bevel's shape depends on: the layer without its placement and
  /// its other effects.
  Layer _bevelShape(Layer l, bool withStroke) => l.withProps(
    l.props.copyWith(
      transform: const LayerTransform(),
      opacity: 1,
      blendMode: PixBlendMode.normal,
      clip: false,
      // Pixel filters change the shape; styles do not.
      effects: [
        for (final e in l.props.effects)
          if (e.enabled && _fx[e.type]?.filter != null) e,
      ],
      fillOpacity: 1,
      clearStroke: !withStroke,
    ),
  );

  /// Computes every background style (bevels, precise glows…) [layers]
  /// need at [pixelScale] (export awaits this so nothing is missing).
  Future<void> prepareStyles(Iterable<Layer> layers, double pixelScale) async {
    final waits = <Future<void>>[];
    void walk(Iterable<Layer> list) {
      for (final l in list) {
        if (l is GroupLayer) {
          walk(l.children);
          continue;
        }
        if (!l.props.effects.any((e) => e.enabled && _isSlowStyle(e))) {
          continue;
        }
        final src = _ShapeSource.of(this, l, const {});
        final maskAfter = l.props.maskHidesEffects && l.props.hasMask;
        void shape(Canvas c) => maskAfter
            ? src.draw(c)
            : _paintMasked(c, l, const {}, null, content: src.draw);
        final stamp = l.props.stroke?.visible ?? false
            ? _Stamp.of(l, shape, pixelScale, extra: src.reach)
            : null;
        final band = stamp == null
            ? null
            : ((src.reach > 0
                      ? null
                      : _vectorBand(
                          l,
                          l.props.stroke!,
                          stamp,
                          layerLocalRect(l),
                        )) ??
                  stamp.strokeBand(l.props.stroke!, layerLocalRect(l)));
        for (final job in _styleJobs(l, pixelScale, shape, band, now: true)) {
          waits.add(MaskJobCache.instance.wait(job.key));
        }
        band?.dispose();
        stamp?.dispose();
        src.dispose();
      }
    }

    walk(layers);
    await Future.wait(waits);
  }

  /// Whether [e] may need background work.
  static bool _isSlowStyle(LayerEffect e) =>
      e.type == 'bevel' ||
      (e.type == 'extrude' && ExtrudeSpec.of(e).lit) ||
      ((e.type == 'shadow' || e.type == 'innerShadow') &&
          e.number('spread', 0) > 0) ||
      ((e.type == 'glow' || e.type == 'innerGlow') && !GlowParams.of(e).fast);

  /// Photoshop's stroke from the layer's vector outline: the outline drawn
  /// twice as wide as the stroke (once for centre), clipped outside or
  /// inside the shape, then coloured. Null when the layer has no plain
  /// outline (images, curved or boxed text, masked layers).
  _Stamp? _vectorBand(
    Layer layer,
    LayerStroke s,
    _Stamp shapeStamp,
    Rect local,
  ) {
    if (layer.props.hasMask) return null;
    final width = s.position == StrokePosition.center ? s.size : s.size * 2;
    void Function(Canvas c)? outline;
    switch (layer) {
      case ShapeLayer l:
        final path = buildShapePath(l);
        outline = (c) => c.drawPath(path, _outlinePaint(width));
      case IconLayer l:
        final path = iconPath(l);
        outline = (c) => c.drawPath(path, _outlinePaint(width));
      case TextLayer l when l.background == null && l.curve.abs() < 0.5:
        final entry = TextLayoutCache.instance.entry(l);
        outline = (c) => entry.paintOutline(c, width);
      default:
        return null;
    }
    final box = shapeStamp.rect.inflate(s.outside + 2);
    return _Stamp._make(box, shapeStamp._res, (c) {
      c.saveLayer(box, Paint());
      outline!(c);
      switch (s.position) {
        case StrokePosition.outside:
          shapeStamp.draw(
            c,
            Offset.zero,
            Paint()..blendMode = BlendMode.dstOut,
          );
        case StrokePosition.inside:
          shapeStamp.draw(c, Offset.zero, Paint()..blendMode = BlendMode.dstIn);
        case StrokePosition.center:
          break;
      }
      c.drawRect(
        box,
        s.fill.applyTo(Paint(), local.inflate(s.outside))
          ..blendMode = BlendMode.srcIn,
      );
      c.restore();
    });
  }

  static Paint _outlinePaint(double width) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true
    ..color = const Color(0xFFFFFFFF);

  /// Whether a layer is worth caching as a bitmap.
  bool _isExpensive(Layer layer) {
    final p = layer.props;
    if (p.hasMask) return true;
    if (p.stroke?.visible ?? false) return true;
    if (layer is TextLayer && layer.curve.abs() >= 0.5) return true;
    for (final e in p.effects) {
      if (!e.enabled) continue;
      if (e.type == 'satin' ||
          e.type == 'bevel' ||
          e.type == 'glow' ||
          e.type == 'innerGlow') {
        return true;
      }
      final d = _fx[e.type];
      if (d == null) continue;
      if (d.filter != null) return true;
      if (d.shadow != null ||
          d.inner != null ||
          d.bevel != null ||
          d.extrude != null ||
          (d.blurSigma?.call(e) ?? 0) > 0) {
        return true;
      }
    }
    return false;
  }

  /// Renders [layer] (at the document origin, full opacity) into bitmaps
  /// at the current resolution — one per differently blended part, so
  /// each still blends with the layers beneath — or returns the cached
  /// ones. [blend] is the mode of the layer itself.
  CachedLayer? _cachedBitmap(Layer layer, BlendMode blend) {
    if (layer is RasterLayer && assets.imageOf(layer.assetId) == null) {
      return null; // not decoded yet — don't cache the placeholder
    }
    for (final id in [...layer.props.maskAssets, ...layer.fillAssets]) {
      if (assets.imageOf(id) == null) return null;
    }

    final p = layer.props;
    final base = layer.withProps(
      p.copyWith(
        transform: p.transform.copyWith(x: 0, y: 0),
        opacity: 1,
        blendMode: PixBlendMode.normal,
        clip: false,
      ),
    );
    // Power-of-two resolution buckets: zooming re-renders only when the
    // needed detail doubles or halves.
    var bucket = 1.0;
    final want = pixelScale.clamp(1 / 64, 16.0);
    while (bucket < want) {
      bucket *= 2;
    }
    while (bucket / 2 >= want) {
      bucket /= 2;
    }
    final key = (base, bucket, TextLayoutCache.generation, blend.index);
    final hit = cache!.lookup(key);
    if (hit != null) return hit;
    // Changing every frame (a slider, a rotate gesture): a bitmap would be
    // stale by the next frame, so paint directly instead.
    if (cache!.isHot((layer.id, bucket), key)) return null;

    final rect = layerDocumentBounds(base).inflate(_effectSpill([base]) + 4);
    if (rect.isEmpty || !rect.isFinite) return null;
    final longest = math.max(rect.width, rect.height);
    final s = math.min(bucket, 4096 / longest);
    // A style still computing: paint directly until it is ready.
    if (layer.props.effects.any((e) => e.enabled && _isSlowStyle(e))) {
      final jobs = _styleJobs(base, s, (_) {}, null, start: false);
      if (jobs.any((j) => !j.exact)) return null;
    }
    final w = math.max(1, (rect.width * s).ceil());
    final h = math.max(1, (rect.height * s).ceil());
    final r = DocumentRenderer(assets, effects: effects, pixelScale: s);
    final plan = r._plan(base, const {});
    ui.Image render(void Function(Canvas c) draw) {
      final recorder = ui.PictureRecorder();
      final c = Canvas(recorder)
        ..scale(w / rect.width, h / rect.height)
        ..translate(-rect.left, -rect.top);
      base.props.transform.applyTo(c);
      draw(c);
      final picture = recorder.endRecording();
      final image = picture.toImageSync(w, h);
      picture.dispose();
      return image;
    }

    final images = <CachedPart>[];
    if (plan.isolate) {
      images.add(
        CachedPart(
          render((c) => plan.paint(c, blend: BlendMode.srcOver, opacity: 1)),
          blend,
          1,
        ),
      );
    } else {
      // Consecutive plain parts share one bitmap.
      var i = 0;
      final parts = plan.parts;
      while (i < parts.length) {
        final mode = parts[i].body ? blend : parts[i].mode;
        final a = parts[i].alpha;
        var j = i + 1;
        if (mode == BlendMode.srcOver && a >= 1) {
          while (j < parts.length &&
              (parts[j].body ? blend : parts[j].mode) == BlendMode.srcOver &&
              parts[j].alpha >= 1) {
            j++;
          }
        }
        final run = parts.sublist(i, j);
        images.add(
          CachedPart(
            render((c) {
              for (final q in run) {
                q.draw(c);
              }
            }),
            mode,
            a,
          ),
        );
        i = j;
      }
    }
    plan.dispose();
    final entry = CachedLayer(images, rect, s);
    cache!.put(key, entry);
    return entry;
  }

  /// Inner shadow / glow: a blurred, offset inverse of the shape drawn only
  /// where the shape already has pixels.
  void _paintInner(
    Canvas canvas,
    Offset localOffset,
    double blurPx,
    Color color,
    Rect area,
    void Function(Canvas) shape, {
    bool clipToShape = false,
    BlendMode mode = BlendMode.srcOver,
  }) {
    // Over existing content: srcATop keeps it inside the painted pixels.
    // Alone (fill opacity) or with a blend mode: clip to the shape, then
    // composite with the mode.
    final clip = clipToShape || mode != BlendMode.srcOver;
    canvas.saveLayer(
      area,
      Paint()..blendMode = clip ? mode : BlendMode.srcATop,
    );
    canvas.saveLayer(
      area,
      Paint()
        ..imageFilter = blurPx > 0
            ? ui.ImageFilter.blur(
                sigmaX: blurPx / 2,
                sigmaY: blurPx / 2,
                tileMode: TileMode.decal,
              )
            : null,
    );
    canvas.drawRect(area.inflate(blurPx * 2), Paint()..color = color);
    canvas
      ..save()
      ..translate(localOffset.dx, localOffset.dy);
    canvas.saveLayer(null, Paint()..blendMode = BlendMode.dstOut);
    shape(canvas);
    canvas
      ..restore()
      ..restore()
      ..restore();
    if (clip) {
      canvas.saveLayer(area, Paint()..blendMode = BlendMode.dstIn);
      shape(canvas);
      canvas.restore();
    }
    canvas.restore();
  }

  /// The light's direction (x right, y down, z towards the viewer).
  static List<double> _lightVector(ExtrudeSpec x) {
    final th = x.lightAngle * math.pi / 180, al = x.altitude * math.pi / 180;
    return [
      math.cos(al) * math.cos(th),
      -math.cos(al) * math.sin(th),
      math.sin(al),
    ];
  }

  static List<double> _mul3(List<double> a, List<double> b) => [
    for (var r = 0; r < 3; r++)
      for (var c = 0; c < 3; c++)
        a[r * 3] * b[c] + a[r * 3 + 1] * b[3 + c] + a[r * 3 + 2] * b[6 + c],
  ];

  static List<double> _invert3(List<double> h) {
    final a = h[0], b = h[1], c = h[2];
    final d = h[3], e = h[4], f = h[5];
    final g = h[6], hh = h[7], i = h[8];
    final det =
        a * (e * i - f * hh) - b * (d * i - f * g) + c * (d * hh - e * g);
    final k = det.abs() < 1e-12 ? 0.0 : 1 / det;
    return [
      (e * i - f * hh) * k, (c * hh - b * i) * k, (b * f - c * e) * k, //
      (f * g - d * i) * k, (a * i - c * g) * k, (c * d - a * f) * k, //
      (d * hh - e * g) * k, (b * g - a * hh) * k, (a * e - b * d) * k, //
    ];
  }

  /// How far a 3D extrusion reaches past the layer box (layer units).
  static double _extrudeReach(ExtrudeSpec x, Rect local, double ms) {
    final half = local.longestSide / 2;
    var r = x.depth / ms;
    if (x.backScale > 1) r += (x.backScale - 1) * half;
    if (x.twist != 0) r += half * 0.5;
    return r;
  }

  /// Photoshop-style 3D extrusion. The sides are made once per paint as a
  /// "lit stamp": the shape's normal map turned into light (ambient +
  /// diffuse from the light's direction, plus gloss) by a colour matrix,
  /// times the side colour or the layer's own pixels, cut to the shape.
  /// That stamp is then laid down back to front along the depth — about
  /// one copy per output pixel, each moved, scaled (taper) and turned
  /// (twist) and darkened towards the back — so every visible side pixel
  /// shows the light of the edge that made it.
  void _paintExtrude(
    Canvas canvas,
    ExtrudeSpec x,
    Layer layer,
    Rect? bounds,
    Offset Function(Offset) toLocal,
    _Stamp stamp, {
    MaskResult? normals,
    required void Function(Canvas) content,
  }) {
    if (x.depth <= 0) return;
    final r = stamp.rect;
    final al = x.altitude * math.pi / 180;
    final t = layer.props.transform;
    final solid = t.hasTilt;
    // The light in the layer's own axes (sides face along local x / y).
    final lw = _lightVector(x);
    final (ax, ay, az) = t.axes;
    final lx = solid ? ax[0] * lw[0] + ax[1] * lw[1] + ax[2] * lw[2] : lw[0];
    final ly = solid ? ay[0] * lw[0] + ay[1] * lw[1] + ay[2] * lw[2] : lw[1];
    Color grey(double v) {
      final g = (v.clamp(0.0, 1.0) * 255).round();
      return Color.fromARGB(255, g, g, g);
    }

    final lit = _Stamp._make(r, stamp._res, (c) {
      c.saveLayer(r, Paint());
      // Light. Until the normals are ready, sides get an even light.
      c.drawRect(
        r,
        Paint()
          ..color = grey(
            x.lit && normals == null
                ? x.ambient + x.intensity * math.cos(al) * 0.3
                : x.ambient,
          ),
      );
      final nm = normals?.masks.first;
      if (x.lit && nm != null) {
        final from = Rect.fromLTWH(
          0,
          0,
          nm.width.toDouble(),
          nm.height.toDouble(),
        );
        // dot(n, l) with n = 2·(R, G)/255 − 1.
        List<double> light(double k, double bias) {
          final row = [2 * k * lx, 2 * k * ly, 0.0, 0.0, bias];
          return [...row, ...row, ...row, 0, 0, 0, 0, 255];
        }

        // Ambient everywhere, plus diffuse light on the sides that face
        // it (negative light clamps to zero: Lambert's max(0, n·l)).
        c.drawImageRect(
          nm,
          from,
          normals!.rect,
          Paint()
            ..filterQuality = FilterQuality.medium
            ..blendMode = BlendMode.plus
            ..colorFilter = ColorFilter.matrix(
              light(x.intensity, -255 * x.intensity * (lx + ly)),
            ),
        );
        if (x.gloss > 0) {
          // Shine where a side faces the light squarely.
          final k = x.gloss * 4;
          c.drawImageRect(
            nm,
            from,
            normals.rect,
            Paint()
              ..filterQuality = FilterQuality.medium
              ..blendMode = BlendMode.plus
              ..colorFilter = ColorFilter.matrix(
                light(k, 255 * k * (-(lx + ly) - 0.6)),
              ),
          );
        }
      }
      // Material: a colour, or the layer's own pixels.
      if (x.layerMaterial) {
        // The layer's colours, opaque right to the anti-aliased rim (a
        // faint rim would stack into streaks along the sides).
        c.saveLayer(
          r,
          Paint()
            ..blendMode = BlendMode.multiply
            ..colorFilter = const ColorFilter.matrix([
              1, 0, 0, 0, 0, //
              0, 1, 0, 0, 0, //
              0, 0, 1, 0, 0, //
              0, 0, 0, 0, 255, //
            ]),
        );
        content(c);
        c.restore();
      } else {
        c.drawRect(
          r,
          Paint()
            ..color = x.color
            ..blendMode = BlendMode.multiply,
        );
      }
      stamp.draw(c, Offset.zero, Paint()..blendMode = BlendMode.dstIn);
      c.restore();
    });

    final center = layerLocalRect(layer).center;
    final half = layerLocalRect(layer).longestSide / 2;
    final outPx = pixelScale * math.max(t.scaleX.abs(), t.scaleY.abs());
    void taperTwist(double u) {
      if (x.backScale != 1 || x.twist != 0) {
        canvas
          ..translate(center.dx, center.dy)
          ..rotate(x.twist * math.pi / 180 * u)
          ..scale(1 + (x.backScale - 1) * u)
          ..translate(-center.dx, -center.dy);
      }
    }

    final shapeTravel =
        (x.backScale - 1).abs() * half * outPx +
        (x.twist * math.pi / 180).abs() * half * outPx;

    // Darker towards the back, per copy (no offscreen layers needed).
    Paint shaded(double u) {
      final f = 1 - x.shade * u;
      return Paint()
        ..filterQuality = FilterQuality.medium
        ..colorFilter = ColorFilter.matrix([
          f, 0, 0, 0, 0, //
          0, f, 0, 0, 0, //
          0, 0, f, 0, 0, //
          0, 0, 0, 1, 0, //
        ]);
    }

    if (solid) {
      // A real solid: each slice sits at its depth behind the layer, in
      // the layer's 3D rotation and perspective, drawn far to near.
      final base = t.homographyAt(0);
      final inv = _invert3(base);
      final side = math.sqrt(az[0] * az[0] + az[1] * az[1]);
      // Two slices per output pixel of side: seamless faces.
      final steps =
          ((x.depth * pixelScale * math.max(side, 0.04) + shapeTravel) * 2)
              .ceil()
              .clamp(2, 600);
      final facing = az[2] >= 0;
      void slice(int i) {
        final u = i / steps;
        final m = _mul3(inv, t.homographyAt(-x.depth * u));
        canvas
          ..save()
          ..transform(
            Float64List.fromList([
              m[0], m[3], 0, m[6], //
              m[1], m[4], 0, m[7], //
              0, 0, 1, 0, //
              m[2], m[5], 0, m[8], //
            ]),
          );
        taperTwist(u);
        lit.draw(canvas, Offset.zero, shaded(u));
        canvas.restore();
      }

      // Far to near.
      if (facing) {
        for (var i = steps; i >= 1; i--) {
          slice(i);
        }
      } else {
        for (var i = 1; i <= steps; i++) {
          slice(i);
        }
      }
      if (!facing) {
        // The back face, lit as a flat face pointing away.
        final g =
            (x.ambient +
                    x.intensity *
                        math.max(
                          0.0,
                          -(az[0] * lw[0] + az[1] * lw[1] + az[2] * lw[2]),
                        ))
                .clamp(0.0, 1.0) *
            (1 - x.shade);
        final m = _mul3(inv, t.homographyAt(-x.depth));
        canvas
          ..save()
          ..transform(
            Float64List.fromList([
              m[0], m[3], 0, m[6], //
              m[1], m[4], 0, m[7], //
              0, 0, 1, 0, //
              m[2], m[5], 0, m[8], //
            ]),
          );
        taperTwist(1);
        canvas.saveLayer(null, Paint());
        if (x.layerMaterial) {
          content(canvas);
        } else {
          stamp.draw(
            canvas,
            Offset.zero,
            Paint()..colorFilter = ColorFilter.mode(x.color, BlendMode.srcIn),
          );
        }
        final gv = (g * 255).round();
        canvas
          ..drawRect(
            r.inflate(r.longestSide),
            Paint()
              ..color = Color.fromARGB(255, gv, gv, gv)
              ..blendMode = BlendMode.modulate,
          )
          ..restore()
          ..restore();
      }
      lit.dispose();
      return;
    }

    final dir = Offset(math.cos(x.angle), math.sin(x.angle));
    // About one copy per output pixel of travel (depth, taper, twist).
    final travel = x.depth * pixelScale + shapeTravel;
    final steps = travel.ceil().clamp(1, 360);
    for (var i = steps; i >= 1; i--) {
      final u = i / steps;
      final o = toLocal(dir * (x.depth * u));
      canvas
        ..save()
        ..translate(o.dx, o.dy);
      taperTwist(u);
      lit.draw(canvas, Offset.zero, shaded(u));
      canvas.restore();
    }
    lit.dispose();
  }

  /// Content with the layer mask applied (vector strokes, white = visible).
  /// [content] draws the (filtered) pixels; the plain content by default.
  void _paintMasked(
    Canvas canvas,
    Layer layer,
    Set<String> hidden,
    Rect? bounds, {
    void Function(Canvas c)? content,
  }) {
    void draw() => content == null
        ? _paintContent(canvas, layer, hidden)
        : content(canvas);
    if (!layer.props.hasMask) {
      draw();
      return;
    }
    canvas.saveLayer(bounds, Paint());
    draw();
    _applyMask(canvas, layer, bounds);
    canvas.restore();
  }

  /// Multiplies what is in the current layer by [layer]'s mask (with its
  /// density and feather).
  void _applyMask(Canvas canvas, Layer layer, Rect? bounds) {
    final props = layer.props;
    final maskPaint = Paint()..blendMode = BlendMode.dstIn;
    // Density: alpha' = d·alpha + (1 − d) — a weaker mask.
    final d = props.maskDensity;
    if (d < 1) {
      maskPaint.colorFilter = ColorFilter.matrix([
        1, 0, 0, 0, 0, //
        0, 1, 0, 0, 0, //
        0, 0, 1, 0, 0, //
        0, 0, 0, d, (1 - d) * 255, //
      ]);
    }
    final f = props.maskFeather;
    if (f > 0) {
      maskPaint.imageFilter = ui.ImageFilter.blur(
        sigmaX: f / 2,
        sigmaY: f / 2,
        tileMode: TileMode.decal,
      );
    }
    // A feathered mask spills outside the layer box while blurring.
    canvas.saveLayer(f > 0 ? null : bounds, maskPaint);
    final area =
        (bounds ?? layerLocalRect(layer).inflate(_effectSpill([layer]) + 64))
            .inflate(f * 3 + 2);
    final img = _maskImage(layer, area);
    if (img != null) {
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        area,
        Paint()..filterQuality = FilterQuality.medium,
      );
    } else {
      paintMask(canvas, props.mask, area, images: assets.imageOf);
    }
    canvas.restore();
  }

  /// The layer's mask rendered once as an image and reused: masks made of
  /// many soft brush strokes are slow to redraw, and the mask rarely
  /// changes while everything else about a layer does.
  ui.Image? _maskImage(Layer layer, Rect area) {
    final props = layer.props;
    for (final id in props.maskAssets) {
      if (assets.imageOf(id) == null) return null;
    }
    if (area.isEmpty || !area.isFinite) return null;
    final t = props.transform;
    final want = math.max(
      1e-3,
      pixelScale * math.max(t.scaleX.abs(), t.scaleY.abs()),
    );
    var res = math.pow(2, (math.log(want) / math.ln2).ceil()).toDouble();
    final cap = cache != null ? 2048.0 : 4096.0;
    res = math.min(res, cap / area.longestSide);
    final key = (_Identity(props.mask), area, res);
    final hit = _maskImages.remove(key);
    if (hit != null) {
      _maskImages[key] = hit;
      return hit;
    }
    final w = math.max(1, (area.width * res).ceil());
    final h = math.max(1, (area.height * res).ceil());
    // Masks change by strokes added (or the last one growing, while
    // painting): start from the image of the earlier strokes.
    ui.Image render(ui.Image? from, Iterable<MaskStroke> strokes) {
      final recorder = ui.PictureRecorder();
      final c = Canvas(recorder)
        ..scale(w / area.width, h / area.height)
        ..translate(-area.left, -area.top);
      if (from == null) {
        c.drawRect(area, Paint()..color = const Color(0xFFFFFFFF));
      } else {
        c.drawImageRect(
          from,
          Rect.fromLTWH(0, 0, from.width.toDouble(), from.height.toDouble()),
          area,
          Paint()..blendMode = BlendMode.src,
        );
      }
      for (final st in strokes) {
        paintMaskStroke(c, st, area, assets.imageOf);
      }
      final pic = recorder.endRecording();
      final out = pic.toImageSync(w, h);
      pic.dispose();
      return out;
    }

    final strokes = props.mask;
    final n = strokes.length;
    var done = 0;
    ui.Image? from;
    final base = _maskBases[layer.id];
    if (base != null &&
        base.area == area &&
        base.res == res &&
        base.strokes.length <= n) {
      var same = true;
      for (var i = 0; i < base.strokes.length; i++) {
        if (!identical(base.strokes[i], strokes[i])) {
          same = false;
          break;
        }
      }
      if (same) {
        done = base.strokes.length;
        from = base.image;
      }
    }
    if (n - 1 > done) {
      from = render(from, strokes.sublist(done, n - 1));
      done = n - 1;
      _maskBases[layer.id] = _MaskBase(
        strokes.sublist(0, n - 1),
        area,
        res,
        from,
      );
      if (_maskBases.length > 8) _maskBases.remove(_maskBases.keys.first);
    }
    final img = render(from, strokes.sublist(done));
    _maskImages[key] = img;
    // Evicted images are left to the garbage collector (a picture being
    // painted may still use them).
    while (_maskImages.length > 12) {
      _maskImages.remove(_maskImages.keys.first);
    }
    return img;
  }

  static final LinkedHashMap<Object, ui.Image> _maskImages = LinkedHashMap();
  static final LinkedHashMap<String, _MaskBase> _maskBases = LinkedHashMap();

  /// Outer / Inner Glow on the GPU: the (inverted, for inner) shape
  /// blurred over the glow size, its alpha scaled by 1 / Range (the
  /// linear contour; flipped for a Center source), coloured, clipped to
  /// the shape for inner glows and composited with the glow's mode.
  void _paintGlow(
    Canvas canvas,
    GlowParams g,
    Rect area,
    void Function(Canvas) shape, {
    BlendMode? mode,
  }) {
    final c = g.color;
    final k = 1 / g.range;
    final sigma = g.sigma;
    final center = g.inner && g.center;
    canvas
      ..saveLayer(
        area,
        Paint()
          ..blendMode = mode ?? g.blend.engine
          ..color = Color.fromRGBO(0, 0, 0, (g.opacity * c.a).clamp(0.0, 1.0)),
      )
      ..saveLayer(
        area,
        Paint()
          ..colorFilter = ColorFilter.matrix([
            0, 0, 0, 0, c.r * 255, //
            0, 0, 0, 0, c.g * 255, //
            0, 0, 0, 0, c.b * 255, //
            0, 0, 0, center ? -k : k, center ? 255 : 0, //
          ]),
      )
      ..saveLayer(
        area,
        Paint()
          ..imageFilter = sigma > 0.05
              ? ui.ImageFilter.blur(
                  sigmaX: sigma,
                  sigmaY: sigma,
                  tileMode: TileMode.decal,
                )
              : null,
      );
    if (g.inner) {
      canvas
        ..drawRect(
          area.inflate(sigma * 3 + 2),
          Paint()..color = const Color(0xFFFFFFFF),
        )
        ..saveLayer(null, Paint()..blendMode = BlendMode.dstOut);
      shape(canvas);
      canvas.restore();
    } else {
      shape(canvas);
    }
    canvas
      ..restore()
      ..restore();
    if (g.inner) {
      canvas.saveLayer(area, Paint()..blendMode = BlendMode.dstIn);
      shape(canvas);
      canvas.restore();
    }
    canvas.restore();
  }

  /// A glow computed in the background: its coverage mask, coloured (or
  /// with its gradient colours), composited with the glow's mode.
  void _paintGlowMask(
    Canvas canvas,
    MaskResult r,
    GlowParams g, {
    BlendMode? mode,
  }) {
    final m = r.masks[0];
    final src = Rect.fromLTWH(0, 0, m.width.toDouble(), m.height.toDouble());
    if (r.masks.length > 1) {
      canvas
        ..saveLayer(
          r.rect,
          Paint()
            ..blendMode = mode ?? g.blend.engine
            ..color = Color.fromRGBO(0, 0, 0, g.opacity),
        )
        ..drawImageRect(
          r.masks[1],
          src,
          r.rect,
          Paint()..filterQuality = FilterQuality.medium,
        )
        ..drawImageRect(
          m,
          src,
          r.rect,
          Paint()
            ..filterQuality = FilterQuality.medium
            ..blendMode = BlendMode.dstIn,
        )
        ..restore();
      return;
    }
    final c = g.color;
    canvas.drawImageRect(
      m,
      src,
      r.rect,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..blendMode = mode ?? g.blend.engine
        ..colorFilter = ColorFilter.mode(
          c.withValues(alpha: (c.a * g.opacity).clamp(0.0, 1.0)),
          BlendMode.srcIn,
        ),
    );
  }

  static const _invertRgb = ColorFilter.matrix([
    -1, 0, 0, 0, 255, //
    0, -1, 0, 0, 255, //
    0, 0, -1, 0, 255, //
    0, 0, 0, 1, 0, //
  ]);

  /// Photoshop's Satin: |A − B| of two blurred copies of the shape moved
  /// ±[offset] (as exact grey arithmetic: `A − B = 1 − ((1 − A) + B)`),
  /// optionally inverted, coloured, clipped to the shape and composited
  /// with the satin's blend mode.
  void _paintSatin(
    Canvas canvas,
    SatinSpec s,
    Rect area,
    Offset offset,
    void Function(Canvas) shape,
  ) {
    final blur = s.size > 0
        ? ui.ImageFilter.blur(
            sigmaX: s.size / 2,
            sigmaY: s.size / 2,
            tileMode: TileMode.decal,
          )
        : null;
    void copy(Offset o, Color color, BlendMode mode) {
      canvas
        ..saveLayer(
          area,
          Paint()
            ..blendMode = mode
            ..colorFilter = ColorFilter.mode(color, BlendMode.srcIn)
            ..imageFilter = blur,
        )
        ..translate(o.dx, o.dy);
      shape(canvas);
      canvas.restore();
    }

    const black = Color(0xFF000000), white = Color(0xFFFFFFFF);
    void minus(Offset a, Offset b, BlendMode mode) {
      canvas.saveLayer(
        area,
        Paint()
          ..colorFilter = _invertRgb
          ..blendMode = mode,
      );
      canvas.drawRect(area, Paint()..color = white);
      copy(a, black, BlendMode.srcOver);
      copy(b, white, BlendMode.plus);
      canvas.restore();
    }

    final c = s.color, op = s.opacity;
    final r = c.r * 255, g = c.g * 255, b = c.b * 255;
    final a = c.a * op;
    canvas.saveLayer(area, Paint()..blendMode = s.blend.engine);
    canvas.saveLayer(
      area,
      Paint()
        ..colorFilter = ColorFilter.matrix([
          0, 0, 0, 0, r, //
          0, 0, 0, 0, g, //
          0, 0, 0, 0, b, //
          if (s.invert) ...[-a, 0, 0, 0, a * 255] else ...[a, 0, 0, 0, 0],
        ]),
    );
    canvas.drawRect(area, Paint()..color = black);
    minus(offset, -offset, BlendMode.srcOver); // A − B
    minus(-offset, offset, BlendMode.plus); // + (B − A)
    canvas.restore();
    canvas.saveLayer(area, Paint()..blendMode = BlendMode.dstIn);
    shape(canvas);
    canvas
      ..restore()
      ..restore();
  }

  /// Draws a mask as alpha (opaque = visible) over [area]: starts white
  /// (reveal all) and applies every stroke in order.
  static void paintMask(
    Canvas canvas,
    List<MaskStroke> mask,
    Rect area, {
    MaskImageLookup? images,
  }) {
    canvas.drawRect(area, Paint()..color = const Color(0xFFFFFFFF));
    for (final s in mask) {
      paintMaskStroke(canvas, s, area, images);
    }
  }

  /// Draws one mask stroke inside a mask layer. Photoshop semantics: the
  /// stroke replaces the mask with its grey [MaskStroke.value] by its
  /// coverage × opacity — `new = old·(1 − c) + grey·c` — done as an erase
  /// (dstOut) followed by an additive (plus) pass over the same shape.
  static void paintMaskStroke(
    Canvas canvas,
    MaskStroke s, [
    Rect? area,
    MaskImageLookup? images,
  ]) {
    final whole = area ?? const Rect.fromLTWH(-1e5, -1e5, 2e5, 2e5);
    final v = s.value.clamp(0.0, 1.0), a = s.opacity.clamp(0.0, 1.0);
    if (a <= 0) return;

    // Bitmap coverage (selections turned into masks).
    if (s.shape == MaskShape.image) {
      final id = s.assetId;
      final img = id == null ? null : images?.call(id);
      if (img == null || s.points.length < 2) return;
      final src = Rect.fromLTWH(
        0,
        0,
        img.width.toDouble(),
        img.height.toDouble(),
      );
      final dst = Rect.fromPoints(s.points[0], s.points[1]);
      canvas.drawImageRect(
        img,
        src,
        dst,
        Paint()
          ..filterQuality = FilterQuality.medium
          ..blendMode = BlendMode.dstOut
          ..color = Color.fromRGBO(0, 0, 0, a),
      );
      if (v * a > 0) {
        canvas.drawImageRect(
          img,
          src,
          dst,
          Paint()
            ..filterQuality = FilterQuality.medium
            ..blendMode = BlendMode.plus
            ..colorFilter = ColorFilter.mode(
              Color.fromRGBO(255, 255, 255, v * a),
              BlendMode.srcIn,
            ),
        );
      }
      return;
    }

    // Whole-mask fill and gradients.
    if (s.shape == MaskShape.fill ||
        s.shape == MaskShape.linear ||
        s.shape == MaskShape.radial) {
      canvas.drawRect(
        whole,
        Paint()
          ..blendMode = BlendMode.dstOut
          ..color = Color.fromRGBO(255, 255, 255, a),
      );
      final add = Paint()..blendMode = BlendMode.plus;
      if (s.shape == MaskShape.fill || s.points.length < 2) {
        if (v * a <= 0) return;
        add.color = Color.fromRGBO(255, 255, 255, v * a);
      } else {
        final c0 = Color.fromRGBO(255, 255, 255, v * a);
        final c1 = Color.fromRGBO(255, 255, 255, (1 - v) * a);
        final p0 = s.points[0], p1 = s.points[1];
        add.shader = s.shape == MaskShape.linear
            ? ui.Gradient.linear(p0, p1, [c0, c1])
            : ui.Gradient.radial(p0, math.max(0.5, (p1 - p0).distance), [
                c0,
                c1,
              ]);
      }
      canvas.drawRect(whole, add);
      return;
    }

    if (s.points.isEmpty && s.contour == null) return;
    void draw(Paint paint) {
      paint.isAntiAlias = true;
      if (s.softness > 0) {
        paint.maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          math.max(0.5, s.width * s.softness * 0.35),
        );
      }
      _drawMaskGeometry(canvas, s, paint);
    }

    // Pure black/white at full strength: one pass is enough.
    if (v == 0) {
      draw(
        Paint()
          ..blendMode = BlendMode.dstOut
          ..color = Color.fromRGBO(255, 255, 255, a),
      );
      return;
    }
    if (v == 1 && a == 1) {
      draw(Paint()..color = const Color(0xFFFFFFFF));
      return;
    }
    // Grey or partial opacity: erase by the coverage, then add the grey
    // (both straight onto the mask, so they blend with what is there).
    draw(
      Paint()
        ..blendMode = BlendMode.dstOut
        ..color = Color.fromRGBO(255, 255, 255, a),
    );
    draw(
      Paint()
        ..blendMode = BlendMode.plus
        ..color = Color.fromRGBO(255, 255, 255, v * a),
    );
  }

  static void _drawMaskGeometry(Canvas canvas, MaskStroke s, Paint paint) {
    if (s.contour != null) {
      final c = s.contour!;
      if (c.nodes.length < 2) return;
      canvas.drawPath(contourPath(c.copyWith(closed: true)), paint);
      return;
    }
    if (s.shape == MaskShape.area) {
      if (s.points.length < 3) return;
      canvas.drawPath(Path()..addPolygon(s.points, true), paint);
      return;
    }
    if (s.points.length == 1) {
      canvas.drawCircle(s.points.first, s.width / 2, paint);
      return;
    }
    final path = Path()..moveTo(s.points.first.dx, s.points.first.dy);
    for (final p in s.points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = s.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  double _minScale(LayerTransform t) =>
      math.max(0.0001, math.min(t.scaleX.abs(), t.scaleY.abs()));

  void _paintContent(Canvas canvas, Layer layer, Set<String> hidden) {
    switch (layer) {
      case GroupLayer g:
        paintLayers(canvas, g.children, hidden: hidden);
      case RasterLayer l:
        final img = assets.imageOf(l.assetId);
        final dst = Rect.fromCenter(
          center: Offset.zero,
          width: l.width,
          height: l.height,
        );
        if (img == null) {
          canvas.drawRect(dst, Paint()..color = const Color(0x22888888));
          return;
        }
        canvas.drawImageRect(
          img,
          Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
          dst,
          Paint()
            ..filterQuality = FilterQuality.medium
            ..isAntiAlias = true,
        );
      case TextLayer l:
        final t = l.props.transform;
        TextLayoutCache.instance.paint(
          canvas,
          l,
          pixelScale * math.max(t.scaleX.abs(), t.scaleY.abs()),
        );
      case IconLayer l:
        final path = iconPath(l);
        final b = path.getBounds();
        canvas.drawPath(path, l.fill.applyTo(Paint()..isAntiAlias = true, b));
        if (l.strokeWidth > 0) {
          canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = l.strokeWidth
              ..strokeJoin = StrokeJoin.round
              ..color = l.strokeColor
              ..isAntiAlias = true,
          );
        }
      case PathLayer l:
        paintPathLayer(canvas, l);
      case DrawingLayer l:
        paintDrawing(canvas, l);
      case ShapeLayer l:
        final path = buildShapePath(l);
        final bounds = path.getBounds();
        canvas.drawPath(
          path,
          l.fill.applyTo(Paint()..isAntiAlias = true, bounds),
        );
        if (l.strokeWidth > 0) {
          canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = l.strokeWidth
              ..strokeJoin = StrokeJoin.round
              ..color = l.strokeColor
              ..isAntiAlias = true,
          );
        }
    }
  }

  /// Renders [doc] to an image at [scale] (1 = document pixels), optionally
  /// capped so the longest side is at most [maxSide]. A [matte] color is
  /// painted underneath (needed for formats without alpha, like JPEG).
  Future<ui.Image> renderImage(
    PixDocument doc, {
    double scale = 1,
    double? maxSide,
    Color? matte,
    int? width,
    int? height,
  }) async {
    await assets.decodeAll(doc.referencedAssets);
    final longest = math.max(doc.width, doc.height);
    var s = scale;
    if (maxSide != null) s = math.min(s, maxSide / longest);
    final w = width ?? math.max(1, (doc.width * s).round());
    final h = height ?? math.max(1, (doc.height * s).round());
    await prepareStyles(doc.layers, math.max(w / doc.width, h / doc.height));
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    if (matte != null) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
        Paint()..color = matte,
      );
    }
    canvas.scale(w / doc.width, h / doc.height);
    DocumentRenderer(
      assets,
      effects: effects,
      pixelScale: math.max(w / doc.width, h / doc.height),
    ).paint(canvas, doc);
    final picture = recorder.endRecording();
    final image = await picture.toImage(w, h);
    picture.dispose();
    return image;
  }

  Future<Uint8List> renderPng(PixDocument doc, {double? maxSide}) async {
    final img = await renderImage(doc, maxSide: maxSide);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    return data!.buffer.asUint8List();
  }

  /// Renders [layers] (bottom → top, as siblings) into a bitmap covering
  /// their combined bounds including effect spill. Used by merge, flatten
  /// and rasterize. Returns the PNG bytes and where it sits in the document.
  Future<(Uint8List png, Rect bounds)?> rasterize(
    List<Layer> layers, {
    double maxSide = 8192,
  }) async {
    final visible = [
      for (final l in layers)
        if (l.props.visible) l,
    ];
    if (visible.isEmpty) return null;
    await assets.decodeAll({for (final l in visible) ...assetsOf(l)});
    var bounds = unionBounds(visible).inflate(_effectSpill(visible));
    await prepareStyles(
      visible,
      math.min(
        1.0,
        maxSide / math.max(1, math.max(bounds.width, bounds.height)),
      ),
    );
    if (bounds.isEmpty) return null;
    bounds = Rect.fromLTRB(
      bounds.left.floorToDouble(),
      bounds.top.floorToDouble(),
      bounds.right.ceilToDouble(),
      bounds.bottom.ceilToDouble(),
    );
    final scale = math.min(
      1.0,
      maxSide / math.max(bounds.width, bounds.height),
    );
    final w = math.max(1, (bounds.width * scale).round());
    final h = math.max(1, (bounds.height * scale).round());
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(scale)
      ..translate(-bounds.left, -bounds.top);
    paintLayers(canvas, visible);
    final picture = recorder.endRecording();
    final image = await picture.toImage(w, h);
    picture.dispose();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return (data!.buffer.asUint8List(), bounds);
  }

  /// How far effects (blur, shadows, glow) can paint outside layer bounds.
  double _effectSpill(Iterable<Layer> layers) {
    var spill = 0.0;
    for (final l in layers) {
      var own = 0.0;
      for (final e in l.props.effects) {
        if (!e.enabled) continue;
        final def = _fx[e.type];
        if (def == null) continue;
        own = math.max(own, (def.blurSigma?.call(e) ?? 0) * 3);
        final s = def.shadow?.call(e);
        if (s != null) own = math.max(own, s.blur * 1.5 + s.offset.distance);
        if (def.extrude?.call(e) case final x?) {
          own = math.max(own, _extrudeReach(x, layerLocalRect(l), 1) + 2);
        }
        if (e.type == 'bevel') own = math.max(own, BevelParams.of(e).reach);
        if (e.type == 'glow') own = math.max(own, GlowParams.of(e).reach);
        if (e.type == 'satin') {
          final st = SatinSpec.of(e);
          own = math.max(own, st.size * 1.5 + st.distance);
        }
      }
      // Pixel filters spread the layer's pixels (in layer units).
      final filterReach = _ShapeSource.reachOf(this, l);
      if (filterReach > 0) {
        final t = l.props.transform;
        own += filterReach * math.max(t.scaleX.abs(), t.scaleY.abs());
      }
      // Shadows and glows start from the stroke's edge.
      final st = l.props.stroke;
      if (st != null && st.visible) {
        final t = l.props.transform;
        own += st.outside * math.max(t.scaleX.abs(), t.scaleY.abs()) + 2;
      }
      spill = math.max(spill, own);
      if (l is GroupLayer) spill = math.max(spill, _effectSpill(l.children));
    }
    return spill;
  }
}

class _StyleJob {
  _StyleJob(
    this.key,
    this.result, {
    required this.exact,
    required this.effectId,
  });
  final Object key;
  final String effectId;
  final MaskResult? result;
  BevelParams? bevel;
  GlowParams? glow;

  /// Whether [result] is for exactly these settings at full resolution
  /// (not a preview or a previous result).
  final bool exact;
}

/// A layer's shape (content + mask) rendered once into a bitmap in its
/// local space, then drawn ("stamped") as often as effects need it.
class _Stamp {
  _Stamp._(this.image, this.rect);

  static _Stamp of(
    Layer layer,
    void Function(Canvas) shape,
    double pixelScale, {
    double extra = 0,
  }) {
    final t = layer.props.transform;
    final local = layerLocalRect(layer).inflate(4 + extra);
    final layerScale = math.max(t.scaleX.abs(), t.scaleY.abs());
    var rs = pixelScale * layerScale;
    rs = math.min(rs, 4096 / math.max(local.width, local.height));
    rs = math.max(rs, 0.05);
    final w = math.max(1, (local.width * rs).ceil());
    final h = math.max(1, (local.height * rs).ceil());
    final recorder = ui.PictureRecorder();
    final c = Canvas(recorder)
      ..scale(w / local.width, h / local.height)
      ..translate(-local.left, -local.top);
    shape(c);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(w, h);
    picture.dispose();
    return _Stamp._(image, local);
  }

  final ui.Image image;
  final Rect rect;
  static final Paint _paint = Paint()..filterQuality = FilterQuality.medium;

  void draw(Canvas canvas, [Offset offset = Offset.zero, Paint? paint]) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      rect.shift(offset),
      paint ?? _paint,
    );
  }

  /// Pixels per local unit.
  double get _res => image.width / rect.width;

  /// A new stamp of [w]×[h] over [box], drawn by [paint].
  static _Stamp _make(Rect box, double res, void Function(Canvas c) paint) {
    final w = math.max(1, (box.width * res).ceil());
    final h = math.max(1, (box.height * res).ceil());
    final recorder = ui.PictureRecorder();
    final c = Canvas(recorder)
      ..scale(w / box.width, h / box.height)
      ..translate(-box.left, -box.top);
    paint(c);
    final picture = recorder.endRecording();
    final out = picture.toImageSync(w, h);
    picture.dispose();
    return _Stamp._(out, box);
  }

  /// Offsets covering a disk of radius [r] (local units): rings about
  /// every 3 output pixels, up to 48 points each — morphology by stamping.
  static List<Offset> _disk(double r, double res) {
    if (r <= 0) return const [];
    final rings = (r * res / 3).ceil().clamp(1, 6);
    final out = <Offset>[];
    for (var k = 1; k <= rings; k++) {
      final rr = r * k / rings;
      final n = (2 * math.pi * rr * res / 2.5).ceil().clamp(8, 48);
      for (var i = 0; i < n; i++) {
        out.add(Offset.fromDirection(2 * math.pi * i / n, rr));
      }
    }
    return out;
  }

  /// Photoshop's Stroke style from this shape: grow it by the outside
  /// width, take away the shape shrunk by the inside width, and colour
  /// the band with the stroke's fill (laid out over [layerBox] grown by
  /// the outside width).
  _Stamp strokeBand(LayerStroke s, Rect layerBox) {
    final res = _res;
    final outR = s.outside, inR = s.inside;
    final box = rect.inflate(outR + 2);
    // The outside of the shape, for erosion: shape − grow(outside).
    final outside = inR > 0
        ? _make(rect.inflate(inR + 2), res, (c) {
            final b = rect.inflate(inR + 2);
            c.drawRect(b, Paint()..color = const Color(0xFFFFFFFF));
            draw(c, Offset.zero, Paint()..blendMode = BlendMode.dstOut);
          })
        : null;
    final band = _make(box, res, (c) {
      c.saveLayer(box, Paint());
      // Grown shape.
      draw(c);
      for (final o in _disk(outR, res)) {
        draw(c, o);
      }
      // Minus the shrunk shape.
      c.saveLayer(box, Paint()..blendMode = BlendMode.dstOut);
      draw(c);
      if (outside != null) {
        c.saveLayer(box, Paint()..blendMode = BlendMode.dstOut);
        outside.draw(c);
        for (final o in _disk(inR, res)) {
          outside.draw(c, o);
        }
        c.restore();
      }
      c.restore();
      // Colour it.
      c.drawRect(
        box,
        s.fill.applyTo(Paint(), layerBox.inflate(outR))
          ..blendMode = BlendMode.srcIn,
      );
      c.restore();
    });
    outside?.dispose();
    return band;
  }

  void dispose() => image.dispose();
}

/// A layer's own pixels as effects see them: the content, run through the
/// layer's pixel filters (blur, noise…) when it has any. Filtered content
/// is rendered once, at the output resolution, and drawn from a bitmap.
class _ShapeSource {
  _ShapeSource._(
    this._r,
    this._layer,
    this._hidden,
    this._filtered,
    this.reach, {
    this.owned = true,
  });

  /// Whether [dispose] frees the filtered pixels (not when cached).
  final bool owned;

  static _ShapeSource of(DocumentRenderer r, Layer layer, Set<String> hidden) {
    final local = layerLocalRect(layer);
    final filters = _filters(r, layer, local);
    if (filters.isEmpty) return _ShapeSource._(r, layer, hidden, null, 0);
    var reach = 0.0;
    for (final f in filters) {
      reach += f.filter.reach;
    }
    final box = local.inflate(reach + 2);
    if (box.isEmpty || !box.isFinite) {
      return _ShapeSource._(r, layer, hidden, null, 0);
    }
    final t = layer.props.transform;
    final want = r.pixelScale * math.max(t.scaleX.abs(), t.scaleY.abs());
    // Power-of-two resolution buckets, so moving, turning and small
    // scale changes reuse the filtered pixels; capped for speed (lower
    // on screen than for export).
    var rs = math.pow(2, (math.log(math.max(want, 1e-3)) / math.ln2).ceil());
    final cap = r.cache != null ? 2048.0 : 4096.0;
    rs = math.min(rs, cap / math.max(box.width, box.height));
    rs = math.max(rs, 0.05);
    final cacheable = layer is! GroupLayer && hidden.isEmpty;
    final key = cacheable
        ? (
            layer.withProps(
              layer.props.copyWith(
                transform: const LayerTransform(),
                opacity: 1,
                blendMode: PixBlendMode.normal,
                clip: false,
                mask: const [],
                clearStroke: true,
                fillOpacity: 1,
                effects: [
                  for (final e in layer.props.effects)
                    if (e.enabled && r._fx[e.type]?.filter != null) e,
                ],
              ),
            ),
            rs,
            TextLayoutCache.generation,
          )
        : null;
    final hit = key == null ? null : _filteredCache.remove(key);
    if (hit != null) {
      _filteredCache[key!] = hit;
      return _ShapeSource._(r, layer, hidden, hit, reach + 2, owned: false);
    }
    final plain = _Stamp._make(
      box,
      rs.toDouble(),
      (c) => r._paintContent(c, layer, hidden),
    );
    final out = FilterEngine.apply(plain.image, box, filters);
    plain.dispose();
    final stamp = _Stamp._(out, box);
    if (key != null) {
      _filteredCache[key] = stamp;
      // Evicted images are left to the garbage collector: a plan being
      // painted may still hold them.
      while (_filteredCache.length > 6) {
        _filteredCache.remove(_filteredCache.keys.first);
      }
      return _ShapeSource._(r, layer, hidden, stamp, reach + 2, owned: false);
    }
    return _ShapeSource._(r, layer, hidden, stamp, reach + 2);
  }

  /// Recently filtered layer pixels (filters are the slow part).
  static final LinkedHashMap<Object, _Stamp> _filteredCache = LinkedHashMap();

  static List<FilterStep> _filters(DocumentRenderer r, Layer layer, Rect box) =>
      [
        for (final e in layer.props.effects)
          if (e.enabled)
            if (r._fx[e.type]?.filter?.call(e, box) case final f?)
              FilterStep(
                f,
                mode: PixBlendMode
                    .values[e
                        .number('blend', 0)
                        .round()
                        .clamp(0, PixBlendMode.values.length - 1)]
                    .engine,
                opacity: e.number('opacity', 1),
              ),
      ];

  /// How far [layer]'s filters spread its pixels (layer units).
  static double reachOf(DocumentRenderer r, Layer layer) {
    var reach = 0.0;
    for (final f in _filters(r, layer, layerLocalRect(layer))) {
      reach += f.filter.reach;
    }
    return reach == 0 ? 0 : reach + 2;
  }

  final DocumentRenderer _r;
  final Layer _layer;
  final Set<String> _hidden;
  final _Stamp? _filtered;

  /// Extra room the filtered pixels need around the layer box.
  final double reach;

  void draw(Canvas c) {
    final f = _filtered;
    f == null ? _r._paintContent(c, _layer, _hidden) : f.draw(c);
  }

  void dispose() {
    if (owned) _filtered?.dispose();
  }
}

/// One piece of a layer, composited on its own with [mode] and [alpha];
/// the [body] (the layer itself) uses the layer's blend mode.
class _Part {
  _Part(this.mode, this.alpha, this.draw, {this.body = false});
  final BlendMode mode;
  final double alpha;
  final bool body;
  final void Function(Canvas c) draw;
}

/// What a layer draws, ready to paint (see `DocumentRenderer._plan`).
class _LayerPlan {
  _LayerPlan(
    this.parts,
    this.bounds, {
    required this.isolate,
    required this.applyMask,
    required this.onDispose,
  });

  final List<_Part> parts;
  final Rect? bounds;

  /// Painted as one group (groups; Layer Mask Hides Effects).
  final bool isolate;
  final void Function(Canvas c)? applyMask;
  final VoidCallback onDispose;

  void paint(
    Canvas canvas, {
    required BlendMode blend,
    required double opacity,
  }) {
    if (isolate) {
      canvas.saveLayer(
        bounds,
        Paint()
          ..color = Color.fromRGBO(0, 0, 0, opacity.clamp(0.0, 1.0))
          ..blendMode = blend,
      );
      for (final p in parts) {
        _draw(canvas, p, p.body ? BlendMode.srcOver : p.mode, p.alpha);
      }
      applyMask?.call(canvas);
      canvas.restore();
      return;
    }
    for (final p in parts) {
      _draw(canvas, p, p.body ? blend : p.mode, p.alpha * opacity);
    }
  }

  void _draw(Canvas c, _Part p, BlendMode mode, double alpha) {
    if (mode == BlendMode.srcOver && alpha >= 1) {
      p.draw(c);
      return;
    }
    c.saveLayer(
      bounds,
      Paint()
        ..blendMode = mode
        ..color = Color.fromRGBO(0, 0, 0, alpha.clamp(0.0, 1.0)),
    );
    p.draw(c);
    c.restore();
  }

  void dispose() => onDispose();
}

/// Compares by identity (for caching by an immutable object).
class _Identity {
  const _Identity(this.value);
  final Object value;
  @override
  bool operator ==(Object other) =>
      other is _Identity && identical(other.value, value);
  @override
  int get hashCode => identityHashCode(value);
}

/// A mask's earlier strokes, already rendered (see `_maskImage`).
class _MaskBase {
  _MaskBase(this.strokes, this.area, this.res, this.image);
  final List<MaskStroke> strokes;
  final Rect area;
  final double res;
  final ui.Image image;
}

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../assets/asset_store.dart';
import '../effects/effect_registry.dart';
import '../model/blend.dart';
import '../model/document.dart';
import '../model/layer.dart';
import '../model/layer_stroke.dart';
import 'bevel_engine.dart';
import '../model/layer_transform.dart';
import '../model/mask.dart';
import 'brush_paint.dart';
import 'color_matrix.dart';
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
      final hit = _cachedBitmap(layer);
      if (hit != null) {
        final t = props.transform;
        canvas.drawImageRect(
          hit.image,
          Rect.fromLTWH(
            0,
            0,
            hit.image.width.toDouble(),
            hit.image.height.toDouble(),
          ),
          hit.rect.shift(Offset(t.x, t.y)),
          Paint()
            ..color = Color.fromRGBO(0, 0, 0, props.opacity)
            ..blendMode = blend
            ..filterQuality = FilterQuality.medium
            ..isAntiAlias = true,
        );
        return;
      }
    }

    List<double>? matrix;
    var blur = 0.0;
    final shadows = <ShadowSpec>[];
    final inners = <ShadowSpec>[];
    final bevels = <BevelParams>[];
    final extrudes = <ExtrudeSpec>[];
    for (final e in props.effects) {
      if (!e.enabled) continue;
      if (e.type == 'bevel') {
        bevels.add(BevelParams.of(e));
        continue;
      }
      final def = _fx[e.type];
      if (def == null) continue;
      final m = def.colorMatrix?.call(e);
      if (m != null) {
        matrix = matrix == null ? m : ColorMatrix.concat(matrix, m);
      }
      blur += def.blurSigma?.call(e) ?? 0;
      if (def.shadow?.call(e) case final s?) shadows.add(s);
      if (def.inner?.call(e) case final s?) inners.add(s);
      if (def.extrude?.call(e) case final x?) extrudes.add(x);
    }
    if (matrix != null && ColorMatrix.isIdentity(matrix)) matrix = null;

    final isGroup = layer is GroupLayer;
    final local = layerLocalRect(layer);
    final t = props.transform;
    final ms = _minScale(t);
    var margin = blur * 3;
    for (final s in shadows) {
      margin = math.max(margin, s.blur * 3 + s.offset.distance / ms);
    }
    for (final b in bevels) {
      margin = math.max(margin, b.reach + 2);
    }
    for (final x in extrudes) {
      margin = math.max(margin, x.depth / ms + 4);
    }
    final stroke = !isGroup && (props.stroke?.visible ?? false)
        ? props.stroke
        : null;
    // Outer effects start from the stroke's edge.
    if (stroke != null) margin += stroke.outside + 2;
    // Children of a group may carry their own effects, so a group's layer
    // is left unbounded rather than risk clipping them.
    final Rect? layerBounds = isGroup ? null : local.inflate(margin + 2);

    canvas.save();
    t.applyTo(canvas);

    // Groups are always isolated so their blend mode applies to the
    // composite of their children.
    final needsGroup =
        isGroup || props.opacity < 1 || blend != BlendMode.srcOver;
    if (needsGroup) {
      canvas.saveLayer(
        layerBounds,
        Paint()
          ..color = Color.fromRGBO(0, 0, 0, props.opacity)
          ..blendMode = blend,
      );
    }

    // The layer's shape (content with its mask) — what effects derive from.
    void shape(Canvas c) => _paintMasked(c, layer, hidden, layerBounds);

    // Effects redraw the shape many times; stamp one pre-rendered bitmap
    // of it instead (the visible content itself stays vector).
    final passes =
        shadows.length +
        inners.length +
        bevels.length * 4 +
        extrudes.length +
        (stroke == null ? 0 : 8);
    final stamp = !isGroup && passes >= 2
        ? _Stamp.of(layer, shape, pixelScale)
        : null;
    void effectShape(Canvas c) => stamp == null ? shape(c) : stamp.draw(c);

    // The stroke band, coloured, rendered once: exact vector outlines for
    // shapes, icons and flat text; otherwise grown from the layer's pixels.
    final band = stroke == null || stamp == null
        ? null
        : (_vectorBand(layer, stroke, stamp, local) ??
              stamp.strokeBand(stroke, local));

    // Outer effects (shadows, glows) follow the layer and its stroke.
    void outerShape(Canvas c) {
      effectShape(c);
      band?.draw(c);
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

    void silhouette(
      Offset docOffset,
      double blurPx,
      Color color, {
      BlendMode mode = BlendMode.srcOver,
      bool outer = false,
    }) {
      final lo = toLocal(docOffset);
      canvas.saveLayer(
        layerBounds,
        Paint()
          ..blendMode = mode
          ..colorFilter = ColorFilter.mode(color, BlendMode.srcIn)
          ..imageFilter = blurPx > 0
              ? ui.ImageFilter.blur(
                  sigmaX: blurPx / 2,
                  sigmaY: blurPx / 2,
                  tileMode: TileMode.decal,
                )
              : null,
      );
      canvas.translate(lo.dx, lo.dy);
      outer ? outerShape(canvas) : effectShape(canvas);
      canvas.restore();
    }

    for (final s in shadows) {
      silhouette(s.offset, s.blur, s.color, mode: s.blend.engine, outer: true);
    }
    for (final x in extrudes) {
      _paintExtrude(
        canvas,
        x,
        layerBounds,
        toLocal,
        stamp ?? _Stamp.of(layer, shape, pixelScale),
        disposeStamp: stamp == null,
      );
    }
    final hasInner = inners.isNotEmpty;
    // Fill opacity fades the layer's own pixels only. With "Blend interior
    // effects as group" the inner effects fade with them; otherwise they
    // keep full strength, clipped to the unfaded shape (Photoshop).
    final fill = props.fillOpacity.clamp(0.0, 1.0);
    final faded = fill < 1;
    final interiorFades = faded && props.blendInterior;

    void content() {
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

    void innerEffects({required bool clipToShape}) {
      void inner(
        Offset docOffset,
        double blurPx,
        Color color, [
        BlendMode mode = BlendMode.srcOver,
      ]) => _paintInner(
        canvas,
        toLocal(docOffset),
        blurPx,
        color,
        layerBounds ?? local.inflate(4000),
        shape,
        clipToShape: clipToShape,
        mode: mode,
      );
      for (final s in inners) {
        inner(s.offset, s.blur, s.color, s.blend.engine);
      }
    }

    final fadePaint = Paint()..color = Color.fromRGBO(0, 0, 0, fill);
    if (!faded || interiorFades) {
      // Content and inner effects together (faded as one when needed).
      if (faded) canvas.saveLayer(layerBounds, fadePaint);
      if (hasInner) canvas.saveLayer(layerBounds, Paint());
      content();
      if (hasInner) {
        innerEffects(clipToShape: false);
        canvas.restore();
      }
      if (faded) canvas.restore();
    } else {
      canvas.saveLayer(layerBounds, fadePaint);
      content();
      canvas.restore();
      if (hasInner) {
        canvas.saveLayer(layerBounds, Paint());
        innerEffects(clipToShape: true);
        canvas.restore();
      }
    }

    // Stroke on top, with its own opacity and blend mode; Fill opacity
    // does not fade it.
    if (band != null) {
      band.draw(
        canvas,
        Offset.zero,
        Paint()
          ..filterQuality = FilterQuality.medium
          ..blendMode = stroke!.blend.engine
          ..color = Color.fromRGBO(0, 0, 0, stroke.opacity.clamp(0.0, 1.0)),
      );
    }

    // Bevel & Emboss on top: shadow and highlight layers from the bevel
    // engine, each with its own blend mode (computed in the background;
    // the canvas repaints when they are ready).
    for (final job in _bevelJobs(layer, pixelScale, shape, band)) {
      final r = job.result;
      if (r == null) continue;
      final src = Rect.fromLTWH(
        0,
        0,
        r.shadow.width.toDouble(),
        r.shadow.height.toDouble(),
      );
      final q = job.params;
      canvas
        ..drawImageRect(
          r.shadow,
          src,
          r.rect,
          Paint()
            ..filterQuality = FilterQuality.medium
            ..blendMode = q.shadowMode.engine
            ..colorFilter = ColorFilter.mode(
              q.shadow.withValues(alpha: q.shadow.a * q.shadowOpacity),
              BlendMode.srcIn,
            ),
        )
        ..drawImageRect(
          r.highlight,
          src,
          r.rect,
          Paint()
            ..filterQuality = FilterQuality.medium
            ..blendMode = q.highlightMode.engine
            ..colorFilter = ColorFilter.mode(
              q.highlight.withValues(alpha: q.highlight.a * q.highlightOpacity),
              BlendMode.srcIn,
            ),
        );
    }
    band?.dispose();

    if (needsGroup) canvas.restore();
    canvas.restore();
    stamp?.dispose();
  }

  /// The bevels of [layer] with their cache keys, each already computed
  /// or started now (from the layer's shape — or its stroke, for Stroke
  /// Emboss — rendered at the bevel resolution).
  List<_BevelJob> _bevelJobs(
    Layer layer,
    double pixelScale,
    void Function(Canvas) shape,
    _Stamp? band, {
    bool start = true,
  }) {
    final jobs = <_BevelJob>[];
    for (final e in layer.props.effects) {
      if (!e.enabled || e.type != 'bevel') continue;
      final p = BevelParams.of(e);
      if (p.size <= 0) continue;
      final emboss = p.kind == BevelKind.strokeEmboss;
      if (emboss && band == null && start) continue;
      final t = layer.props.transform;
      final box = (emboss && band != null ? band.rect : layerLocalRect(layer))
          .inflate(p.reach + 4);
      if (box.isEmpty || !box.isFinite) continue;
      // Power-of-two resolution buckets; capped for speed.
      var res = 1.0;
      final want = (pixelScale * math.max(t.scaleX.abs(), t.scaleY.abs()))
          .clamp(1 / 16, 8.0);
      while (res < want) {
        res *= 2;
      }
      while (res / 2 >= want) {
        res /= 2;
      }
      // Capped by a box that does not depend on the stroke band being
      // at hand, so every caller agrees on the key.
      final capBox = layerLocalRect(layer)
          .inflate(p.reach + (layer.props.stroke?.outside ?? 0) + 4);
      res = math.min(res, 1536 / math.max(capBox.width, capBox.height));
      final key = (_bevelShape(layer, emboss), p.computeKey, res);
      final cache = BevelCache.instance;
      var result = cache.lookup(key);
      if (result == null && start && !cache.isPending(key)) {
        final w = math.max(1, (box.width * res).ceil());
        final h = math.max(1, (box.height * res).ceil());
        final recorder = ui.PictureRecorder();
        final c = Canvas(recorder)
          ..scale(w / box.width, h / box.height)
          ..translate(-box.left, -box.top);
        if (emboss) {
          band!.draw(c);
        } else {
          shape(c);
        }
        final pic = recorder.endRecording();
        final alpha = pic.toImageSync(w, h);
        pic.dispose();
        unawaited(cache.request(key, alpha, box, res, p));
        result = cache.lookup(key);
      }
      jobs.add(_BevelJob(key, p, result));
    }
    return jobs;
  }

  /// What a bevel's shape depends on: the layer without its placement and
  /// its other effects.
  static Layer _bevelShape(Layer l, bool withStroke) => l.withProps(
    l.props.copyWith(
      transform: const LayerTransform(),
      opacity: 1,
      blendMode: PixBlendMode.normal,
      clip: false,
      effects: const [],
      fillOpacity: 1,
      clearStroke: !withStroke,
    ),
  );

  /// Computes every bevel [layers] need at [pixelScale] (export awaits
  /// this before painting so no bevel is missing).
  Future<void> prepareBevels(Iterable<Layer> layers, double pixelScale) async {
    final waits = <Future<void>>[];
    void walk(Iterable<Layer> list) {
      for (final l in list) {
        if (l is GroupLayer) {
          walk(l.children);
          continue;
        }
        if (!l.props.effects.any((e) => e.enabled && e.type == 'bevel')) {
          continue;
        }
        void shape(Canvas c) => _paintMasked(c, l, const {}, null);
        final stamp = l.props.stroke?.visible ?? false
            ? _Stamp.of(l, shape, pixelScale)
            : null;
        final band = stamp == null
            ? null
            : (_vectorBand(l, l.props.stroke!, stamp, layerLocalRect(l)) ??
                  stamp.strokeBand(l.props.stroke!, layerLocalRect(l)));
        for (final job in _bevelJobs(l, pixelScale, shape, band)) {
          waits.add(BevelCache.instance.wait(job.key));
        }
        band?.dispose();
        stamp?.dispose();
      }
    }

    walk(layers);
    await Future.wait(waits);
  }

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
      final d = _fx[e.type];
      if (d == null) continue;
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

  /// Renders [layer] (at the document origin, full opacity, normal blend)
  /// into a bitmap at the current resolution, or returns the cached one.
  CachedLayer? _cachedBitmap(Layer layer) {
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
    final key = (base, bucket, TextLayoutCache.generation);
    final hit = cache!.lookup(key);
    if (hit != null) return hit;

    final rect = layerDocumentBounds(base).inflate(_effectSpill([base]) + 4);
    if (rect.isEmpty || !rect.isFinite) return null;
    final longest = math.max(rect.width, rect.height);
    final s = math.min(bucket, 4096 / longest);
    // A bevel still computing: paint directly until it is ready.
    if (layer.props.effects.any((e) => e.enabled && e.type == 'bevel')) {
      final jobs = _bevelJobs(
        layer.withProps(
          layer.props.copyWith(
            transform: layer.props.transform.copyWith(x: 0, y: 0),
          ),
        ),
        s,
        (_) {},
        null,
        start: false,
      );
      if (jobs.any((j) => j.result == null)) return null;
    }
    final w = math.max(1, (rect.width * s).ceil());
    final h = math.max(1, (rect.height * s).ceil());
    final recorder = ui.PictureRecorder();
    final c = Canvas(recorder)
      ..scale(w / rect.width, h / rect.height)
      ..translate(-rect.left, -rect.top);
    DocumentRenderer(
      assets,
      effects: effects,
      pixelScale: s,
    ).paintLayer(c, base);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(w, h);
    picture.dispose();
    final entry = CachedLayer(image, rect, s);
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

  /// 3D extrusion: the shape repeated along the extrusion direction,
  /// shaded in bands from the front colour to a darker back. The shape is
  /// stamped from one bitmap, so deep extrusions stay fast.
  void _paintExtrude(
    Canvas canvas,
    ExtrudeSpec x,
    Rect? bounds,
    Offset Function(Offset) toLocal,
    _Stamp stamp, {
    bool disposeStamp = false,
  }) {
    final steps = x.depth.ceil().clamp(1, 240);
    final dir = Offset(math.cos(x.angle), math.sin(x.angle));
    const bands = 6;
    final hsl = HSLColor.fromColor(x.color);
    for (var band = bands - 1; band >= 0; band--) {
      // band 0 = front, bands-1 = back.
      final k = band / math.max(1, bands - 1);
      final color = hsl
          .withLightness(
            (hsl.lightness * (1 - x.shade * 0.75 * k)).clamp(0.0, 1.0),
          )
          .toColor();
      canvas.saveLayer(
        bounds,
        Paint()..colorFilter = ColorFilter.mode(color, BlendMode.srcIn),
      );
      final from = (steps * band / bands).floor() + 1;
      final to = (steps * (band + 1) / bands).floor();
      for (var i = to; i >= from; i--) {
        stamp.draw(canvas, toLocal(dir * (x.depth * i / steps)));
      }
      canvas.restore();
    }
    if (disposeStamp) stamp.dispose();
  }

  /// Content with the layer mask applied (vector strokes, white = visible).
  void _paintMasked(
    Canvas canvas,
    Layer layer,
    Set<String> hidden,
    Rect? bounds,
  ) {
    final props = layer.props;
    if (!props.hasMask) {
      _paintContent(canvas, layer, hidden);
      return;
    }
    canvas.saveLayer(bounds, Paint());
    _paintContent(canvas, layer, hidden);
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
    final area = (bounds ?? layerLocalRect(layer).inflate(4000)).inflate(
      f * 3 + 2,
    );
    paintMask(canvas, props.mask, area, images: assets.imageOf);
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
    await prepareBevels(doc.layers, math.max(w / doc.width, h / doc.height));
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
    await prepareBevels(
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
          own = math.max(own, x.depth + 2);
        }
        if (e.type == 'bevel') own = math.max(own, BevelParams.of(e).reach);
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

class _BevelJob {
  _BevelJob(this.key, this.params, this.result);
  final Object key;
  final BevelParams params;
  final BevelResult? result;
}

/// A layer's shape (content + mask) rendered once into a bitmap in its
/// local space, then drawn ("stamped") as often as effects need it.
class _Stamp {
  _Stamp._(this.image, this.rect);

  static _Stamp of(
    Layer layer,
    void Function(Canvas) shape,
    double pixelScale,
  ) {
    final t = layer.props.transform;
    final local = layerLocalRect(layer).inflate(4);
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

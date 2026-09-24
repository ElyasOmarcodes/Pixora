import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../assets/asset_store.dart';
import '../effects/effect_registry.dart';
import '../model/document.dart';
import '../model/layer.dart';
import '../model/layer_transform.dart';
import 'color_matrix.dart';
import 'shape_paths.dart';
import 'text_layout.dart';

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
    GroupLayer g => unionBounds(g.children),
  };
}

/// Asset ids used by [layer] and, for groups, its descendants.
Set<String> assetsOf(Layer layer) => switch (layer) {
  RasterLayer l => {l.assetId},
  GroupLayer g => {for (final c in g.children) ...assetsOf(c)},
  _ => const {},
};

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
  const DocumentRenderer(this.assets, {this.effects});

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

    List<double>? matrix;
    var blur = 0.0;
    final shadows = <ShadowSpec>[];
    for (final e in props.effects) {
      if (!e.enabled) continue;
      final def = _fx[e.type];
      if (def == null) continue;
      final m = def.colorMatrix?.call(e);
      if (m != null) {
        matrix = matrix == null ? m : ColorMatrix.concat(matrix, m);
      }
      blur += def.blurSigma?.call(e) ?? 0;
      final s = def.shadow?.call(e);
      if (s != null) shadows.add(s);
    }
    if (matrix != null && ColorMatrix.isIdentity(matrix)) matrix = null;

    final isGroup = layer is GroupLayer;
    final local = layerLocalRect(layer);
    final t = props.transform;
    var margin = blur * 3;
    for (final s in shadows) {
      margin = math.max(margin, s.blur * 3 + s.offset.distance / _minScale(t));
    }
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

    for (final s in shadows) {
      // Shadow offsets are specified in document space; undo the layer's
      // rotation/scale so the shadow always falls the same way.
      final c = math.cos(-t.rotation), sn = math.sin(-t.rotation);
      final o = s.offset;
      final lo = Offset(
        (o.dx * c - o.dy * sn) / (t.scaleX == 0 ? 1 : t.scaleX),
        (o.dx * sn + o.dy * c) / (t.scaleY == 0 ? 1 : t.scaleY),
      );
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
      _paintContent(canvas, layer, hidden);
      canvas.restore();
    }

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
      _paintContent(canvas, layer, hidden);
      canvas.restore();
    } else {
      _paintContent(canvas, layer, hidden);
    }

    if (needsGroup) canvas.restore();
    canvas.restore();
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
        final cache = TextLayoutCache.instance;
        final fill = cache.fill(l);
        final origin = Offset(-fill.width / 2, -fill.height / 2);
        cache.stroke(l)?.paint(canvas, origin);
        fill.paint(canvas, origin);
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
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    if (matte != null) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
        Paint()..color = matte,
      );
    }
    canvas.scale(w / doc.width, h / doc.height);
    paint(canvas, doc);
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
      for (final e in l.props.effects) {
        if (!e.enabled) continue;
        final def = _fx[e.type];
        if (def == null) continue;
        spill = math.max(spill, (def.blurSigma?.call(e) ?? 0) * 3);
        final s = def.shadow?.call(e);
        if (s != null) {
          spill = math.max(spill, s.blur * 1.5 + s.offset.distance);
        }
      }
      if (l is GroupLayer) spill = math.max(spill, _effectSpill(l.children));
    }
    return spill;
  }
}

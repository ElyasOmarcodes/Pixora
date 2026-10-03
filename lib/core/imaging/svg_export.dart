import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../document/model/blend.dart';
import '../../document/model/document.dart';
import '../../document/model/fill.dart';
import '../../document/model/layer.dart';
import '../../document/render/document_renderer.dart';
import '../../document/render/shape_paths.dart';
import '../../document/render/vector_paths.dart';

/// Exports a document as SVG: plain vector layers (shapes, icons, pen
/// paths with solid colours and no effects) become real vector paths that
/// stay sharp at any size; everything else (photos, text, layers with
/// effects, masks or blend modes) is drawn into embedded pictures, runs of
/// neighbouring layers together so they still blend with each other.
abstract final class SvgExport {
  static Future<String> build(
    PixDocument doc,
    DocumentRenderer renderer, {
    double scale = 1,
  }) async {
    final w = doc.width, h = doc.height;
    final b = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln(
        '<svg xmlns="http://www.w3.org/2000/svg" '
        'xmlns:xlink="http://www.w3.org/1999/xlink" '
        'width="${_n(w)}" height="${_n(h)}" viewBox="0 0 ${_n(w)} ${_n(h)}">',
      )
      ..writeln('  <title>${_esc(doc.name)}</title>');
    final bg = doc.background;
    final layers = doc.layers;
    var i = 0;
    // The background: a rectangle when plain, else part of the first
    // picture.
    final plainBg =
        bg == null ||
        (bg.kind == FillKind.solid && doc.backgroundEffects.isEmpty);
    if (bg != null && plainBg) {
      b.writeln(
        '  <rect width="${_n(w)}" height="${_n(h)}" ${_fillAttr(bg.colors.first)}/>',
      );
    }
    var withBg = !plainBg;
    while (i < layers.length) {
      final l = layers[i];
      final next = i + 1 < layers.length ? layers[i + 1] : null;
      if (!l.props.visible || l.props.opacity <= 0) {
        i++;
        continue;
      }
      final vector = _vector(l, clippedBy: next?.props.clip ?? false);
      if (vector != null) {
        b.writeln('  $vector');
        i++;
        continue;
      }
      // A run of layers that need pixels.
      var j = i + 1;
      while (j < layers.length &&
          (layers[j].props.clip ||
              _vector(
                    layers[j],
                    clippedBy:
                        j + 1 < layers.length && layers[j + 1].props.clip,
                  ) ==
                  null)) {
        j++;
      }
      final run = layers.sublist(i, j);
      final png = await _raster(doc, run, renderer, scale, withBg);
      withBg = false;
      if (png != null) {
        final (bounds, bytes) = png;
        b.writeln(
          '  <image x="${_n(bounds.left)}" y="${_n(bounds.top)}" '
          'width="${_n(bounds.width)}" height="${_n(bounds.height)}" '
          'preserveAspectRatio="none" '
          'xlink:href="data:image/png;base64,${base64Encode(bytes)}"/>',
        );
      }
      i = j;
    }
    b.writeln('</svg>');
    return b.toString();
  }

  static String _n(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(3);

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static String _hex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  static String _fillAttr(Color c) =>
      'fill="${_hex(c)}"${c.a < 1 ? ' fill-opacity="${c.a.toStringAsFixed(3)}"' : ''}';

  /// The layer as an SVG element, or null when it needs pixels.
  static String? _vector(Layer l, {required bool clippedBy}) {
    final p = l.props;
    if (clippedBy ||
        p.clip ||
        p.hasMask ||
        p.blendMode != PixBlendMode.normal ||
        p.effects.any((e) => e.enabled) ||
        (p.stroke?.visible ?? false) ||
        p.transform.hasTilt ||
        p.fillOpacity < 1) {
      return null;
    }
    Path path;
    String paint;
    switch (l) {
      case ShapeLayer s when s.fill.kind == FillKind.solid:
        path = buildShapePath(s);
        paint = _fillAttr(s.fill.colors.first);
      case IconLayer ic when ic.fill.kind == FillKind.solid:
        if (ic.strokeWidth > 0) return null;
        path = iconPath(ic);
        paint = _fillAttr(ic.fill.colors.first);
      case PathLayer pl:
        if (pl.startHead != ArrowHead.none ||
            pl.endHead != ArrowHead.none ||
            pl.dash != DashStyle.solid ||
            pl.profile != WidthProfile.uniform ||
            pl.align != StrokeAlign.center ||
            (pl.fill != null && pl.fill!.kind != FillKind.solid)) {
          return null;
        }
        path = pathLayerPath(pl);
        final fill = pl.fill;
        paint =
            '${fill == null ? 'fill="none"' : _fillAttr(fill.colors.first)}'
            '${pl.strokeWidth > 0 ? ' stroke="${_hex(pl.strokeColor)}" stroke-width="${_n(pl.strokeWidth)}"'
                      ' stroke-linecap="${pl.cap.name}" stroke-linejoin="${pl.join.name}"'
                      '${pl.join == StrokeJoin.miter ? ' stroke-miterlimit="${_n(pl.miterLimit)}"' : ''}'
                      '${pl.strokeColor.a < 1 ? ' stroke-opacity="${pl.strokeColor.a.toStringAsFixed(3)}"' : ''}' : ''}';
      default:
        return null;
    }
    final t = p.transform;
    final scale = math.max(t.scaleX.abs(), t.scaleY.abs());
    final d = _pathData(path, 0.5 / math.max(scale, 1e-3));
    if (d.isEmpty) return null;
    final rule = path.fillType == PathFillType.evenOdd
        ? ' fill-rule="evenodd"'
        : '';
    final opacity = p.opacity < 1
        ? ' opacity="${p.opacity.toStringAsFixed(3)}"'
        : '';
    return '<path d="$d" $paint$rule$opacity '
        'transform="translate(${_n(t.x)} ${_n(t.y)}) '
        'rotate(${_n(t.rotation * 180 / math.pi)}) '
        'scale(${_n(t.scaleX)} ${_n(t.scaleY)})"/>';
  }

  /// A path as SVG path data, curves flattened finely ([step] local units
  /// between points).
  static String _pathData(Path path, double step) {
    final b = StringBuffer();
    for (final m in path.computeMetrics()) {
      final n = math.max(2, (m.length / step).ceil());
      for (var k = 0; k <= n; k++) {
        final pos = m.getTangentForOffset(m.length * k / n)?.position;
        if (pos == null) continue;
        b.write(k == 0 ? 'M' : 'L');
        b.write('${_n2(pos.dx)} ${_n2(pos.dy)} ');
      }
      if (m.isClosed) b.write('Z ');
    }
    return b.toString().trim();
  }

  static String _n2(double v) => (v * 100).round() / 100 == v.roundToDouble()
      ? v.round().toString()
      : ((v * 100).round() / 100).toString();

  /// [run] (and the background, when [withBg]) drawn over the area it
  /// covers, as PNG.
  static Future<(Rect, List<int>)?> _raster(
    PixDocument doc,
    List<Layer> run,
    DocumentRenderer renderer,
    double scale,
    bool withBg,
  ) async {
    Rect? area;
    for (final l in run) {
      final r = layerDocumentBounds(l).inflate(64);
      area = area == null ? r : area.expandToInclude(r);
    }
    if (withBg || area == null) area = doc.bounds;
    area = area.intersect(doc.bounds);
    if (area.isEmpty) return null;
    area = Rect.fromLTRB(
      area.left.floorToDouble(),
      area.top.floorToDouble(),
      area.right.ceilToDouble(),
      area.bottom.ceilToDouble(),
    );
    final pw = math.max(1, (area.width * scale).round());
    final ph = math.max(1, (area.height * scale).round());
    final part = doc.copyWith(
      layers: run,
      clearBackground: !withBg,
      backgroundEffects: withBg ? doc.backgroundEffects : const [],
    );
    final rec = ui.PictureRecorder();
    final c = Canvas(rec)
      ..scale(pw / area.width, ph / area.height)
      ..translate(-area.left, -area.top);
    renderer.paint(c, part);
    final image = rec.endRecording().toImageSync(pw, ph);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) return null;
    return (area, data.buffer.asUint8List());
  }
}

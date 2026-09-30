import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart' show ZLibEncoder;
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;
import 'package:xml/xml.dart';

import '../../document/render/svg_path.dart';

/// Picture formats Pixora reads and writes beyond what the platform's own
/// decoder handles.
abstract final class ImageFormats {
  /// Extensions offered when opening a picture.
  static const openable = [
    'png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp', 'tif', 'tiff', //
    'svg', 'psd', 'tga', 'ico', 'heic', 'heif', 'pnm', 'ppm', 'exr',
  ];

  /// Bytes the image decoder understands: PNG, JPEG, GIF, WebP and BMP
  /// pass through; TIFF, PSD (its composite), TGA, ICO, PNM and EXR are
  /// converted to PNG; SVG is drawn (at up to [svgSize] px on its long
  /// side) into a PNG.
  static Future<Uint8List> normalize(
    String name,
    Uint8List bytes, {
    double svgSize = 2048,
  }) async {
    if (_native(bytes)) return bytes;
    if (_isSvg(bytes)) {
      final png = await SvgRaster.toPng(utf8.decode(bytes), svgSize);
      return png ?? bytes;
    }
    final out = await compute(_convert, (name, bytes));
    return out ?? bytes;
  }

  static bool _starts(Uint8List b, List<int> sig) {
    if (b.length < sig.length) return false;
    for (var i = 0; i < sig.length; i++) {
      if (b[i] != sig[i]) return false;
    }
    return true;
  }

  static bool _native(Uint8List b) =>
      _starts(b, [0x89, 0x50, 0x4E, 0x47]) || // PNG
      _starts(b, [0xFF, 0xD8, 0xFF]) || // JPEG
      _starts(b, [0x47, 0x49, 0x46]) || // GIF
      _starts(b, [0x42, 0x4D]) || // BMP
      (_starts(b, [0x52, 0x49, 0x46, 0x46]) &&
          b.length > 12 &&
          b[8] == 0x57 &&
          b[9] == 0x45) || // WebP
      // HEIC/HEIF/AVIF ('ftyp' box): the platform decodes these.
      (b.length > 12 && b[4] == 0x66 && b[5] == 0x74 && b[6] == 0x79);

  static bool _isSvg(Uint8List b) {
    final head = utf8
        .decode(b.sublist(0, math.min(b.length, 1024)), allowMalformed: true)
        .toLowerCase();
    return head.contains('<svg');
  }

  static Uint8List? _convert((String, Uint8List) job) {
    final (name, bytes) = job;
    final decoded = img.decodeNamedImage(name, bytes) ?? img.decodeImage(bytes);
    if (decoded == null) return null;
    return img.encodePng(decoded);
  }

  // ─────────────────────────────── writing

  /// Encodes straight RGBA pixels as [format] ('webp', 'bmp', 'tiff');
  /// [dpi] is written into BMP and TIFF files.
  static Future<Uint8List> encodeRaster(
    String format,
    Uint8List rgba,
    int w,
    int h, {
    int quality = 90,
    bool lossless = true,
    double dpi = 72,
  }) async {
    // BMP and TIFF are plain copies of the pixels: quick enough to write
    // right here (and far quicker than the general encoder, which froze
    // the web page for seconds on big pictures).
    if (format == 'bmp') return bmp(rgba, w, h, dpi: dpi);
    if (format == 'tiff') return tiff(rgba, w, h, dpi: dpi);
    return compute(_encode, (format, rgba, w, h, quality, lossless));
  }

  static Uint8List _encode((String, Uint8List, int, int, int, bool) job) {
    final (format, rgba, w, h, quality, lossless) = job;
    final raster = img.Image.fromBytes(
      width: w,
      height: h,
      bytes: rgba.buffer,
      bytesOffset: rgba.offsetInBytes,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
    return switch (format) {
      // Effort 1: about four times faster than the default for a slightly
      // bigger file (this is the fallback where the system has no WebP
      // encoder).
      'webp' => img.encodeWebP(
        raster,
        lossless: lossless,
        quality: quality,
        method: 1,
        exact: false,
      ),
      _ => img.encodePng(raster),
    };
  }

  /// A 32-bit BMP (BITMAPV4HEADER with an alpha mask) of straight RGBA
  /// pixels, rows bottom-up as most readers expect.
  static Uint8List bmp(Uint8List rgba, int w, int h, {double dpi = 72}) {
    const header = 14 + 108;
    final size = header + w * h * 4;
    final out = Uint8List(size);
    final b = ByteData.sublistView(out);
    b
      ..setUint8(0, 0x42) // 'BM'
      ..setUint8(1, 0x4D)
      ..setUint32(2, size, Endian.little)
      ..setUint32(10, header, Endian.little)
      ..setUint32(14, 108, Endian.little)
      ..setInt32(18, w, Endian.little)
      ..setInt32(22, h, Endian.little)
      ..setUint16(26, 1, Endian.little)
      ..setUint16(28, 32, Endian.little)
      ..setUint32(30, 3, Endian.little) // BI_BITFIELDS
      ..setUint32(34, w * h * 4, Endian.little);
    final ppm = (dpi / 0.0254).round();
    b
      ..setInt32(38, ppm, Endian.little)
      ..setInt32(42, ppm, Endian.little)
      ..setUint32(54, 0x00FF0000, Endian.little) // red
      ..setUint32(58, 0x0000FF00, Endian.little) // green
      ..setUint32(62, 0x000000FF, Endian.little) // blue
      ..setUint32(66, 0xFF000000, Endian.little) // alpha
      ..setUint32(70, 0x73524742, Endian.little); // 'sRGB'
    // R G B A → B G R A, a row at a time from the bottom.
    final src = ByteData.sublistView(rgba);
    for (var y = 0; y < h; y++) {
      var o = header + (h - 1 - y) * w * 4;
      var i = y * w * 4;
      for (var x = 0; x < w; x++, i += 4, o += 4) {
        final v = src.getUint32(i, Endian.little); // A B G R
        b.setUint32(
          o,
          (v & 0xFF00FF00) | ((v & 0xFF) << 16) | ((v >> 16) & 0xFF),
          Endian.little,
        );
      }
    }
    return out;
  }

  /// An uncompressed baseline TIFF of straight RGBA pixels (alpha as
  /// unassociated extra sample), in strips of about 64 KB.
  static Uint8List tiff(Uint8List rgba, int w, int h, {double dpi = 72}) {
    final rowBytes = w * 4;
    final rowsPerStrip = math.max(1, 65536 ~/ math.max(1, rowBytes));
    final strips = (h + rowsPerStrip - 1) ~/ rowsPerStrip;
    const entries = 14;
    const ifd = 8;
    const ifdSize = 2 + entries * 12 + 4;
    const bps = ifd + ifdSize; // 4 shorts
    const res = bps + 8; // 2 rationals
    const offsets = res + 16;
    final counts = offsets + strips * 4;
    final data = counts + strips * 4;
    final out = Uint8List(data + rowBytes * h);
    final b = ByteData.sublistView(out);
    b
      ..setUint8(0, 0x49) // 'II'
      ..setUint8(1, 0x49)
      ..setUint16(2, 42, Endian.little)
      ..setUint32(4, ifd, Endian.little)
      ..setUint16(ifd, entries, Endian.little);
    var e = ifd + 2;
    void tag(int id, int type, int count, int value) {
      b
        ..setUint16(e, id, Endian.little)
        ..setUint16(e + 2, type, Endian.little)
        ..setUint32(e + 4, count, Endian.little);
      if (type == 3 && count == 1) {
        b.setUint16(e + 8, value, Endian.little);
      } else {
        b.setUint32(e + 8, value, Endian.little);
      }
      e += 12;
    }

    const short = 3, long = 4, rational = 5;
    tag(256, long, 1, w); // width
    tag(257, long, 1, h); // height
    tag(258, short, 4, bps); // bits per sample
    tag(259, short, 1, 1); // no compression
    tag(262, short, 1, 2); // RGB
    tag(273, long, strips, strips == 1 ? data : offsets); // strip offsets
    tag(277, short, 1, 4); // samples per pixel
    tag(278, long, 1, rowsPerStrip);
    tag(279, long, strips, strips == 1 ? rowBytes * h : counts);
    tag(282, rational, 1, res); // x resolution
    tag(283, rational, 1, res + 8); // y resolution
    tag(284, short, 1, 1); // chunky
    tag(296, short, 1, 2); // inches
    tag(338, short, 1, 2); // extra sample: unassociated alpha
    b.setUint32(e, 0, Endian.little); // no next IFD
    for (var k = 0; k < 4; k++) {
      b.setUint16(bps + k * 2, 8, Endian.little);
    }
    final d = (dpi * 100).round();
    for (final at in [res, res + 8]) {
      b
        ..setUint32(at, d, Endian.little)
        ..setUint32(at + 4, 100, Endian.little);
    }
    for (var k = 0; k < strips; k++) {
      final rows = math.min(rowsPerStrip, h - k * rowsPerStrip);
      b
        ..setUint32(
          offsets + k * 4,
          data + k * rowsPerStrip * rowBytes,
          Endian.little,
        )
        ..setUint32(counts + k * 4, rows * rowBytes, Endian.little);
    }
    out.setRange(data, data + rowBytes * h, rgba);
    return out;
  }

  /// A one-page PDF holding the picture at its print size ([dpi]): RGB, or
  /// CMYK for print shops (straight RGB → CMYK with full black
  /// generation). Transparent areas are flattened on white.
  static Future<Uint8List> encodePdf(
    Uint8List rgba,
    int w,
    int h, {
    required double dpi,
    bool cmyk = false,
    String title = 'Pixora',
  }) => compute(_pdf, (rgba, w, h, dpi, cmyk, title));

  static Uint8List _pdf((Uint8List, int, int, double, bool, String) job) {
    final (rgba, w, h, dpi, cmyk, title) = job;
    final comps = cmyk ? 4 : 3;
    final raw = Uint8List(w * h * comps);
    for (var i = 0, o = 0; i < w * h; i++) {
      final a = rgba[i * 4 + 3] / 255;
      // On white.
      final r = rgba[i * 4] / 255 * a + (1 - a);
      final g = rgba[i * 4 + 1] / 255 * a + (1 - a);
      final b = rgba[i * 4 + 2] / 255 * a + (1 - a);
      if (cmyk) {
        final k = 1 - math.max(r, math.max(g, b));
        final d = k >= 1 ? 1.0 : 1 - k;
        raw[o++] = (((1 - r - k) / d) * 255).round().clamp(0, 255);
        raw[o++] = (((1 - g - k) / d) * 255).round().clamp(0, 255);
        raw[o++] = (((1 - b - k) / d) * 255).round().clamp(0, 255);
        raw[o++] = (k * 255).round().clamp(0, 255);
      } else {
        raw[o++] = (r * 255).round();
        raw[o++] = (g * 255).round();
        raw[o++] = (b * 255).round();
      }
    }
    final data = const ZLibEncoder().encodeBytes(raw);
    // Page size in points (1/72 in).
    final pw = w / (dpi <= 0 ? 72 : dpi) * 72;
    final ph = h / (dpi <= 0 ? 72 : dpi) * 72;
    String n(double v) => v.toStringAsFixed(2);
    final content = 'q ${n(pw)} 0 0 ${n(ph)} 0 0 cm /Im0 Do Q';
    final out = BytesBuilder();
    final offsets = <int>[];
    void write(String s) => out.add(latin1.encode(s));
    void obj(int id, String body, [Uint8List? stream]) {
      offsets.add(out.length);
      write('$id 0 obj\n$body');
      if (stream != null) {
        write('\nstream\n');
        out.add(stream);
        write('\nendstream');
      }
      write('\nendobj\n');
    }

    final safeTitle = title.replaceAll(RegExp(r'[()\\]'), '_');
    write('%PDF-1.4\n%\xE2\xE3\xCF\xD3\n');
    obj(1, '<< /Type /Catalog /Pages 2 0 R >>');
    obj(2, '<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
    obj(
      3,
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${n(pw)} ${n(ph)}] '
      '/Resources << /XObject << /Im0 4 0 R >> >> /Contents 5 0 R >>',
    );
    obj(
      4,
      '<< /Type /XObject /Subtype /Image /Width $w /Height $h '
      '/ColorSpace /${cmyk ? 'DeviceCMYK' : 'DeviceRGB'} '
      '/BitsPerComponent 8 /Filter /FlateDecode /Length ${data.length} >>',
      data,
    );
    obj(5, '<< /Length ${content.length} >>', latin1.encode(content));
    obj(6, '<< /Title ($safeTitle) /Producer (Pixora) >>');
    final xref = out.length;
    write('xref\n0 ${offsets.length + 1}\n0000000000 65535 f \n');
    for (final o in offsets) {
      write('${o.toString().padLeft(10, '0')} 00000 n \n');
    }
    write(
      'trailer\n<< /Size ${offsets.length + 1} /Root 1 0 R /Info 6 0 R >>\n'
      'startxref\n$xref\n%%EOF\n',
    );
    return out.toBytes();
  }
}

/// Draws simple SVG files (paths and basic shapes, fills, strokes,
/// opacity, transforms, viewBox) — enough for icons, logos and most
/// exported artwork — so they can be opened as pictures.
abstract final class SvgRaster {
  static Future<Uint8List?> toPng(String source, double longSide) async {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(source);
    } catch (_) {
      return null;
    }
    final svg = doc.rootElement;
    double? len(String? v) =>
        v == null ? null : double.tryParse(v.replaceAll(RegExp('[a-z%]'), ''));
    final vb = svg
        .getAttribute('viewBox')
        ?.trim()
        .split(RegExp(r'[\s,]+'))
        .map(double.tryParse)
        .toList();
    var w = len(svg.getAttribute('width'));
    var h = len(svg.getAttribute('height'));
    Rect view;
    if (vb != null && vb.length == 4 && vb.every((v) => v != null)) {
      view = Rect.fromLTWH(vb[0]!, vb[1]!, vb[2]!, vb[3]!);
      w ??= view.width;
      h ??= view.height;
    } else {
      w ??= 512;
      h ??= 512;
      view = Rect.fromLTWH(0, 0, w, h);
    }
    if (view.width <= 0 || view.height <= 0) return null;
    final k = longSide / math.max(w, h);
    final pw = math.max(1, (w * k).round()), ph = math.max(1, (h * k).round());
    final rec = ui.PictureRecorder();
    final c = Canvas(rec)
      ..scale(pw / view.width, ph / view.height)
      ..translate(-view.left, -view.top);
    _draw(c, svg, const _Style());
    final image = rec.endRecording().toImageSync(pw, ph);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data?.buffer.asUint8List();
  }

  static void _draw(Canvas c, XmlElement el, _Style inherited) {
    final style = inherited.merge(el);
    if (style.hidden) return;
    final name = el.name.local;
    if (name == 'defs' ||
        name == 'title' ||
        name == 'desc' ||
        name == 'metadata' ||
        name == 'clipPath' ||
        name == 'mask' ||
        name == 'linearGradient' ||
        name == 'radialGradient' ||
        name == 'style') {
      return;
    }
    c.save();
    final t = el.getAttribute('transform');
    if (t != null) c.transform(_matrix(t));
    final group = name == 'g' || name == 'svg' || name == 'a';
    if (group && style.opacity < 1) {
      c.saveLayer(
        null,
        Paint()..color = Color.fromRGBO(0, 0, 0, style.opacity),
      );
    }
    if (group) {
      for (final child in el.childElements) {
        _draw(c, child, style.forChildren());
      }
    } else {
      final path = _shape(el);
      if (path != null) {
        path.fillType = style.evenOdd
            ? PathFillType.evenOdd
            : PathFillType.nonZero;
        final a = style.opacity;
        if (style.fill != null) {
          c.drawPath(
            path,
            Paint()
              ..isAntiAlias = true
              ..color = style.fill!.withValues(
                alpha: style.fill!.a * style.fillOpacity * a,
              ),
          );
        }
        if (style.stroke != null && style.strokeWidth > 0) {
          c.drawPath(
            path,
            Paint()
              ..isAntiAlias = true
              ..style = PaintingStyle.stroke
              ..strokeWidth = style.strokeWidth
              ..strokeCap = style.cap
              ..strokeJoin = style.join
              ..color = style.stroke!.withValues(
                alpha: style.stroke!.a * style.strokeOpacity * a,
              ),
          );
        }
      }
    }
    if (group && style.opacity < 1) c.restore();
    c.restore();
  }

  static double _n(XmlElement el, String a, [double f = 0]) =>
      double.tryParse(
        (el.getAttribute(a) ?? '').replaceAll(RegExp('[a-z%]'), ''),
      ) ??
      f;

  static Path? _shape(XmlElement el) {
    switch (el.name.local) {
      case 'path':
        final d = el.getAttribute('d');
        if (d == null) return null;
        try {
          return parseSvgPath(d);
        } catch (_) {
          return null;
        }
      case 'rect':
        final x = _n(el, 'x'), y = _n(el, 'y');
        final w = _n(el, 'width'), h = _n(el, 'height');
        var rx = _n(el, 'rx', -1), ry = _n(el, 'ry', -1);
        if (rx < 0) rx = ry < 0 ? 0 : ry;
        if (ry < 0) ry = rx;
        return Path()
          ..addRRect(RRect.fromRectXY(Rect.fromLTWH(x, y, w, h), rx, ry));
      case 'circle':
        final r = _n(el, 'r');
        return Path()..addOval(
          Rect.fromCircle(
            center: Offset(_n(el, 'cx'), _n(el, 'cy')),
            radius: r,
          ),
        );
      case 'ellipse':
        return Path()..addOval(
          Rect.fromCenter(
            center: Offset(_n(el, 'cx'), _n(el, 'cy')),
            width: _n(el, 'rx') * 2,
            height: _n(el, 'ry') * 2,
          ),
        );
      case 'line':
        return Path()
          ..moveTo(_n(el, 'x1'), _n(el, 'y1'))
          ..lineTo(_n(el, 'x2'), _n(el, 'y2'));
      case 'polyline':
      case 'polygon':
        final v = (el.getAttribute('points') ?? '')
            .trim()
            .split(RegExp(r'[\s,]+'))
            .map(double.tryParse)
            .whereType<double>()
            .toList();
        if (v.length < 4) return null;
        final p = Path()..moveTo(v[0], v[1]);
        for (var i = 2; i + 1 < v.length; i += 2) {
          p.lineTo(v[i], v[i + 1]);
        }
        if (el.name.local == 'polygon') p.close();
        return p;
    }
    return null;
  }

  /// An SVG transform list as a 4×4 column-major matrix.
  static Float64List _matrix(String s) {
    var m = Matrix4Values.identity();
    for (final f in RegExp(r'(\w+)\s*\(([^)]*)\)').allMatches(s)) {
      final args = f
          .group(2)!
          .trim()
          .split(RegExp(r'[\s,]+'))
          .map(double.tryParse)
          .whereType<double>()
          .toList();
      Matrix4Values t;
      switch (f.group(1)) {
        case 'matrix' when args.length == 6:
          t = Matrix4Values(
            args[0],
            args[1],
            args[2],
            args[3],
            args[4],
            args[5],
          );
        case 'translate' when args.isNotEmpty:
          t = Matrix4Values(1, 0, 0, 1, args[0], args.length > 1 ? args[1] : 0);
        case 'scale' when args.isNotEmpty:
          t = Matrix4Values(
            args[0],
            0,
            0,
            args.length > 1 ? args[1] : args[0],
            0,
            0,
          );
        case 'rotate' when args.isNotEmpty:
          final a = args[0] * math.pi / 180;
          final r = Matrix4Values(
            math.cos(a),
            math.sin(a),
            -math.sin(a),
            math.cos(a),
            0,
            0,
          );
          if (args.length == 3) {
            t = Matrix4Values(
              1,
              0,
              0,
              1,
              args[1],
              args[2],
            ).times(r).times(Matrix4Values(1, 0, 0, 1, -args[1], -args[2]));
          } else {
            t = r;
          }
        case 'skewX' when args.isNotEmpty:
          t = Matrix4Values(1, 0, math.tan(args[0] * math.pi / 180), 1, 0, 0);
        case 'skewY' when args.isNotEmpty:
          t = Matrix4Values(1, math.tan(args[0] * math.pi / 180), 0, 1, 0, 0);
        default:
          continue;
      }
      m = m.times(t);
    }
    return m.storage;
  }
}

/// A 2D affine transform (SVG's a b c d e f).
class Matrix4Values {
  const Matrix4Values(this.a, this.b, this.c, this.d, this.e, this.f);
  factory Matrix4Values.identity() => const Matrix4Values(1, 0, 0, 1, 0, 0);
  final double a, b, c, d, e, f;

  Matrix4Values times(Matrix4Values o) => Matrix4Values(
    a * o.a + c * o.b,
    b * o.a + d * o.b,
    a * o.c + c * o.d,
    b * o.c + d * o.d,
    a * o.e + c * o.f + e,
    b * o.e + d * o.f + f,
  );

  Float64List get storage => Float64List.fromList([
    a, b, 0, 0, //
    c, d, 0, 0, //
    0, 0, 1, 0, //
    e, f, 0, 1, //
  ]);
}

/// Inherited SVG presentation attributes.
class _Style {
  const _Style({
    this.fill = const Color(0xFF000000),
    this.stroke,
    this.strokeWidth = 1,
    this.fillOpacity = 1,
    this.strokeOpacity = 1,
    this.opacity = 1,
    this.evenOdd = false,
    this.hidden = false,
    this.cap = StrokeCap.butt,
    this.join = StrokeJoin.miter,
  });
  final Color? fill, stroke;
  final double strokeWidth, fillOpacity, strokeOpacity, opacity;
  final bool evenOdd, hidden;
  final StrokeCap cap;
  final StrokeJoin join;

  /// Group opacity applies once (as a layer), not again to children.
  _Style forChildren() => _Style(
    fill: fill,
    stroke: stroke,
    strokeWidth: strokeWidth,
    fillOpacity: fillOpacity,
    strokeOpacity: strokeOpacity,
    evenOdd: evenOdd,
    cap: cap,
    join: join,
  );

  _Style merge(XmlElement el) {
    final props = <String, String>{};
    for (final a in el.attributes) {
      props[a.name.local] = a.value;
    }
    final css = el.getAttribute('style');
    if (css != null) {
      for (final decl in css.split(';')) {
        final i = decl.indexOf(':');
        if (i > 0) {
          props[decl.substring(0, i).trim()] = decl.substring(i + 1).trim();
        }
      }
    }
    Color? paint(String? v, Color? current) {
      if (v == null) return current;
      if (v == 'none' || v == 'transparent') return null;
      if (v == 'currentColor') return current ?? const Color(0xFF000000);
      if (v.startsWith('url(')) return current ?? const Color(0xFF888888);
      return _color(v) ?? current;
    }

    double num(String? v, double f) => v == null
        ? f
        : (v.endsWith('%')
              ? (double.tryParse(v.substring(0, v.length - 1)) ?? f * 100) / 100
              : double.tryParse(v.replaceAll(RegExp('[a-z]'), '')) ?? f);

    return _Style(
      fill: props.containsKey('fill') ? paint(props['fill'], fill) : fill,
      stroke: props.containsKey('stroke')
          ? paint(props['stroke'], stroke)
          : stroke,
      strokeWidth: num(props['stroke-width'], strokeWidth),
      fillOpacity: num(props['fill-opacity'], fillOpacity),
      strokeOpacity: num(props['stroke-opacity'], strokeOpacity),
      opacity: num(props['opacity'], 1),
      evenOdd: props.containsKey('fill-rule')
          ? props['fill-rule'] == 'evenodd'
          : evenOdd,
      hidden: props['display'] == 'none' || props['visibility'] == 'hidden',
      cap: switch (props['stroke-linecap']) {
        'round' => StrokeCap.round,
        'square' => StrokeCap.square,
        null => cap,
        _ => StrokeCap.butt,
      },
      join: switch (props['stroke-linejoin']) {
        'round' => StrokeJoin.round,
        'bevel' => StrokeJoin.bevel,
        null => join,
        _ => StrokeJoin.miter,
      },
    );
  }

  static const _named = {
    'black': 0xFF000000, 'white': 0xFFFFFFFF, 'red': 0xFFFF0000, //
    'green': 0xFF008000, 'blue': 0xFF0000FF, 'yellow': 0xFFFFFF00,
    'orange': 0xFFFFA500, 'purple': 0xFF800080, 'gray': 0xFF808080,
    'grey': 0xFF808080, 'pink': 0xFFFFC0CB, 'brown': 0xFFA52A2A,
    'cyan': 0xFF00FFFF, 'magenta': 0xFFFF00FF, 'lime': 0xFF00FF00,
    'navy': 0xFF000080, 'teal': 0xFF008080, 'silver': 0xFFC0C0C0,
    'gold': 0xFFFFD700, 'maroon': 0xFF800000, 'olive': 0xFF808000,
  };

  static Color? _color(String v) {
    v = v.trim().toLowerCase();
    if (_named.containsKey(v)) return Color(_named[v]!);
    if (v.startsWith('#')) {
      var hex = v.substring(1);
      if (hex.length == 3 || hex.length == 4) {
        hex = hex.split('').map((c) => '$c$c').join();
      }
      final n = int.tryParse(hex, radix: 16);
      if (n == null) return null;
      if (hex.length == 6) return Color(0xFF000000 | n);
      if (hex.length == 8) {
        // #RRGGBBAA
        return Color(((n & 0xFF) << 24) | (n >> 8));
      }
      return null;
    }
    final m = RegExp(r'rgba?\(([^)]*)\)').firstMatch(v);
    if (m != null) {
      final p = m.group(1)!.split(',').map((s) => s.trim()).toList();
      if (p.length < 3) return null;
      int ch(String s) => s.endsWith('%')
          ? ((double.tryParse(s.substring(0, s.length - 1)) ?? 0) * 2.55)
                .round()
          : (double.tryParse(s) ?? 0).round();
      final a = p.length > 3 ? (double.tryParse(p[3]) ?? 1) : 1.0;
      return Color.fromRGBO(
        ch(p[0]).clamp(0, 255),
        ch(p[1]).clamp(0, 255),
        ch(p[2]).clamp(0, 255),
        a.clamp(0.0, 1.0),
      );
    }
    return null;
  }
}

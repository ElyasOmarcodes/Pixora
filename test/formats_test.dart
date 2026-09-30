import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pixora/core/imaging/image_formats.dart';
import 'package:pixora/core/imaging/svg_export.dart';
import 'package:pixora/document/assets/asset_store.dart';
import 'package:pixora/document/model/document.dart';
import 'package:pixora/document/model/fill.dart';
import 'package:pixora/document/model/layer.dart';
import 'package:pixora/document/model/layer_transform.dart';
import 'package:pixora/document/render/document_renderer.dart';

Uint8List _rgba(int w, int h) {
  final px = Uint8List(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    px[i * 4] = 200;
    px[i * 4 + 1] = 40;
    px[i * 4 + 2] = 90;
    px[i * 4 + 3] = 255;
  }
  return px;
}

void main() {
  test('WebP, BMP and TIFF round-trip through a decoder', () async {
    for (final f in ['webp', 'bmp', 'tiff']) {
      final bytes = await ImageFormats.encodeRaster(f, _rgba(8, 6), 8, 6);
      final back = img.decodeImage(bytes)!;
      expect(back.width, 8, reason: f);
      final p = back.getPixel(3, 3);
      expect(p.r.toInt(), 200, reason: f);
      expect(p.b.toInt(), 90, reason: f);
    }
  });

  test('PDF: one page at print size, RGB or CMYK', () async {
    final rgb = await ImageFormats.encodePdf(
      _rgba(300, 150),
      300,
      150,
      dpi: 300,
    );
    final text = latin1.decode(rgb);
    expect(text.startsWith('%PDF-1.4'), isTrue);
    expect(text, contains('/DeviceRGB'));
    // 300 px at 300 dpi = 1 inch = 72 pt.
    expect(text, contains('/MediaBox [0 0 72.00 36.00]'));
    expect(text.trimRight().endsWith('%%EOF'), isTrue);
    final cmyk = await ImageFormats.encodePdf(
      _rgba(4, 4),
      4,
      4,
      dpi: 72,
      cmyk: true,
    );
    expect(latin1.decode(cmyk), contains('/DeviceCMYK'));
  });

  test('TIFF and SVG open as pictures', () async {
    final tiff = img.encodeTiff(img.Image(width: 5, height: 4));
    final png = await ImageFormats.normalize('a.tif', tiff);
    expect(png.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    const svg =
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">'
        '<rect width="10" height="10" fill="#ff0000"/>'
        '<g transform="translate(5 0)"><path d="M0 0H5V10H0Z" style="fill:#00ff00"/></g>'
        '</svg>';
    final out = await ImageFormats.normalize(
      'a.svg',
      Uint8List.fromList(utf8.encode(svg)),
      svgSize: 100,
    );
    final decoded = img.decodePng(out)!;
    expect(decoded.width, 100);
    expect(decoded.getPixel(20, 50).r.toInt(), 255);
    expect(decoded.getPixel(80, 50).g.toInt(), 255);
  });

  test('SVG export keeps shapes as vectors and embeds the rest', () async {
    final doc = PixDocument(
      name: 'd',
      width: 200,
      height: 100,
      background: PixFill.color(const ui.Color(0xFFFFFFFF)),
      layers: [
        ShapeLayer(
          LayerProps(name: 's', transform: const LayerTransform(x: 50, y: 50)),
          shape: ShapeKind.ellipse,
          width: 80,
          height: 60,
          fill: PixFill.color(const ui.Color(0xFF3366CC)),
        ),
        TextLayer(
          LayerProps(name: 't', transform: const LayerTransform(x: 150, y: 50)),
          text: 'Hi',
          fontSize: 30,
        ),
      ],
    );
    final svg = await SvgExport.build(doc, DocumentRenderer(AssetStore()));
    expect(svg, contains('<rect width="200" height="100" fill="#ffffff"/>'));
    expect(svg, contains('<path d="M'));
    expect(svg, contains('fill="#3366cc"'));
    expect(svg, contains('data:image/png;base64,'));
    expect(svg.trimRight().endsWith('</svg>'), isTrue);
  });

  test('export file name follows a bound text layer', () {
    final text = TextLayer(
      LayerProps(id: 'title', name: 't'),
      text: 'Ghor: Attack / Report\nsecond line',
    );
    final doc = PixDocument(
      name: 'My project',
      width: 10,
      height: 10,
      layers: [text],
    );
    expect(doc.exportFileName, 'My project');
    final bound = doc.copyWith(exportName: 'layer:title');
    expect(bound.exportFileName, 'Ghor_ Attack _ Report');
    final edited = bound.replaceLayer(text.copyWith(text: 'New title'));
    expect(edited.exportFileName, 'New title');
    expect(
      doc.copyWith(exportName: 'Poster final').exportFileName,
      'Poster final',
    );
    // Survives saving.
    expect(PixDocument.fromJson(bound.toJson()).exportName, 'layer:title');
  });
}

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixora/document/assets/asset_store.dart';
import 'package:pixora/document/model/document.dart';
import 'package:pixora/document/model/fill.dart';
import 'package:pixora/document/model/layer.dart';
import 'package:pixora/document/model/layer_transform.dart';
import 'package:pixora/document/model/text_span_style.dart';
import 'package:pixora/document/render/document_renderer.dart';
import 'package:pixora/document/render/text_layout.dart';

const pashto =
    'پښتو د افغانستان او پښتونخوا د خلکو ژبه ده چې په سلګونو کلونو کې یې '
    'بډای ادبیات، شعرونه او کیسې رامنځته کړې دي. خوشحال خان خټک، رحمان بابا '
    'او حمید بابا د دې ژبې نامتو شاعران دي چې شعرونه یې نن هم د خلکو په '
    'ژبو ګرځي. د کتاب لوستل د انسان فکر پراخوي، د ژوند لاره روښانه کوي او '
    'راتلونکي نسل ته د پوهې ډالۍ پرېږدي. ';

const english =
    'Typography is the art and technique of arranging type to make written '
    'language legible, readable and appealing when displayed. Justified text '
    'spreads every line to both edges of the column, so the spacing between '
    'words has to be distributed evenly and carefully. ';

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final bytes = File('assets/fonts/$f').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  await load('Vazirmatn', ['Vazirmatn-Regular.ttf', 'Vazirmatn-Bold.ttf']);
  await load('Noto Naskh Arabic', ['NotoNaskhArabic.ttf']);
  await load('Amiri', ['Amiri-Regular.ttf']);
  await load('Poppins', ['Poppins-Regular.ttf']);
}

TextLayer _text(
  String text,
  PixTextAlign align, {
  String font = 'Vazirmatn',
  double size = 30,
  double width = 700,
  PixKashida kashida = PixKashida.medium,
  double x = 400,
  double y = 300,
}) => TextLayer(
  LayerProps(
    name: 't',
    transform: LayerTransform(x: x, y: y),
  ),
  text: text,
  fontFamily: font,
  fontSize: size,
  fontWeight: 400,
  align: align,
  boxWidth: width,
  lineHeight: 1.6,
  kashida: kashida,
  fill: PixFill.color(const ui.Color(0xFF1B1B1F)),
);

Future<void> _save(String name, List<Layer> layers, double w, double h) async {
  final out = Platform.environment['JUSTIFY_OUT'];
  if (out == null) return;
  final doc = PixDocument(
    name: name,
    width: w,
    height: h,
    layers: [
      ShapeLayer(
        LayerProps(
          name: 'bg',
          transform: LayerTransform(x: w / 2, y: h / 2),
        ),
        shape: ShapeKind.rectangle,
        width: w,
        height: h,
        fill: PixFill.color(const ui.Color(0xFFFFFFFF)),
      ),
      ...layers,
    ],
  );
  final img = await DocumentRenderer(AssetStore()).renderImage(doc);
  final png = await img.toByteData(format: ui.ImageByteFormat.png);
  File('$out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
}

/// Widths of the laid-out lines.
List<double> _widths(TextLayer l) => [
  for (final m in TextLayoutCache.instance.fill(l).computeLineMetrics())
    m.width,
];

void main() {
  setUpAll(_loadFonts);

  test('justified lines reach both edges (RTL with kashida)', () {
    final l = _text(pashto * 3, PixTextAlign.justify);
    final lines = TextLayoutCache.instance.fill(l).computeLineMetrics();
    expect(lines.length, greaterThan(5));
    for (final m in lines.take(lines.length - 1)) {
      if (m.hardBreak) continue;
      expect(m.width, closeTo(700, 1.0));
    }
    // Kashidas went in.
    final shown = TextLayoutCache.instance.fill(l).plainText;
    expect(shown.contains('ـ'), isTrue);
  });

  test('fonts with contextual kashida still line up (Amiri, Naskh)', () {
    for (final f in ['Amiri', 'Noto Naskh Arabic']) {
      final l = _text(
        pashto * 2,
        PixTextAlign.justify,
        font: f,
        kashida: PixKashida.long,
      );
      final lines = TextLayoutCache.instance.fill(l).computeLineMetrics();
      for (final m in lines.take(lines.length - 1)) {
        expect(m.width, closeTo(700, 1.5), reason: f);
      }
    }
  });

  test('empty lines, over-long words and styled spans survive', () {
    final text =
        'Short line\n\n${'x' * 90} tail words here and more words '
        'to wrap around the box edge nicely.\n$pashto';
    final l = _text(text, PixTextAlign.justify, font: 'Poppins').copyWith(
      spans: [
        const TextSpanStyle(start: 0, end: 5, color: ui.Color(0xFFFF0000)),
        TextSpanStyle(
          start: text.length - 40,
          end: text.length - 10,
          fontFamily: 'Amiri',
        ),
      ],
    );
    final p = TextLayoutCache.instance.fill(l);
    final lines = p.computeLineMetrics();
    expect(lines.length, greaterThan(6));
    expect(p.plainText.startsWith('Short line\n\n'), isTrue);
  });

  test('LTR justify widens the spaces only', () {
    final l = _text(english * 3, PixTextAlign.justify, font: 'Poppins');
    final w = _widths(l);
    for (final x in w.take(w.length - 1)) {
      expect(x, closeTo(700, 1.0));
    }
    final shown = TextLayoutCache.instance.fill(l).plainText;
    expect(shown.contains('ـ'), isFalse);
  });

  test('last line modes', () {
    for (final a in [
      PixTextAlign.justify,
      PixTextAlign.justifyCenter,
      PixTextAlign.justifyEnd,
    ]) {
      final w = _widths(_text(english * 2, a, font: 'Poppins'));
      expect(w.last, lessThan(690), reason: a.name);
    }
    final all = _widths(
      _text(english * 2, PixTextAlign.justifyAll, font: 'Poppins'),
    );
    expect(all.last, closeTo(700, 1.0));
  });

  test('no kashida mode still justifies with spaces', () {
    final l = _text(pashto * 2, PixTextAlign.justify, kashida: PixKashida.none);
    final lines = TextLayoutCache.instance.fill(l).computeLineMetrics();
    for (final m in lines.take(lines.length - 1)) {
      expect(m.width, closeTo(700, 1.0));
    }
    expect(TextLayoutCache.instance.fill(l).plainText.contains('ـ'), isFalse);
  });

  test('a huge paragraph lays out fast', () {
    final big = pashto * 60; // ~20 000 characters
    int time(PixTextAlign a, double w) {
      final sw = Stopwatch()..start();
      TextLayoutCache.instance.sizeOf(_text(big, a, size: 24, width: w));
      return sw.elapsedMilliseconds;
    }

    time(PixTextAlign.start, 880); // warm the glyph caches
    time(PixTextAlign.justify, 880);
    var plain = 0, ms = 0;
    for (var i = 0; i < 4; i++) {
      plain += time(PixTextAlign.start, 900.0 + i);
      ms += time(PixTextAlign.justify, 900.0 + i);
    }
    plain ~/= 4;
    ms ~/= 4;
    // ignore: avoid_print
    print('justify ${big.length} chars: $ms ms (plain $plain ms)');
    expect(ms, lessThan(1500));
  });

  test('screenshots', () async {
    await _save(
      'justify_modes_rtl',
      [
        for (final (i, a) in [
          PixTextAlign.justify,
          PixTextAlign.justifyCenter,
          PixTextAlign.justifyEnd,
          PixTextAlign.justifyAll,
        ].indexed)
          _text(
            pashto,
            a,
            size: 26,
            width: 560,
            x: 310 + (i % 2) * 620,
            y: 250 + (i ~/ 2) * 420,
          ),
      ],
      1240,
      900,
    );
    await _save(
      'justify_fonts',
      [
        _text(
          pashto,
          PixTextAlign.justify,
          size: 28,
          width: 560,
          x: 310,
          y: 230,
        ),
        _text(
          pashto,
          PixTextAlign.justify,
          font: 'Noto Naskh Arabic',
          size: 28,
          width: 560,
          x: 930,
          y: 230,
        ),
        _text(
          pashto,
          PixTextAlign.justify,
          font: 'Amiri',
          size: 28,
          width: 560,
          x: 310,
          y: 660,
          kashida: PixKashida.long,
        ),
        _text(
          english * 2,
          PixTextAlign.justify,
          font: 'Poppins',
          size: 22,
          width: 560,
          x: 930,
          y: 660,
        ),
      ],
      1240,
      900,
    );
    await _save(
      'justify_big',
      [
        _text(
          pashto * 8,
          PixTextAlign.justify,
          size: 22,
          width: 1100,
          x: 600,
          y: 600,
        ),
      ],
      1200,
      1200,
    );
  });
}

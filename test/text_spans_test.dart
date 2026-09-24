import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixora/document/model/document.dart';
import 'package:pixora/document/model/layer.dart';
import 'package:pixora/document/model/text_span_style.dart';
import 'package:pixora/document/render/text_layout.dart';
import 'package:pixora/projects/pixora_format.dart';

void main() {
  const red = Color(0xFFFF0000), blue = Color(0xFF0000FF);

  test('apply splits and merges ranges', () {
    var s = TextSpans.apply(const [], 2, 8, fontFamily: 'Amiri');
    expect(s, [const TextSpanStyle(start: 2, end: 8, fontFamily: 'Amiri')]);
    s = TextSpans.apply(s, 5, 10, color: red);
    expect(s, const [
      TextSpanStyle(start: 2, end: 5, fontFamily: 'Amiri'),
      TextSpanStyle(start: 5, end: 8, fontFamily: 'Amiri', color: red),
      TextSpanStyle(start: 8, end: 10, color: red),
    ]);
    s = TextSpans.apply(s, 0, 12, color: blue);
    expect(s.every((x) => x.color == blue), isTrue);
    final cleared = TextSpans.clear(s, 0, 12, font: false);
    expect(cleared, const [
      TextSpanStyle(start: 2, end: 8, fontFamily: 'Amiri'),
    ]);
  });

  test('ranges follow text edits', () {
    const spans = [TextSpanStyle(start: 6, end: 11, color: red)];
    // "hello world" -> "oh hello world": everything shifts by 3.
    final a = TextSpans.adjust(spans, 'hello world', 'oh hello world');
    expect(a.single.start, 9);
    expect(a.single.end, 14);
    // Typing inside the styled word extends it.
    final b = TextSpans.adjust(spans, 'hello world', 'hello worxld');
    expect(b.single.start, 6);
    expect(b.single.end, 12);
    // Deleting the styled word removes the span.
    expect(TextSpans.adjust(spans, 'hello world', 'hello '), isEmpty);
  });

  test('spans render and survive JSON/XML', () {
    final t = TextLayer(
      LayerProps(name: 'T'),
      text: 'Hello world',
      spans: const [
        TextSpanStyle(start: 0, end: 5, fontFamily: 'Amiri', color: red),
      ],
    );
    expect(TextLayoutCache.instance.sizeOf(t).width, greaterThan(0));
    final doc = PixDocument(name: 'x', width: 100, height: 100, layers: [t]);
    expect(PixDocument.fromJson(doc.toJson()), doc);
    final (p, _) = PixoraFormat.decode(PixoraFormat.encode(doc, const {}));
    expect((p.document.layers.single as TextLayer).spans, t.spans);
  });
}

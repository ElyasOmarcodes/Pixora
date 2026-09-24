import 'package:flutter_test/flutter_test.dart';
import 'package:pixora/core/units/units.dart';
import 'package:pixora/document/model/document.dart';
import 'package:pixora/editor/editor_controller.dart';
import 'package:pixora/projects/pixora_format.dart';

void main() {
  test('unit conversions', () {
    expect(MeasureUnit.inch.toPx(2, 300), 600);
    expect(MeasureUnit.cm.toPx(2.54, 300), closeTo(300, 1e-9));
    expect(MeasureUnit.mm.fromPx(300, 300), closeTo(25.4, 1e-9));
    expect(MeasureUnit.pt.toPx(72, 144), 144);
    expect(MeasureUnit.percent.toPx(50, 72, reference: 800), 400);
    expect(MeasureUnit.cm.format(21.0), '21');
    expect(MeasureUnit.cm.format(29.7), '29.7');
  });

  test('document resolution survives JSON/XML and resize', () {
    final doc = PixDocument(name: 'a4', width: 2480, height: 3508, dpi: 300);
    expect(PixDocument.fromJson(doc.toJson()).dpi, 300);
    final (p, _) = PixoraFormat.decode(PixoraFormat.encode(doc, const {}));
    expect(p.document.dpi, 300);
    final e = EditorController(document: doc);
    e.resizeCanvas(1240, 1754, dpi: 150);
    expect(e.document.dpi, 150);
    e.undo();
    expect(e.document.dpi, 300);
  });
}

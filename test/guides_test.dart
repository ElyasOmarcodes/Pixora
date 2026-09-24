import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixora/document/model/document.dart';
import 'package:pixora/document/model/guides.dart';
import 'package:pixora/document/model/layer.dart';
import 'package:pixora/document/render/text_layout.dart';
import 'package:pixora/editor/editor_controller.dart';
import 'package:pixora/editor/tools/grid_tool.dart';
import 'package:pixora/projects/pixora_format.dart';

PixDocument guidedDoc() => PixDocument(
  name: 'Guides',
  width: 1000,
  height: 500,
  guides: CanvasGuides(
    grid: const GridSpec(
      visible: true,
      columns: 4,
      rows: 2,
      rotation: 15,
      color: Color(0xFFFF0000),
      opacity: 0.4,
      xLines: [0.1, 0.5],
    ),
    vertical: [120, 640.5],
    horizontal: [250],
  ),
  layers: [
    TextLayer(
      LayerProps(name: 'T'),
      text: 'Hello wrapping world',
      boxWidth: 120,
    ),
  ],
);

void main() {
  test('guides and text box width survive JSON', () {
    final doc = guidedDoc();
    final back = PixDocument.fromJson(doc.toJson());
    expect(back.guides, doc.guides);
    expect((back.layers.single as TextLayer).boxWidth, 120);
    expect(back, doc);
  });

  test('guides survive the .pixora archive (XML)', () {
    final doc = guidedDoc();
    final (project, _) = PixoraFormat.decode(
      PixoraFormat.encode(doc, const {}),
    );
    expect(project.document.guides, doc.guides);
    expect((project.document.layers.single as TextLayer).boxWidth, 120);
  });

  test('empty guides are not serialised', () {
    final doc = PixDocument(name: 'e', width: 10, height: 10);
    expect(doc.toJson().containsKey('guides'), isFalse);
    expect(PixDocument.fromJson(doc.toJson()).guides.isEmpty, isTrue);
  });

  test('grid lines: even by default, custom after edits', () {
    const g = GridSpec(columns: 4, rows: 3);
    expect(g.verticalLines, [0.25, 0.5, 0.75]);
    expect(g.horizontalLines.length, 2);
    final custom = g.copyWith(xLines: [0.3]);
    expect(custom.isCustom, isTrue);
    expect(custom.copyWith(resetLines: true).isCustom, isFalse);
  });

  test('dragging a guide off the canvas deletes it; remove works', () {
    final doc = guidedDoc();
    const ref = GuideLineRef(GuideLineKind.guideVertical, 0);
    final moved = GuideGeometry.moveTo(doc, ref, const Offset(300, 10));
    expect(moved!.vertical.first, 300);
    expect(GuideGeometry.moveTo(doc, ref, const Offset(-5, 10)), isNull);
    final removed = GuideGeometry.remove(doc, ref);
    expect(removed.vertical, [640.5]);
    const gridRef = GuideLineRef(GuideLineKind.gridVertical, 1);
    expect(GuideGeometry.remove(doc, gridRef).grid.verticalLines, [0.1]);
  });

  test('guides are undoable and scale with the canvas', () {
    final e = EditorController(document: guidedDoc());
    e.updateGuides((g) => g.copyWith(vertical: const []));
    expect(e.document.guides.vertical, isEmpty);
    e.undo();
    expect(e.document.guides.vertical, [120, 640.5]);
    e.resizeCanvas(2000, 1000, scaleContent: true);
    expect(e.document.guides.vertical.first, closeTo(240, 0.01));
  });

  test('a text box width wraps lines and grows height', () {
    final free = TextLayer(LayerProps(name: 'T'), text: 'Hello wrapping world');
    final boxed = free.copyWith(boxWidth: 60);
    final a = TextLayoutCache.instance.fill(free);
    final b = TextLayoutCache.instance.fill(boxed);
    expect(b.width, 60);
    expect(b.height, greaterThan(a.height));
    expect(boxed.copyWith(autoWidth: true).boxWidth, isNull);
  });
}


import 'package:flutter_test/flutter_test.dart';
import 'package:pixora/document/model/document.dart';
import 'package:pixora/document/model/layer.dart';
import 'package:pixora/document/model/layer_geometry.dart';
import 'package:pixora/document/render/document_renderer.dart';
import 'package:pixora/editor/editor_controller.dart';

EditorController newEditor() => EditorController(
  document: PixDocument(name: 'T', width: 1000, height: 800),
);

void main() {
  group('groups', () {
    test('group the selection and ungroup it again', () {
      final e = newEditor();
      final a = e.addShape(ShapeKind.rectangle);
      final b = e.addShape(ShapeKind.ellipse);
      final c = e.addShape(ShapeKind.star);
      e.selectMany([a.id, b.id]);
      final g = e.groupSelected(name: 'G')!;

      expect(e.document.layers.map((l) => l.id), [g.id, c.id]);
      expect(e.document.parentOf(a.id)?.id, g.id);
      expect(
        (e.document.layerById(g.id)! as GroupLayer).children.map((l) => l.id),
        [a.id, b.id],
      );
      expect(e.selectedId, g.id);

      e.ungroup(g.id);
      expect(e.document.layers.map((l) => l.id), [a.id, b.id, c.id]);
      expect(e.selectedIds, [a.id, b.id]);

      e.undo();
      expect(e.document.layerById(g.id), isA<GroupLayer>());
    });

    test('new layers are inserted above the selection inside its group', () {
      final e = newEditor();
      final a = e.addShape(ShapeKind.rectangle);
      e.select(a.id);
      final g = e.groupSelected()!;
      e.select(a.id);
      final t = e.addText('hi');
      expect(e.document.parentOf(t.id)?.id, g.id);
      expect(e.document.indexOf(t.id), 1);
    });

    test('a group cannot be moved into its own descendant', () {
      final e = newEditor();
      final a = e.addShape(ShapeKind.rectangle);
      e.select(a.id);
      final inner = e.groupSelected(name: 'inner')!;
      e.select(inner.id);
      final outer = e.groupSelected(name: 'outer')!;
      final before = e.document;
      e.moveLayer(outer.id, parentId: inner.id, index: 0);
      expect(e.document, before);
    });

    test('moving a group moves its children; bounds follow', () {
      final e = newEditor();
      final a = e.addShape(ShapeKind.rectangle);
      final b = e.addShape(ShapeKind.ellipse);
      e.selectMany([a.id, b.id]);
      final g = e.groupSelected()!;
      final before = layerDocumentBounds(e.document.layerById(g.id)!);
      e.transformLayers([g.id], const Similarity(translate: Offset(50, -20)));
      final after = layerDocumentBounds(e.document.layerById(g.id)!);
      expect(after.left, closeTo(before.left + 50, 1e-6));
      expect(after.top, closeTo(before.top - 20, 1e-6));
      expect(e.document.layerById(g.id)!.props.transform.x, 0);
    });

    test('hit testing picks leaves inside groups and honours group lock', () {
      final e = newEditor();
      final a = e.addShape(ShapeKind.rectangle);
      e.select(a.id);
      final g = e.groupSelected()!;
      expect(e.layerAt(e.document.center)?.id, a.id);
      e.toggleLocked(g.id);
      expect(e.layerAt(e.document.center), isNull);
      expect(e.document.isEffectivelyLocked(a.id), isTrue);
    });
  });

  group('multi-selection', () {
    test('toggle, select all, topLevelSelection', () {
      final e = newEditor();
      final a = e.addShape(ShapeKind.rectangle);
      final b = e.addShape(ShapeKind.ellipse);
      e.select(a.id);
      e.toggleSelect(b.id);
      expect(e.selectedIds, [a.id, b.id]);
      expect(e.selectedId, b.id);
      e.toggleSelect(a.id);
      expect(e.selectedIds, [b.id]);
      e.selectAll();
      expect(e.selectedIds.length, 2);

      e.selectMany([a.id, b.id]);
      final g = e.groupSelected()!;
      e.selectMany([g.id, a.id]);
      expect(e.topLevelSelection, [g.id]);
    });

    test('duplicate and delete several layers in one step', () {
      final e = newEditor();
      final a = e.addShape(ShapeKind.rectangle);
      final b = e.addShape(ShapeKind.ellipse);
      e.selectMany([a.id, b.id]);
      final steps = e.history.length;
      e.duplicateSelected();
      expect(e.document.layers.length, 4);
      expect(e.history.length, steps + 1);
      e.deleteSelected();
      expect(e.document.layers.map((l) => l.id), [a.id, b.id]);
    });

    test('align several layers to their combined bounds', () {
      final e = newEditor();
      final a = e.addShape(ShapeKind.rectangle);
      final b = e.addShape(ShapeKind.ellipse);
      e.transformLayers([b.id], const Similarity(translate: Offset(120, 0)));
      e.alignLayers([a.id, b.id], LayerAlign.left);
      final la = layerDocumentBounds(e.document.layerById(a.id)!);
      final lb = layerDocumentBounds(e.document.layerById(b.id)!);
      expect(la.left, closeTo(lb.left, 1e-6));
    });
  });

  group('clipping & visibility', () {
    test('toggle clip is undoable and serialised', () {
      final e = newEditor();
      e.addShape(ShapeKind.rectangle);
      final top = e.addShape(ShapeKind.ellipse);
      e.toggleClip(top.id);
      expect(e.document.layerById(top.id)!.props.clip, isTrue);
      final back = PixDocument.fromJson(e.document.toJson());
      expect(back.layerById(top.id)!.props.clip, isTrue);
      e.undo();
      expect(e.document.layerById(top.id)!.props.clip, isFalse);
    });

    test('show only this, then show all', () {
      final e = newEditor();
      final a = e.addShape(ShapeKind.rectangle);
      final b = e.addShape(ShapeKind.ellipse);
      e.soloVisible(a.id);
      expect(e.document.layerById(b.id)!.props.visible, isFalse);
      e.soloVisible(a.id);
      expect(e.document.layerById(b.id)!.props.visible, isTrue);
    });
  });

  testWidgets('merge down produces one raster layer with the right bounds', (
    tester,
  ) async {
    final e = newEditor();
    final a = e.addShape(ShapeKind.rectangle);
    final b = e.addShape(ShapeKind.ellipse);
    e.transformLayers([b.id], const Similarity(translate: Offset(100, 0)));
    final expected = unionBounds([
      e.document.layerById(a.id)!,
      e.document.layerById(b.id)!,
    ]);

    final merged = await tester.runAsync(() => e.mergeDown(b.id));
    expect(merged, isNotNull);
    expect(e.document.layers.single, isA<RasterLayer>());
    final r = layerDocumentBounds(e.document.layers.single);
    expect(r.width, closeTo(expected.width.ceilToDouble(), 2));
    expect(r.center.dx, closeTo(expected.center.dx, 1.5));
    expect(
      e.assets.contains((e.document.layers.single as RasterLayer).assetId),
      isTrue,
    );
  });
}

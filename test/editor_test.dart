import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixora/document/model/document.dart';
import 'package:pixora/document/model/fill.dart';
import 'package:pixora/document/model/layer.dart';
import 'package:pixora/editor/actions/action_registry.dart';
import 'package:pixora/editor/editor_controller.dart';

EditorController newEditor() => EditorController(
  document: PixDocument(name: 'T', width: 1000, height: 800),
);

void main() {
  group('history', () {
    test('apply, undo and redo', () {
      final e = newEditor();
      final shape = e.addShape(ShapeKind.ellipse);
      expect(e.document.layers.length, 1);
      expect(e.selectedId, shape.id);

      e.undo();
      expect(e.document.layers, isEmpty);
      expect(e.selectedId, isNull);

      e.redo();
      expect(e.document.layers.single.id, shape.id);
      expect(e.selectedId, shape.id);
    });

    test('previews collapse into a single undo step', () {
      final e = newEditor();
      final shape = e.addShape(ShapeKind.rectangle);
      final before = e.history.length;
      for (var i = 1; i <= 10; i++) {
        e.updateProps(
          shape.id,
          (p) => p.copyWith(opacity: 1 - i * 0.05),
          live: true,
        );
      }
      e.commit('opacity');
      expect(e.history.length, before + 1);
      expect(e.selectedLayer!.props.opacity, closeTo(0.5, 1e-9));
      e.undo();
      expect(e.selectedLayer!.props.opacity, 1);
    });

    test('apply during a preview folds the preview in', () {
      final e = newEditor();
      final shape = e.addShape(ShapeKind.rectangle);
      final before = e.history.length;
      e.setBackground(PixFill.color(Colors.red), live: true);
      e.setBackground(PixFill.color(Colors.blue));
      expect(e.history.length, before + 1);
      e.undo();
      expect(e.document.background, isNull);
      expect(e.document.layerById(shape.id), isNotNull);
    });

    test('no-op edits are not recorded', () {
      final e = newEditor();
      final shape = e.addShape(ShapeKind.rectangle);
      final before = e.history.length;
      e.updateProps(shape.id, (p) => p);
      expect(e.history.length, before);
    });
  });

  group('layer commands', () {
    test('duplicate inserts above and selects the copy', () {
      final e = newEditor();
      final a = e.addShape(ShapeKind.rectangle);
      e.addText('top');
      final copy = e.duplicateLayer(a.id)!;
      expect(e.document.indexOf(copy.id), e.document.indexOf(a.id) + 1);
      expect(e.selectedId, copy.id);
    });

    test('arrange to front and back', () {
      final e = newEditor();
      final a = e.addShape(ShapeKind.rectangle);
      e.addShape(ShapeKind.ellipse);
      e.addShape(ShapeKind.star);
      e.arrange(a.id, LayerArrange.front);
      expect(e.document.layers.last.id, a.id);
      e.arrange(a.id, LayerArrange.back);
      expect(e.document.layers.first.id, a.id);
    });

    test('filters are exclusive', () {
      final e = newEditor();
      final a = e.addShape(ShapeKind.rectangle);
      e.applyFilter(a.id, 'mono');
      e.applyFilter(a.id, 'sepia');
      final types = e.selectedLayer!.props.effects.map((x) => x.type);
      expect(types, ['sepia']);
    });

    test('align left puts the bounds at x = 0', () {
      final e = newEditor();
      final a = e.addShape(ShapeKind.rectangle);
      e.align(a.id, LayerAlign.left);
      final l = e.document.layerById(a.id) as ShapeLayer;
      expect(l.props.transform.x, closeTo(l.width / 2, 1e-6));
    });

    test('hit testing ignores hidden and locked layers', () {
      final e = newEditor();
      final a = e.addShape(ShapeKind.rectangle);
      final center = e.document.center;
      expect(e.layerAt(center)?.id, a.id);
      e.toggleLocked(a.id);
      expect(e.layerAt(center), isNull);
      e.toggleLocked(a.id);
      e.toggleVisible(a.id);
      expect(e.layerAt(center), isNull);
    });
  });

  group('actions (automation / AI API)', () {
    test('every action exposes a valid tool schema', () {
      final registry = ActionRegistry();
      for (final schema in registry.toolSchemas()) {
        expect(schema['name'], isA<String>());
        expect((schema['input_schema'] as Map)['type'], 'object');
      }
    });

    test('actions drive the editor', () async {
      final e = newEditor();
      final r = ActionRegistry();
      final added = await r.execute(e, 'layer.add_text', {
        'text': 'سلام',
        'color': '#FF0000',
      });
      expect(added.ok, isTrue);
      final id = added.data as String;

      expect(
        (await r.execute(e, 'layer.set_props', {
          'layer_id': id,
          'opacity': 0.4,
        })).ok,
        isTrue,
      );
      expect(e.document.layerById(id)!.props.opacity, 0.4);

      final fx = await r.execute(e, 'effect.set', {
        'layer_id': id,
        'type': 'shadow',
        'params': {'blur': 30, 'color': '#00FF00'},
      });
      expect(fx.ok, isTrue, reason: fx.error);
      final shadow = e.effectOf(id, 'shadow')!;
      expect(shadow.number('blur', 0), 30);

      final desc = await r.execute(e, 'document.describe', {});
      expect(((desc.data as Map)['layers'] as List).length, 1);

      final bad = await r.execute(e, 'effect.set', {
        'layer_id': id,
        'type': 'nope',
      });
      expect(bad.ok, isFalse);
      expect((await r.execute(e, 'does.not.exist', {})).ok, isFalse);
    });
  });
}

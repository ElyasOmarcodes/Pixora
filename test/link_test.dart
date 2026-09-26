import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixora/document/model/document.dart';
import 'package:pixora/document/model/fill.dart';
import 'package:pixora/document/model/layer.dart';
import 'package:pixora/document/model/layer_transform.dart';
import 'package:pixora/editor/editor_controller.dart';

ShapeLayer box(String id, double x) => ShapeLayer(
  LayerProps(
    id: id,
    name: id,
    transform: LayerTransform(x: x, y: 50),
  ),
  shape: ShapeKind.rectangle,
  width: 20,
  height: 20,
  fill: PixFill.color(const Color(0xFF000000)),
);

void main() {
  EditorController make() => EditorController(
    document: PixDocument(
      name: 't',
      width: 200,
      height: 100,
      layers: [box('a', 20), box('b', 80), box('c', 140)],
    ),
  );

  double x(EditorController e, String id) =>
      e.document.layerById(id)!.props.transform.x;

  test('linked layers move together; unlinked do not', () {
    final e = make();
    e.linkLayers(['a', 'b']);
    expect(e.isLinked('a'), isTrue);
    expect(e.linkedTo('a'), ['b']);
    e.select('a');
    e.nudgeSelection(10, 0);
    expect(x(e, 'a'), 30);
    expect(x(e, 'b'), 90);
    expect(x(e, 'c'), 140);
    e.unlinkLayers(['b']);
    // A set of one dissolves.
    expect(e.isLinked('a'), isFalse);
    expect(e.document.layerById('a')!.props.link, isNull);
    e.nudgeSelection(10, 0);
    expect(x(e, 'b'), 90);
  });

  test('link merges sets, survives save, selects linked', () {
    final e = make();
    e.linkLayers(['a', 'b']);
    e.linkLayers(['b', 'c']);
    expect(e.linkedTo('a').toSet(), {'b', 'c'});
    final json = e.document.toJson();
    final back = PixDocument.fromJson(json);
    expect(
      back.layerById('c')!.props.link,
      e.document.layerById('a')!.props.link,
    );
    e.selectLinked('c');
    expect(e.selectedIds.toSet(), {'a', 'b', 'c'});
    expect(e.selectionIsLinked, isTrue);
    e.toggleLinkSelection();
    expect(e.isLinked('a'), isFalse);
  });

  test('rotating a linked layer turns its partners about the joint centre', () {
    final e = make();
    e.linkLayers(['a', 'c']);
    e.rotateLayers(['a'], 3.141592653589793);
    // a and c swap places around x = 80.
    expect(x(e, 'a'), closeTo(140, 0.01));
    expect(x(e, 'c'), closeTo(20, 0.01));
    expect(x(e, 'b'), 80);
  });
}

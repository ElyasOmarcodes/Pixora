import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixora/document/model/document.dart';
import 'package:pixora/document/model/fill.dart';
import 'package:pixora/document/model/layer.dart';
import 'package:pixora/document/model/layer_transform.dart';
import 'package:pixora/document/model/mask.dart';
import 'package:pixora/document/render/shape_paths.dart';
import 'package:pixora/document/render/svg_path.dart';
import 'package:pixora/editor/tools/pen_tool.dart';
import 'package:pixora/projects/pixora_format.dart';

class _Target implements PenTarget {
  List<PathContour> value = [];
  @override
  LayerTransform get transform => const LayerTransform();
  @override
  List<PathContour> get contours => value;
  @override
  void setContours(List<PathContour> c, {bool live = false}) => value = c;
  @override
  void commit() {}
}

final _tri = PathContour(
  closed: true,
  nodes: [
    const PathNode(Offset(0, 0)),
    const PathNode(
      Offset(100, 0),
      inHandle: Offset(80, -20),
      outHandle: Offset(120, 20),
      type: PathNodeType.symmetric,
    ),
    const PathNode(Offset(50, 80)),
  ],
);

void main() {
  group('svg path parser', () {
    test('absolute, relative, compact numbers and close', () {
      final p = parseSvgPath('M10 10h80v80H10z m20-60l.5.5');
      final b = p.getBounds();
      expect(b.left, closeTo(10, 0.01));
      expect(b.right, closeTo(90, 0.01));
      expect(b.bottom, closeTo(90, 0.01));
    });

    test('curves and arcs stay inside their control boxes', () {
      final p = parseSvgPath(
        'M0 0C0-50 100-50 100 0S200 50 200 0Q250-50 300 0T400 0'
        'A50 50 0 0 1 500 0',
      );
      final b = p.getBounds();
      expect(b.left, closeTo(0, 0.5));
      expect(b.right, closeTo(500, 0.5));
      expect(b.top, lessThan(-30));
    });

    test('a real material symbol parses', () {
      final p = parseSvgPath(
        'M480-120 120-480l360-360 360 360-360 360Zm0-113 247-247-247-247'
        '-247 247 247 247Z',
      );
      final b = p.getBounds();
      expect(b.width, closeTo(720, 1));
      expect(b.height, closeTo(720, 1));
    });

    test('garbage does not throw', () {
      expect(() => parseSvgPath('M 1 x 2 L'), returnsNormally);
    });
  });

  group('path model', () {
    test('node encode / decode', () {
      for (final n in _tri.nodes) {
        expect(PathNode.decode(n.encode()), n);
      }
    });

    test('new layers survive the .pixora XML round trip', () {
      final doc = PixDocument(
        name: 'v',
        width: 500,
        height: 500,
        layers: [
          PathLayer(
            LayerProps(name: 'p'),
            contours: [
              _tri,
              PathContour(nodes: [const PathNode(Offset.zero)]),
            ],
            fill: PixFill.color(const Color(0xFFFF0000)),
            dash: DashStyle.dashDot,
            startHead: ArrowHead.circle,
            endHead: ArrowHead.arrow,
            headSize: 1.5,
            evenOdd: true,
          ),
          IconLayer(
            LayerProps(
              name: 'i',
              mask: [
                MaskStroke(
                  mode: MaskMode.hide,
                  shape: MaskShape.area,
                  points: const [],
                  contour: _tri,
                ),
              ],
            ),
            iconName: 'rocket',
            pathData: 'M0 0h10v10z',
            style: IconStyle.rounded,
            filled: true,
            weight: 700,
          ),
          ShapeLayer(
            LayerProps(name: 's'),
            shape: ShapeKind.gear,
            width: 100,
            height: 100,
            sides: 12,
            params: const {'depth': 0.3, 'hole': 0.25},
          ),
        ],
      );
      final (back, _) = PixoraFormat.documentFromXml(
        PixoraFormat.documentToXml(doc),
      );
      final p = back.layers[0] as PathLayer;
      expect(p.contours.first, _tri);
      expect(p.contours.length, 2);
      expect(p.dash, DashStyle.dashDot);
      expect(p.startHead, ArrowHead.circle);
      expect(p.endHead, ArrowHead.arrow);
      expect(p.headSize, 1.5);
      expect(p.evenOdd, isTrue);
      expect(p.fill, isNotNull);
      final i = back.layers[1] as IconLayer;
      expect(i.iconName, 'rocket');
      expect(i.pathData, 'M0 0h10v10z');
      expect(i.style, IconStyle.rounded);
      expect(i.filled, isTrue);
      expect(i.weight, 700);
      expect(i.props.mask.single.contour, _tri);
      final s = back.layers[2] as ShapeLayer;
      expect(s.shape, ShapeKind.gear);
      expect(s.sides, 12);
      expect(s.param('depth', 0), closeTo(0.3, 1e-9));
      expect(s.param('hole', 0), closeTo(0.25, 1e-9));
    });
  });

  group('shapes', () {
    test('every kind builds a non-empty path', () {
      for (final k in ShapeKind.values) {
        final l = ShapeLayer(
          LayerProps(name: ''),
          shape: k,
          width: 200,
          height: 120,
        );
        final b = buildShapePath(l).getBounds();
        expect(b.width, greaterThan(0), reason: k.name);
      }
    });

    test('a half circle is half as tall', () {
      final full = ShapeLayer(
        LayerProps(name: ''),
        shape: ShapeKind.ellipse,
        width: 100,
        height: 100,
      );
      final half = full.withParam('sweep', 180);
      final b = buildShapePath(half).getBounds();
      expect(b.width * b.height, lessThan(100 * 100 * 0.6));
    });
  });

  group('pen state', () {
    PenState make() {
      final t = _Target()..value = [_tri];
      return PenState()..target = t;
    }

    test('insert, delete and type changes', () {
      final s = make()..node = 0;
      s.insertNode();
      expect(s.activeContour!.nodes.length, 4);
      expect(s.node, 1);
      s.deleteNode();
      expect(s.activeContour!.nodes.length, 3);
      s
        ..node = 2
        ..setNodeType(PathNodeType.smooth);
      expect(s.activeContour!.nodes[2].type, PathNodeType.smooth);
      expect(s.activeContour!.nodes[2].outHandle, isNotNull);
      s.straightenNode();
      expect(s.activeContour!.nodes[2].type, PathNodeType.corner);
    });

    test('splitting a curve keeps its end points', () {
      final s = make()..node = 1;
      s.insertNode();
      final c = s.activeContour!;
      expect(c.nodes[1].point, const Offset(100, 0));
      expect(c.nodes[3].point, const Offset(50, 80));
    });

    test('shape counter: add, duplicate, navigate, delete', () {
      final s = make();
      s.duplicateContour();
      expect(s.target!.contours.length, 2);
      expect(s.active, 1);
      s.previousContour();
      expect(s.active, 0);
      s.addContour();
      expect(s.target!.contours.length, 3);
      s.deleteContour();
      expect(s.target!.contours.length, 2);
      s.toggleClosed();
      expect(s.activeContour!.closed, isFalse);
    });
  });
}

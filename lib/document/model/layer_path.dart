part of 'layer.dart';

/// How a path node treats its two handles.
enum PathNodeType {
  /// Handles move independently (sharp corner).
  corner,

  /// Handles stay in line; lengths may differ.
  smooth,

  /// Handles stay in line with equal length.
  symmetric,
}

/// One anchor of a bezier path with optional handles (absolute positions
/// in layer-local space; null = no handle, a straight segment side).
@immutable
class PathNode {
  const PathNode(
    this.point, {
    this.inHandle,
    this.outHandle,
    this.type = PathNodeType.corner,
  });

  final Offset point;
  final Offset? inHandle;
  final Offset? outHandle;
  final PathNodeType type;

  bool get hasHandles => inHandle != null || outHandle != null;

  PathNode copyWith({
    Offset? point,
    Offset? inHandle,
    Offset? outHandle,
    PathNodeType? type,
    bool clearIn = false,
    bool clearOut = false,
  }) => PathNode(
    point ?? this.point,
    inHandle: clearIn ? null : (inHandle ?? this.inHandle),
    outHandle: clearOut ? null : (outHandle ?? this.outHandle),
    type: type ?? this.type,
  );

  /// Moves the node and its handles together.
  PathNode shifted(Offset d) => PathNode(
    point + d,
    inHandle: inHandle == null ? null : inHandle! + d,
    outHandle: outHandle == null ? null : outHandle! + d,
    type: type,
  );

  PathNode mapped(Offset Function(Offset) f) => PathNode(
    f(point),
    inHandle: inHandle == null ? null : f(inHandle!),
    outHandle: outHandle == null ? null : f(outHandle!),
    type: type,
  );

  static String _n(double v) => ((v * 100).round() / 100).toString();
  static String _p(Offset o) => '${_n(o.dx)},${_n(o.dy)}';

  /// Compact: "x,y|ix,iy|ox,oy|t" (empty handle = no handle).
  String encode() =>
      '${_p(point)}|${inHandle == null ? '' : _p(inHandle!)}|'
      '${outHandle == null ? '' : _p(outHandle!)}|${type.index}';

  static PathNode? decode(String s) {
    final parts = s.split('|');
    Offset? p(String v) {
      final xy = v.split(',');
      if (xy.length != 2) return null;
      final x = double.tryParse(xy[0]), y = double.tryParse(xy[1]);
      return x == null || y == null ? null : Offset(x, y);
    }

    final pt = parts.isEmpty ? null : p(parts[0]);
    if (pt == null) return null;
    return PathNode(
      pt,
      inHandle: parts.length > 1 ? p(parts[1]) : null,
      outHandle: parts.length > 2 ? p(parts[2]) : null,
      type: parts.length > 3
          ? PathNodeType.values[(int.tryParse(parts[3]) ?? 0).clamp(0, 2)]
          : PathNodeType.corner,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PathNode &&
      other.point == point &&
      other.inHandle == inHandle &&
      other.outHandle == outHandle &&
      other.type == type;

  @override
  int get hashCode => Object.hash(point, inHandle, outHandle, type);
}

/// One sub-path (shape) of a [PathLayer].
@immutable
class PathContour {
  PathContour({List<PathNode> nodes = const [], this.closed = false})
    : nodes = List.unmodifiable(nodes);

  final List<PathNode> nodes;
  final bool closed;

  PathContour copyWith({List<PathNode>? nodes, bool? closed}) =>
      PathContour(nodes: nodes ?? this.nodes, closed: closed ?? this.closed);

  Json toJson() => {
    if (closed) 'closed': true,
    'nodes': nodes.map((n) => n.encode()).join(';'),
  };

  static PathContour fromJson(Json m) => PathContour(
    closed: readBool(m['closed']),
    nodes: [
      for (final s in readString(m['nodes']).split(';'))
        if (s.isNotEmpty) ?PathNode.decode(s),
    ],
  );

  @override
  bool operator ==(Object other) =>
      other is PathContour &&
      other.closed == closed &&
      listEquals(other.nodes, nodes);

  @override
  int get hashCode => Object.hash(closed, Object.hashAll(nodes));
}

/// Line end decorations.
enum ArrowHead {
  none,
  arrow,
  triangle,
  circle,
  square,
  diamond,
  bar,

  /// Concave "stealth" arrow.
  stealth,

  /// Outlined triangle and circle.
  openTriangle,
  openCircle,
}

/// Stroke dash patterns; [custom] uses [PathLayer.dashPattern].
enum DashStyle { solid, dashed, dotted, dashDot, custom }

/// Where a closed path's stroke sits on its edge (Illustrator's Align
/// Stroke).
enum StrokeAlign { center, inside, outside }

/// How the stroke's width runs along the path (Illustrator's width
/// profiles).
enum WidthProfile { uniform, taperStart, taperEnd, taperBoth, bulge }

/// A vector drawn with the pen tool or from the vector presets: bezier
/// contours with fill, stroke, dashes and arrowheads — like Illustrator
/// paths.
@immutable
final class PathLayer extends Layer {
  PathLayer(
    super.props, {
    List<PathContour> contours = const [],
    this.fill,
    this.strokeWidth = 8,
    this.strokeColor = const Color(0xFF111827),
    this.cap = StrokeCap.round,
    this.join = StrokeJoin.round,
    this.dash = DashStyle.solid,
    this.dashScale = 1,
    this.startHead = ArrowHead.none,
    this.endHead = ArrowHead.none,
    this.headSize = 1,
    this.evenOdd = false,
    this.miterLimit = 4,
    this.align = StrokeAlign.center,
    this.profile = WidthProfile.uniform,
    this.endHeadSize,
    List<double> dashPattern = const [3, 2],
  }) : contours = List.unmodifiable(contours),
       dashPattern = List.unmodifiable(dashPattern);

  final List<PathContour> contours;

  /// Null = no fill (a line).
  final PixFill? fill;
  final double strokeWidth;
  final Color strokeColor;
  final StrokeCap cap;
  final StrokeJoin join;
  final DashStyle dash;

  /// Multiplies dash and gap lengths.
  final double dashScale;
  final ArrowHead startHead;
  final ArrowHead endHead;

  /// Arrowhead size relative to the stroke width.
  final double headSize;

  /// Even-odd fill rule (holes where contours overlap).
  final bool evenOdd;

  /// How far mitred corners may reach (in stroke widths) before they are
  /// bevelled.
  final double miterLimit;

  /// Stroke position on closed paths.
  final StrokeAlign align;

  /// Width along the path.
  final WidthProfile profile;

  /// Arrowhead size at the end ([headSize] is the start's); null: same.
  final double? endHeadSize;

  /// Custom dashes: dash, gap, dash, gap… in stroke widths.
  final List<double> dashPattern;

  double get endSize => endHeadSize ?? headSize;

  @override
  LayerKind get kind => LayerKind.path;

  @override
  PathLayer withProps(LayerProps props) => copyWith(props: props);

  PathLayer copyWith({
    LayerProps? props,
    List<PathContour>? contours,
    PixFill? fill,
    bool noFill = false,
    double? strokeWidth,
    Color? strokeColor,
    StrokeCap? cap,
    StrokeJoin? join,
    DashStyle? dash,
    double? dashScale,
    ArrowHead? startHead,
    ArrowHead? endHead,
    double? headSize,
    bool? evenOdd,
    double? miterLimit,
    StrokeAlign? align,
    WidthProfile? profile,
    double? endHeadSize,
    List<double>? dashPattern,
  }) => PathLayer(
    props ?? this.props,
    contours: contours ?? this.contours,
    fill: noFill ? null : (fill ?? this.fill),
    strokeWidth: strokeWidth ?? this.strokeWidth,
    strokeColor: strokeColor ?? this.strokeColor,
    cap: cap ?? this.cap,
    join: join ?? this.join,
    dash: dash ?? this.dash,
    dashScale: dashScale ?? this.dashScale,
    startHead: startHead ?? this.startHead,
    endHead: endHead ?? this.endHead,
    headSize: headSize ?? this.headSize,
    evenOdd: evenOdd ?? this.evenOdd,
    miterLimit: miterLimit ?? this.miterLimit,
    align: align ?? this.align,
    profile: profile ?? this.profile,
    endHeadSize: endHeadSize ?? this.endHeadSize,
    dashPattern: dashPattern ?? this.dashPattern,
  );

  /// The same path drawn the other way (Illustrator's Reverse Path
  /// Direction): arrowheads, their sizes and the width profile stay on the
  /// path's start and end, so they move to the other ends.
  PathLayer reversed() => copyWith(
    contours: [
      for (final c in contours)
        c.copyWith(
          nodes: [
            for (final n in c.nodes.reversed)
              PathNode(
                n.point,
                inHandle: n.outHandle,
                outHandle: n.inHandle,
                type: n.type,
              ),
          ],
        ),
    ],
  );

  @override
  Json contentToJson() => {
    'contours': [for (final c in contours) c.toJson()],
    if (fill != null) 'fill': fill!.toJson(),
    'strokeWidth': strokeWidth,
    'strokeColor': writeColor(strokeColor),
    if (cap != StrokeCap.round) 'cap': cap.name,
    if (join != StrokeJoin.round) 'join': join.name,
    if (dash != DashStyle.solid) 'dash': dash.name,
    if (dashScale != 1) 'dashScale': dashScale,
    if (startHead != ArrowHead.none) 'startHead': startHead.name,
    if (endHead != ArrowHead.none) 'endHead': endHead.name,
    if (headSize != 1) 'headSize': headSize,
    if (evenOdd) 'evenOdd': true,
    if (miterLimit != 4) 'miterLimit': miterLimit,
    if (align != StrokeAlign.center) 'align': align.name,
    if (profile != WidthProfile.uniform) 'profile': profile.name,
    if (endHeadSize != null) 'endHeadSize': endHeadSize,
    if (dash == DashStyle.custom) 'dashPattern': dashPattern,
  };

  static PathLayer fromJson(LayerProps props, Json m) => PathLayer(
    props,
    contours: [
      for (final c in readList(m['contours']))
        if (c is Map) PathContour.fromJson(readMap(c)),
    ],
    fill: m['fill'] == null ? null : PixFill.fromJson(m['fill']),
    strokeWidth: readDouble(m['strokeWidth'], 8),
    strokeColor: readColor(m['strokeColor'], const Color(0xFF111827)),
    cap: readEnum(StrokeCap.values, m['cap'], StrokeCap.round),
    join: readEnum(StrokeJoin.values, m['join'], StrokeJoin.round),
    dash: readEnum(DashStyle.values, m['dash'], DashStyle.solid),
    dashScale: readDouble(m['dashScale'], 1),
    startHead: readEnum(ArrowHead.values, m['startHead'], ArrowHead.none),
    endHead: readEnum(ArrowHead.values, m['endHead'], ArrowHead.none),
    headSize: readDouble(m['headSize'], 1),
    evenOdd: readBool(m['evenOdd']),
    miterLimit: readDouble(m['miterLimit'], 4).clamp(1, 50).toDouble(),
    align: readEnum(StrokeAlign.values, m['align'], StrokeAlign.center),
    profile: readEnum(WidthProfile.values, m['profile'], WidthProfile.uniform),
    endHeadSize: m['endHeadSize'] == null
        ? null
        : readDouble(m['endHeadSize'], 1),
    dashPattern: [
      for (final v in readList(m['dashPattern']))
        readDouble(v, 1).clamp(0.0, 100.0).toDouble(),
    ].take(6).toList().let((l) => l.length >= 2 ? l : const [3.0, 2.0]),
  );

  @override
  bool operator ==(Object other) =>
      other is PathLayer &&
      other.props == props &&
      listEquals(other.contours, contours) &&
      other.fill == fill &&
      other.strokeWidth == strokeWidth &&
      other.strokeColor == strokeColor &&
      other.cap == cap &&
      other.join == join &&
      other.dash == dash &&
      other.dashScale == dashScale &&
      other.startHead == startHead &&
      other.endHead == endHead &&
      other.headSize == headSize &&
      other.evenOdd == evenOdd &&
      other.miterLimit == miterLimit &&
      other.align == align &&
      other.profile == profile &&
      other.endHeadSize == endHeadSize &&
      listEquals(other.dashPattern, dashPattern);

  @override
  int get hashCode => Object.hash(
    props,
    Object.hashAll(contours),
    fill,
    strokeWidth,
    strokeColor,
    cap,
    join,
    dash,
    dashScale,
    startHead,
    endHead,
    headSize,
    Object.hash(evenOdd, miterLimit, align, profile, endHeadSize),
    Object.hashAll(dashPattern),
  );
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

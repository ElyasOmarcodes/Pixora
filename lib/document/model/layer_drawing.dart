part of 'layer.dart';

/// Brush tips for freehand drawing.
enum BrushType {
  /// Smooth round ink line.
  pen,

  /// Thin, hard, slightly transparent graphite line.
  pencil,

  /// Flat square tip, even colour even where it overlaps itself.
  marker,

  /// Wide, see-through, multiplies with what is below.
  highlighter,

  /// Very soft airbrush.
  airbrush,

  /// Angled flat nib: thick and thin strokes.
  calligraphy,

  /// Spray paint dots.
  spray,

  /// Glowing tube with a bright core.
  neon,
}

/// One freehand stroke, in the drawing layer's local space.
@immutable
class BrushStroke {
  BrushStroke({
    required List<Offset> points,
    this.type = BrushType.pen,
    this.color = const Color(0xFF111827),
    this.width = 12,
    this.opacity = 1,
    this.softness = 0,
    this.eraser = false,
    this.seed = 0,
  }) : points = List.unmodifiable(points);

  final List<Offset> points;
  final BrushType type;
  final Color color;

  /// Brush diameter in layer pixels.
  final double width;

  /// 0..1 for the whole stroke (overlaps don't darken).
  final double opacity;

  /// Edge softness 0..1 (0 = hard).
  final double softness;

  /// Erases what earlier strokes painted in this layer.
  final bool eraser;

  /// Random seed for spray dots (keeps them stable).
  final int seed;

  BrushStroke copyWith({List<Offset>? points}) => BrushStroke(
    points: points ?? this.points,
    type: type,
    color: color,
    width: width,
    opacity: opacity,
    softness: softness,
    eraser: eraser,
    seed: seed,
  );

  /// Same stroke in another colour (erasers stay erasers).
  BrushStroke recolored(Color c) => eraser
      ? this
      : BrushStroke(
          points: points,
          type: type,
          color: c,
          width: width,
          opacity: opacity,
          softness: softness,
          eraser: eraser,
          seed: seed,
        );

  BrushStroke mapped(Offset Function(Offset) f, double scale) => BrushStroke(
    points: [for (final p in points) f(p)],
    type: type,
    color: color,
    width: width * scale,
    opacity: opacity,
    softness: softness,
    eraser: eraser,
    seed: seed,
  );

  static String _n(double v) => (v * 10).round() / 10 == v.roundToDouble()
      ? v.round().toString()
      : ((v * 10).round() / 10).toString();

  Json toJson() => {
    if (type != BrushType.pen) 't': type.name,
    'c': writeColor(color),
    'w': width,
    if (opacity != 1) 'o': opacity,
    if (softness != 0) 's': softness,
    if (eraser) 'e': true,
    if (seed != 0) 'seed': seed,
    'pts': [for (final p in points) '${_n(p.dx)},${_n(p.dy)}'].join(';'),
  };

  static BrushStroke fromJson(Json m) {
    final pts = <Offset>[];
    for (final pair in readString(m['pts']).split(';')) {
      final xy = pair.split(',');
      if (xy.length != 2) continue;
      final x = double.tryParse(xy[0]), y = double.tryParse(xy[1]);
      if (x != null && y != null) pts.add(Offset(x, y));
    }
    return BrushStroke(
      points: pts,
      type: readEnum(BrushType.values, m['t'], BrushType.pen),
      color: readColor(m['c'], const Color(0xFF111827)),
      width: readDouble(m['w'], 12).clamp(0.2, 5000).toDouble(),
      opacity: readDouble(m['o'], 1).clamp(0.0, 1.0),
      softness: readDouble(m['s']).clamp(0.0, 1.0),
      eraser: readBool(m['e']),
      seed: readDouble(m['seed']).round(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BrushStroke &&
      other.type == type &&
      other.color == color &&
      other.width == width &&
      other.opacity == opacity &&
      other.softness == softness &&
      other.eraser == eraser &&
      other.seed == seed &&
      listEquals(other.points, points);

  @override
  int get hashCode => Object.hash(
    type,
    color,
    width,
    opacity,
    softness,
    eraser,
    seed,
    Object.hashAll(points),
  );
}

/// A freehand drawing: brush strokes that stay editable (draw more, erase,
/// undo stroke by stroke) and sharp at any zoom.
@immutable
final class DrawingLayer extends Layer {
  DrawingLayer(super.props, {List<BrushStroke> strokes = const []})
    : strokes = List.unmodifiable(strokes);

  final List<BrushStroke> strokes;

  @override
  LayerKind get kind => LayerKind.drawing;

  @override
  DrawingLayer withProps(LayerProps props) => copyWith(props: props);

  DrawingLayer copyWith({LayerProps? props, List<BrushStroke>? strokes}) =>
      DrawingLayer(props ?? this.props, strokes: strokes ?? this.strokes);

  @override
  Json contentToJson() => {
    'strokes': [for (final s in strokes) s.toJson()],
  };

  static DrawingLayer fromJson(LayerProps props, Json m) => DrawingLayer(
    props,
    strokes: [
      for (final s in readList(m['strokes']))
        if (s is Map) BrushStroke.fromJson(readMap(s)),
    ],
  );

  @override
  bool operator ==(Object other) =>
      other is DrawingLayer &&
      other.props == props &&
      listEquals(other.strokes, strokes);

  @override
  int get hashCode => Object.hash(props, Object.hashAll(strokes));
}

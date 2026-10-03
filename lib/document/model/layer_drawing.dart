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

  // Tip brushes (Photoshop's Brush Settings): drawn as dabs of a tip
  // shape, with dynamics, scattering, transfer and colour dynamics.

  /// General round brush (hardness, spacing…).
  round,

  /// Inking pen that tapers at both ends and thins with speed.
  ink,

  /// Grainy chalk / pastel.
  chalk,

  /// Soft, see-through washes that build up.
  watercolor,

  /// Evenly spaced round dots.
  dotted,

  /// Scattered stars in shifting colours.
  stars,

  /// Scattered leaves.
  leaves,
}

/// Shapes a brush tip can have.
enum TipShape { round, square, diamond, star, leaf }

/// Photoshop-style brush settings for tip brushes: the tip (shape,
/// hardness, spacing, angle, roundness), shape dynamics, taper,
/// scattering, transfer and colour dynamics. All amounts are 0..1
/// unless noted.
@immutable
class BrushTip {
  const BrushTip({
    this.shape = TipShape.round,
    this.hardness = 1,
    this.spacing = 0.12,
    this.angle = 0,
    this.roundness = 1,
    this.followPath = false,
    this.sizeJitter = 0,
    this.minSize = 0,
    this.angleJitter = 0,
    this.pressureSize = false,
    this.taperStart = 0,
    this.taperEnd = 0,
    this.scatter = 0,
    this.count = 1,
    this.countJitter = 0,
    this.flow = 1,
    this.flowJitter = 0,
    this.pressureOpacity = false,
    this.hueJitter = 0,
    this.saturationJitter = 0,
    this.brightnessJitter = 0,
  });

  final TipShape shape;

  /// Edge: 1 hard … 0 fully soft.
  final double hardness;

  /// Distance between dabs, in diameters (0.02 … 3).
  final double spacing;

  /// Tip angle in degrees; with [followPath], relative to the stroke.
  final double angle;

  /// Height ÷ width of the tip (0.05 … 1).
  final double roundness;
  final bool followPath;

  /// Random size change per dab, and the smallest size it (or pressure,
  /// or taper) may reach.
  final double sizeJitter;
  final double minSize;

  /// Random turn per dab (1 = a full turn).
  final double angleJitter;

  /// Size follows pen pressure (or speed: faster is thinner).
  final bool pressureSize;

  /// How much of the stroke's length tapers in at the start and out at
  /// the end (like Illustrator's width profiles / Procreate's taper).
  final double taperStart, taperEnd;

  /// Spread of dabs away from the line, in diameters (0 … 5).
  final double scatter;

  /// Dabs per step (1 … 16) and its random variation.
  final int count;
  final double countJitter;

  /// Paint per dab, and its random variation (Photoshop's Transfer).
  final double flow;
  final double flowJitter;

  /// Flow follows pen pressure (or speed).
  final bool pressureOpacity;

  /// Random colour changes per dab.
  final double hueJitter, saturationJitter, brightnessJitter;

  BrushTip copyWith({
    TipShape? shape,
    double? hardness,
    double? spacing,
    double? angle,
    double? roundness,
    bool? followPath,
    double? sizeJitter,
    double? minSize,
    double? angleJitter,
    bool? pressureSize,
    double? taperStart,
    double? taperEnd,
    double? scatter,
    int? count,
    double? countJitter,
    double? flow,
    double? flowJitter,
    bool? pressureOpacity,
    double? hueJitter,
    double? saturationJitter,
    double? brightnessJitter,
  }) => BrushTip(
    shape: shape ?? this.shape,
    hardness: hardness ?? this.hardness,
    spacing: spacing ?? this.spacing,
    angle: angle ?? this.angle,
    roundness: roundness ?? this.roundness,
    followPath: followPath ?? this.followPath,
    sizeJitter: sizeJitter ?? this.sizeJitter,
    minSize: minSize ?? this.minSize,
    angleJitter: angleJitter ?? this.angleJitter,
    pressureSize: pressureSize ?? this.pressureSize,
    taperStart: taperStart ?? this.taperStart,
    taperEnd: taperEnd ?? this.taperEnd,
    scatter: scatter ?? this.scatter,
    count: count ?? this.count,
    countJitter: countJitter ?? this.countJitter,
    flow: flow ?? this.flow,
    flowJitter: flowJitter ?? this.flowJitter,
    pressureOpacity: pressureOpacity ?? this.pressureOpacity,
    hueJitter: hueJitter ?? this.hueJitter,
    saturationJitter: saturationJitter ?? this.saturationJitter,
    brightnessJitter: brightnessJitter ?? this.brightnessJitter,
  );

  /// The tip a brush starts with (null: drawn as a plain line).
  static BrushTip? presetFor(BrushType t) => switch (t) {
    BrushType.round => const BrushTip(),
    BrushType.ink => const BrushTip(
      spacing: 0.06,
      pressureSize: true,
      minSize: 0.15,
      taperStart: 0.18,
      taperEnd: 0.25,
    ),
    BrushType.chalk => const BrushTip(
      hardness: 0.6,
      spacing: 0.1,
      sizeJitter: 0.5,
      angleJitter: 1,
      scatter: 0.35,
      count: 3,
      flow: 0.55,
      flowJitter: 0.7,
      roundness: 0.7,
    ),
    BrushType.watercolor => const BrushTip(
      hardness: 0,
      spacing: 0.08,
      sizeJitter: 0.2,
      flow: 0.18,
      flowJitter: 0.3,
      hueJitter: 0.03,
      brightnessJitter: 0.08,
    ),
    BrushType.dotted => const BrushTip(spacing: 1.6),
    BrushType.stars => const BrushTip(
      shape: TipShape.star,
      spacing: 1.1,
      sizeJitter: 0.7,
      minSize: 0.2,
      angleJitter: 1,
      scatter: 1.4,
      count: 2,
      hueJitter: 0.25,
    ),
    BrushType.leaves => const BrushTip(
      shape: TipShape.leaf,
      spacing: 0.9,
      roundness: 0.55,
      sizeJitter: 0.5,
      minSize: 0.25,
      angleJitter: 1,
      scatter: 1,
      count: 2,
      hueJitter: 0.06,
      brightnessJitter: 0.25,
    ),
    _ => null,
  };

  Json toJson() => {
    if (shape != TipShape.round) 'sh': shape.name,
    if (hardness != 1) 'hd': hardness,
    'sp': spacing,
    if (angle != 0) 'an': angle,
    if (roundness != 1) 'rd': roundness,
    if (followPath) 'fp': true,
    if (sizeJitter != 0) 'sj': sizeJitter,
    if (minSize != 0) 'ms': minSize,
    if (angleJitter != 0) 'aj': angleJitter,
    if (pressureSize) 'ps': true,
    if (taperStart != 0) 'ts': taperStart,
    if (taperEnd != 0) 'te': taperEnd,
    if (scatter != 0) 'sc': scatter,
    if (count != 1) 'ct': count,
    if (countJitter != 0) 'cj': countJitter,
    if (flow != 1) 'fl': flow,
    if (flowJitter != 0) 'fj': flowJitter,
    if (pressureOpacity) 'po': true,
    if (hueJitter != 0) 'hj': hueJitter,
    if (saturationJitter != 0) 'sa': saturationJitter,
    if (brightnessJitter != 0) 'bj': brightnessJitter,
  };

  static BrushTip fromJson(Json m) {
    double f(String k, double d, double lo, double hi) =>
        readDouble(m[k], d).clamp(lo, hi).toDouble();
    return BrushTip(
      shape: readEnum(TipShape.values, m['sh'], TipShape.round),
      hardness: f('hd', 1, 0, 1),
      spacing: f('sp', 0.12, 0.02, 3),
      angle: f('an', 0, -360, 360),
      roundness: f('rd', 1, 0.05, 1),
      followPath: readBool(m['fp']),
      sizeJitter: f('sj', 0, 0, 1),
      minSize: f('ms', 0, 0, 1),
      angleJitter: f('aj', 0, 0, 1),
      pressureSize: readBool(m['ps']),
      taperStart: f('ts', 0, 0, 1),
      taperEnd: f('te', 0, 0, 1),
      scatter: f('sc', 0, 0, 5),
      count: readDouble(m['ct'], 1).round().clamp(1, 16),
      countJitter: f('cj', 0, 0, 1),
      flow: f('fl', 1, 0.01, 1),
      flowJitter: f('fj', 0, 0, 1),
      pressureOpacity: readBool(m['po']),
      hueJitter: f('hj', 0, 0, 1),
      saturationJitter: f('sa', 0, 0, 1),
      brightnessJitter: f('bj', 0, 0, 1),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BrushTip && mapEquals(other.toJson(), toJson());

  @override
  int get hashCode => Object.hashAll(toJson().values);
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
    this.tip,
    List<double>? pressures,
  }) : points = List.unmodifiable(points),
       pressures = pressures == null ? null : List.unmodifiable(pressures);

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

  /// Random seed for spray dots and tip dynamics (keeps them stable).
  final int seed;

  /// Tip brush settings; null draws the stroke as a plain line.
  final BrushTip? tip;

  /// Pen pressure (or speed) per point, 0..1; null: full pressure.
  final List<double>? pressures;

  BrushStroke copyWith({List<Offset>? points, List<double>? pressures}) =>
      BrushStroke(
        points: points ?? this.points,
        type: type,
        color: color,
        width: width,
        opacity: opacity,
        softness: softness,
        eraser: eraser,
        seed: seed,
        tip: tip,
        pressures: pressures ?? this.pressures,
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
          tip: tip,
          pressures: pressures,
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
    tip: tip,
    pressures: pressures,
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
    if (tip != null) 'tip': tip!.toJson(),
    if (pressures != null)
      'pr': [for (final v in pressures!) (v * 100).round()].join(','),
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
      tip: m['tip'] is Map ? BrushTip.fromJson(readMap(m['tip'])) : null,
      pressures: m['pr'] is String && pts.isNotEmpty
          ? () {
              final v = [
                for (final x in (m['pr'] as String).split(','))
                  ((int.tryParse(x) ?? 100) / 100).clamp(0.0, 1.0),
              ];
              return v.length == pts.length ? v : null;
            }()
          : null,
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
      other.tip == tip &&
      listEquals(other.pressures, pressures) &&
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
    tip,
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

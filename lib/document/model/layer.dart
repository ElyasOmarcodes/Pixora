import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../core/utils/ids.dart';
import '../../core/utils/json.dart';
import 'blend.dart';
import 'effect.dart';
import 'fill.dart';
import 'layer_stroke.dart';
import 'layer_transform.dart';
import 'mask.dart';
import 'text_span_style.dart';

part 'layer_icon.dart';
part 'layer_path.dart';
part 'layer_drawing.dart';

enum LayerKind { raster, text, shape, group, icon, path, drawing }

/// Properties every layer has, regardless of its kind.
@immutable
class LayerProps {
  LayerProps({
    String? id,
    required this.name,
    this.visible = true,
    this.locked = false,
    this.opacity = 1,
    this.blendMode = PixBlendMode.normal,
    this.transform = const LayerTransform(),
    this.clip = false,
    List<LayerEffect> effects = const [],
    List<MaskStroke> mask = const [],
    this.maskEnabled = true,
    this.maskDensity = 1,
    this.maskFeather = 0,
    this.fillOpacity = 1,
    this.blendInterior = false,
    this.stroke,
  }) : id = id ?? newId('ly'),
       effects = List.unmodifiable(effects),
       mask = List.unmodifiable(mask);

  final String id;
  final String name;
  final bool visible;
  final bool locked;

  /// 0..1
  final double opacity;
  final PixBlendMode blendMode;
  final LayerTransform transform;

  /// Clipping mask: when true the layer only shows where the nearest
  /// non-clipped layer beneath it (its base) has pixels.
  final bool clip;

  /// Applied in order. See `EffectRegistry` for what each type does.
  final List<LayerEffect> effects;

  /// Layer mask as vector strokes (empty = no mask).
  final List<MaskStroke> mask;

  /// Temporarily disable the mask without deleting it.
  final bool maskEnabled;

  /// Photoshop's mask Density: 1 = the mask fully hides, 0 = no effect.
  final double maskDensity;

  /// Photoshop's mask Feather: blur of the whole mask, in layer pixels.
  final double maskFeather;

  /// Photoshop's Fill opacity (0..1): fades only the layer's own pixels;
  /// layer styles (stroke, shadows, glows, bevel) keep their strength.
  final double fillOpacity;

  /// Photoshop's "Blend Interior Effects as Group": inner effects (inner
  /// shadow / glow, inner bevel) fade together with the fill.
  final bool blendInterior;

  /// Stroke layer style (null = none).
  final LayerStroke? stroke;

  /// Whether the layer has a mask at all (it may be disabled).
  bool get hasMaskLayer => mask.isNotEmpty;

  bool get hasMask => mask.isNotEmpty && maskEnabled;

  /// Asset ids of bitmap mask strokes.
  Iterable<String> get maskAssets => [for (final s in mask) ?s.assetId];

  LayerProps copyWith({
    String? id,
    String? name,
    bool? visible,
    bool? locked,
    double? opacity,
    PixBlendMode? blendMode,
    LayerTransform? transform,
    bool? clip,
    List<LayerEffect>? effects,
    List<MaskStroke>? mask,
    bool? maskEnabled,
    double? maskDensity,
    double? maskFeather,
    double? fillOpacity,
    bool? blendInterior,
    LayerStroke? stroke,
    bool clearStroke = false,
  }) => LayerProps(
    id: id ?? this.id,
    name: name ?? this.name,
    visible: visible ?? this.visible,
    locked: locked ?? this.locked,
    opacity: opacity ?? this.opacity,
    blendMode: blendMode ?? this.blendMode,
    transform: transform ?? this.transform,
    clip: clip ?? this.clip,
    effects: effects ?? this.effects,
    mask: mask ?? this.mask,
    maskEnabled: maskEnabled ?? this.maskEnabled,
    maskDensity: maskDensity ?? this.maskDensity,
    maskFeather: maskFeather ?? this.maskFeather,
    fillOpacity: fillOpacity ?? this.fillOpacity,
    blendInterior: blendInterior ?? this.blendInterior,
    stroke: clearStroke ? null : (stroke ?? this.stroke),
  );

  Json toJson() => {
    'id': id,
    'name': name,
    if (!visible) 'visible': false,
    if (locked) 'locked': true,
    if (opacity != 1) 'opacity': opacity,
    if (blendMode != PixBlendMode.normal) 'blend': blendMode.name,
    if (clip) 'clip': true,
    'transform': transform.toJson(),
    if (effects.isNotEmpty) 'effects': [for (final e in effects) e.toJson()],
    if (mask.isNotEmpty) 'mask': [for (final s in mask) s.toJson()],
    if (!maskEnabled) 'maskEnabled': false,
    if (maskDensity != 1) 'maskDensity': maskDensity,
    if (maskFeather != 0) 'maskFeather': maskFeather,
    if (fillOpacity != 1) 'fill': fillOpacity,
    if (blendInterior) 'blendInterior': true,
    if (stroke != null) 'stroke': stroke!.toJson(),
  };

  static LayerProps fromJson(Json m) => LayerProps(
    id: readString(m['id'], newId('ly')),
    name: readString(m['name'], 'Layer'),
    visible: readBool(m['visible'], true),
    locked: readBool(m['locked']),
    opacity: readDouble(m['opacity'], 1).clamp(0.0, 1.0),
    blendMode: readEnum(PixBlendMode.values, m['blend'], PixBlendMode.normal),
    transform: LayerTransform.fromJson(m['transform']),
    clip: readBool(m['clip']),
    effects: [
      for (final e in readList(m['effects']))
        if (e is Map) LayerEffect.fromJson(readMap(e)),
    ],
    mask: [
      for (final s in readList(m['mask']))
        if (s is Map) MaskStroke.fromJson(readMap(s)),
    ],
    maskEnabled: readBool(m['maskEnabled'], true),
    maskDensity: readDouble(m['maskDensity'], 1).clamp(0.0, 1.0),
    maskFeather: readDouble(m['maskFeather']).clamp(0.0, 1000.0),
    fillOpacity: readDouble(m['fill'], 1).clamp(0.0, 1.0),
    blendInterior: readBool(m['blendInterior']),
    stroke: m['stroke'] is Map
        ? LayerStroke.fromJson(readMap(m['stroke']))
        : null,
  );

  @override
  bool operator ==(Object other) =>
      other is LayerProps &&
      other.id == id &&
      other.name == name &&
      other.visible == visible &&
      other.locked == locked &&
      other.opacity == opacity &&
      other.blendMode == blendMode &&
      other.transform == transform &&
      other.clip == clip &&
      other.maskEnabled == maskEnabled &&
      other.maskDensity == maskDensity &&
      other.maskFeather == maskFeather &&
      other.fillOpacity == fillOpacity &&
      other.blendInterior == blendInterior &&
      other.stroke == stroke &&
      listEquals(other.effects, effects) &&
      listEquals(other.mask, mask);

  @override
  int get hashCode => Object.hash(
    id,
    name,
    visible,
    locked,
    opacity,
    blendMode,
    transform,
    clip,
    maskEnabled,
    maskDensity,
    maskFeather,
    fillOpacity,
    blendInterior,
    stroke,
    Object.hashAll(effects),
    Object.hashAll(mask),
  );
}

/// A node in the document's layer stack.
///
/// Layers are immutable values. Editing produces a new layer (via
/// [withProps] or the subclass `copyWith`), which is what makes undo/redo a
/// matter of keeping old document snapshots around.
///
/// New layer kinds (groups, adjustment layers, smart objects, vector paths…)
/// are added as new subclasses; the `switch` statements over this sealed
/// type will then point out every place that must learn about them.
@immutable
sealed class Layer {
  const Layer(this.props);

  final LayerProps props;

  String get id => props.id;
  LayerKind get kind;

  Layer withProps(LayerProps props);

  Layer update(LayerProps Function(LayerProps p) f) => withProps(f(props));

  /// Every fill this layer paints with (for pattern assets and the like).
  Iterable<PixFill> get fills => [
    ?props.stroke?.fill,
    ...switch (this) {
      TextLayer t => [t.fill, ?t.background],
      ShapeLayer s => [s.fill],
      IconLayer i => [i.fill],
      PathLayer p => [?p.fill],
      RasterLayer() || GroupLayer() || DrawingLayer() => const <PixFill>[],
    },
  ];

  /// Project assets used by image-pattern fills.
  Iterable<String> get fillAssets => [for (final f in fills) ?f.assetId];

  /// Returns a deep copy with fresh ids (layer and effects).
  Layer cloneWithNewId({String? name}) => withProps(
    props.copyWith(
      id: newId('ly'),
      name: name,
      effects: [
        for (final e in props.effects)
          LayerEffect(type: e.type, enabled: e.enabled, params: e.params),
      ],
    ),
  );

  Json contentToJson();

  Json toJson() => {'kind': kind.name, ...props.toJson(), ...contentToJson()};

  static Layer? fromJson(Json m) {
    final props = LayerProps.fromJson(m);
    return switch (readString(m['kind'])) {
      'raster' => RasterLayer.fromJson(props, m),
      'text' => TextLayer.fromJson(props, m),
      'shape' => ShapeLayer.fromJson(props, m),
      'group' => GroupLayer.fromJson(props, m),
      'icon' => IconLayer.fromJson(props, m),
      'path' => PathLayer.fromJson(props, m),
      'drawing' => DrawingLayer.fromJson(props, m),
      _ => null,
    };
  }
}

/// How an image was cropped (kept so the crop can be edited again from
/// the original pixels): quarter turns, flips, straighten angle, the crop
/// rectangle (0..1 of the turned, straightened image's bounding box),
/// an elliptical crop and the output resolution.
@immutable
class CropState {
  const CropState({
    this.quarterTurns = 0,
    this.flipH = false,
    this.flipV = false,
    this.straighten = 0,
    this.rect = const Rect.fromLTRB(0, 0, 1, 1),
    this.ellipse = false,
    this.resolution = 1,
  });

  final int quarterTurns;
  final bool flipH;
  final bool flipV;

  /// Degrees, −45…45.
  final double straighten;
  final Rect rect;
  final bool ellipse;

  /// Output pixel scale 0.1…1.
  final double resolution;

  CropState copyWith({
    int? quarterTurns,
    bool? flipH,
    bool? flipV,
    double? straighten,
    Rect? rect,
    bool? ellipse,
    double? resolution,
  }) => CropState(
    quarterTurns: quarterTurns ?? this.quarterTurns,
    flipH: flipH ?? this.flipH,
    flipV: flipV ?? this.flipV,
    straighten: straighten ?? this.straighten,
    rect: rect ?? this.rect,
    ellipse: ellipse ?? this.ellipse,
    resolution: resolution ?? this.resolution,
  );

  Json toJson() => {
    if (quarterTurns != 0) 'turns': quarterTurns,
    if (flipH) 'flipH': true,
    if (flipV) 'flipV': true,
    if (straighten != 0) 'straighten': straighten,
    'l': rect.left,
    't': rect.top,
    'r': rect.right,
    'b': rect.bottom,
    if (ellipse) 'ellipse': true,
    if (resolution != 1) 'res': resolution,
  };

  static CropState fromJson(Json m) => CropState(
    quarterTurns: readDouble(m['turns']).round() % 4,
    flipH: readBool(m['flipH']),
    flipV: readBool(m['flipV']),
    straighten: readDouble(m['straighten']).clamp(-45.0, 45.0),
    rect: Rect.fromLTRB(
      readDouble(m['l']).clamp(0.0, 1.0),
      readDouble(m['t']).clamp(0.0, 1.0),
      readDouble(m['r'], 1).clamp(0.0, 1.0),
      readDouble(m['b'], 1).clamp(0.0, 1.0),
    ),
    ellipse: readBool(m['ellipse']),
    resolution: readDouble(m['res'], 1).clamp(0.05, 1.0),
  );

  @override
  bool operator ==(Object other) =>
      other is CropState &&
      other.quarterTurns == quarterTurns &&
      other.flipH == flipH &&
      other.flipV == flipV &&
      other.straighten == straighten &&
      other.rect == rect &&
      other.ellipse == ellipse &&
      other.resolution == resolution;

  @override
  int get hashCode => Object.hash(
    quarterTurns,
    flipH,
    flipV,
    straighten,
    rect,
    ellipse,
    resolution,
  );
}

/// A bitmap. Pixels live in the project's asset store under [assetId]; the
/// layer only references them, so snapshots stay cheap. A cropped image
/// keeps its [sourceAssetId] (the original) and [crop] so the crop can be
/// changed later without losing pixels.
final class RasterLayer extends Layer {
  const RasterLayer(
    super.props, {
    required this.assetId,
    required this.width,
    required this.height,
    this.sourceAssetId,
    this.crop,
  });

  final String assetId;

  /// Natural pixel size of the asset.
  final double width;
  final double height;

  /// The uncropped original, when the image was cropped.
  final String? sourceAssetId;
  final CropState? crop;

  @override
  LayerKind get kind => LayerKind.raster;

  @override
  RasterLayer withProps(LayerProps props) => RasterLayer(
    props,
    assetId: assetId,
    width: width,
    height: height,
    sourceAssetId: sourceAssetId,
    crop: crop,
  );

  RasterLayer copyWith({
    String? assetId,
    double? width,
    double? height,
    String? sourceAssetId,
    CropState? crop,
    bool clearCrop = false,
  }) => RasterLayer(
    props,
    assetId: assetId ?? this.assetId,
    width: width ?? this.width,
    height: height ?? this.height,
    sourceAssetId: clearCrop ? null : (sourceAssetId ?? this.sourceAssetId),
    crop: clearCrop ? null : (crop ?? this.crop),
  );

  @override
  Json contentToJson() => {
    'asset': assetId,
    'w': width,
    'h': height,
    if (sourceAssetId != null) 'source': sourceAssetId,
    if (crop != null) 'crop': crop!.toJson(),
  };

  static RasterLayer fromJson(LayerProps props, Json m) => RasterLayer(
    props,
    assetId: readString(m['asset']),
    width: readDouble(m['w'], 1),
    height: readDouble(m['h'], 1),
    sourceAssetId: m['source'] == null ? null : readString(m['source']),
    crop: m['crop'] is Map ? CropState.fromJson(readMap(m['crop'])) : null,
  );

  @override
  bool operator ==(Object other) =>
      other is RasterLayer &&
      other.props == props &&
      other.assetId == assetId &&
      other.width == width &&
      other.height == height &&
      other.sourceAssetId == sourceAssetId &&
      other.crop == crop;

  @override
  int get hashCode =>
      Object.hash(props, assetId, width, height, sourceAssetId, crop);
}

enum PixTextAlign { start, center, end, justify }

/// Letter case transform applied when the text is drawn.
enum PixTextCase { none, upper, lower, title }

@immutable
final class TextLayer extends Layer {
  TextLayer(
    super.props, {
    required this.text,
    this.fontFamily = 'Vazirmatn',
    this.fontSize = 96,
    this.fontWeight = 700,
    this.italic = false,
    PixFill? fill,
    this.align = PixTextAlign.center,
    this.letterSpacing = 0,
    this.lineHeight = 1.3,
    this.strokeWidth = 0,
    this.strokeColor = const Color(0xFF000000),
    this.underline = false,
    this.boxWidth,
    this.strike = false,
    this.textCase = PixTextCase.none,
    this.wordSpacing = 0,
    this.curve = 0,
    this.background,
    this.bgPadX = 0.3,
    this.bgPadY = 0.15,
    this.bgRadius = 0.2,
    List<TextSpanStyle> spans = const [],
  }) : fill = fill ?? PixFill.white,
       spans = List.unmodifiable(spans);

  final String text;
  final String fontFamily;
  final double fontSize;

  /// CSS-style weight: 100..900.
  final int fontWeight;
  final bool italic;
  final PixFill fill;
  final PixTextAlign align;
  final double letterSpacing;
  final double lineHeight;
  final double strokeWidth;
  final Color strokeColor;
  final bool underline;

  /// Text-box width in layer pixels: text wraps onto more lines to fit and
  /// the box grows in height as needed. `null` = one line per paragraph
  /// (the box hugs the text).
  final double? boxWidth;

  /// Strike-through line.
  final bool strike;
  final PixTextCase textCase;

  /// Extra space between words, layer px.
  final double wordSpacing;

  /// Bends the lines along an arc: the angle (degrees) the text spans.
  /// Positive bends upward (∩), negative downward (∪), 0 = straight.
  final double curve;

  /// Box behind the text (null = none).
  final PixFill? background;

  /// Background padding and corner radius, as fractions of the font size.
  final double bgPadX;
  final double bgPadY;
  final double bgRadius;

  /// Fonts / colours for parts of the text (sorted, non-overlapping).
  final List<TextSpanStyle> spans;

  /// [text] with [textCase] applied.
  String get displayText => switch (textCase) {
    PixTextCase.none => text,
    PixTextCase.upper => text.toUpperCase(),
    PixTextCase.lower => text.toLowerCase(),
    PixTextCase.title => text.replaceAllMapped(
      RegExp(r'(^|\s)(\S)'),
      (m) => '${m[1]}${m[2]!.toUpperCase()}',
    ),
  };

  @override
  LayerKind get kind => LayerKind.text;

  @override
  TextLayer withProps(LayerProps props) => copyWith(props: props);

  TextLayer copyWith({
    LayerProps? props,
    String? text,
    String? fontFamily,
    double? fontSize,
    int? fontWeight,
    bool? italic,
    PixFill? fill,
    PixTextAlign? align,
    double? letterSpacing,
    double? lineHeight,
    double? strokeWidth,
    Color? strokeColor,
    bool? underline,
    double? boxWidth,
    bool autoWidth = false,
    bool? strike,
    PixTextCase? textCase,
    double? wordSpacing,
    double? curve,
    PixFill? background,
    bool noBackground = false,
    double? bgPadX,
    double? bgPadY,
    double? bgRadius,
    List<TextSpanStyle>? spans,
  }) => TextLayer(
    props ?? this.props,
    text: text ?? this.text,
    fontFamily: fontFamily ?? this.fontFamily,
    fontSize: fontSize ?? this.fontSize,
    fontWeight: fontWeight ?? this.fontWeight,
    italic: italic ?? this.italic,
    fill: fill ?? this.fill,
    align: align ?? this.align,
    letterSpacing: letterSpacing ?? this.letterSpacing,
    lineHeight: lineHeight ?? this.lineHeight,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    strokeColor: strokeColor ?? this.strokeColor,
    underline: underline ?? this.underline,
    boxWidth: autoWidth ? null : (boxWidth ?? this.boxWidth),
    strike: strike ?? this.strike,
    textCase: textCase ?? this.textCase,
    wordSpacing: wordSpacing ?? this.wordSpacing,
    curve: curve ?? this.curve,
    background: noBackground ? null : (background ?? this.background),
    bgPadX: bgPadX ?? this.bgPadX,
    bgPadY: bgPadY ?? this.bgPadY,
    bgRadius: bgRadius ?? this.bgRadius,
    spans: spans ?? this.spans,
  );

  @override
  Json contentToJson() => {
    'text': text,
    'font': fontFamily,
    'size': fontSize,
    'weight': fontWeight,
    if (italic) 'italic': true,
    'fill': fill.toJson(),
    'align': align.name,
    if (letterSpacing != 0) 'letterSpacing': letterSpacing,
    'lineHeight': lineHeight,
    if (strokeWidth > 0) 'strokeWidth': strokeWidth,
    if (strokeWidth > 0) 'strokeColor': writeColor(strokeColor),
    if (underline) 'underline': true,
    'boxWidth': ?boxWidth,
    if (strike) 'strike': true,
    if (textCase != PixTextCase.none) 'case': textCase.name,
    if (wordSpacing != 0) 'wordSpacing': wordSpacing,
    if (curve != 0) 'curve': curve,
    if (background != null) ...{
      'bg': background!.toJson(),
      'bgPadX': bgPadX,
      'bgPadY': bgPadY,
      'bgRadius': bgRadius,
    },
    if (spans.isNotEmpty) 'spans': [for (final s in spans) s.toJson()],
  };

  static TextLayer fromJson(LayerProps props, Json m) => TextLayer(
    props,
    text: readString(m['text']),
    fontFamily: readString(m['font'], 'Vazirmatn'),
    fontSize: readDouble(m['size'], 96).clamp(1, 4000).toDouble(),
    fontWeight: readInt(m['weight'], 700).clamp(100, 900),
    italic: readBool(m['italic']),
    fill: PixFill.fromJson(m['fill']),
    align: readEnum(PixTextAlign.values, m['align'], PixTextAlign.center),
    letterSpacing: readDouble(m['letterSpacing']),
    lineHeight: readDouble(m['lineHeight'], 1.3),
    strokeWidth: readDouble(m['strokeWidth']),
    strokeColor: readColor(m['strokeColor']),
    underline: readBool(m['underline']),
    boxWidth: m['boxWidth'] == null
        ? null
        : readDouble(m['boxWidth'], 100).clamp(4, 100000).toDouble(),
    strike: readBool(m['strike']),
    textCase: readEnum(PixTextCase.values, m['case'], PixTextCase.none),
    wordSpacing: readDouble(m['wordSpacing']),
    curve: readDouble(m['curve']).clamp(-360.0, 360.0),
    background: m['bg'] == null ? null : PixFill.fromJson(m['bg']),
    bgPadX: readDouble(m['bgPadX'], 0.3),
    bgPadY: readDouble(m['bgPadY'], 0.15),
    bgRadius: readDouble(m['bgRadius'], 0.2),
    spans: [
      for (final s in readList(m['spans']))
        if (s is Map) TextSpanStyle.fromJson(readMap(s)),
    ],
  );

  @override
  bool operator ==(Object other) =>
      other is TextLayer &&
      other.props == props &&
      other.text == text &&
      other.fontFamily == fontFamily &&
      other.fontSize == fontSize &&
      other.fontWeight == fontWeight &&
      other.italic == italic &&
      other.fill == fill &&
      other.align == align &&
      other.letterSpacing == letterSpacing &&
      other.lineHeight == lineHeight &&
      other.strokeWidth == strokeWidth &&
      other.strokeColor == strokeColor &&
      other.underline == underline &&
      other.boxWidth == boxWidth &&
      other.strike == strike &&
      other.textCase == textCase &&
      other.wordSpacing == wordSpacing &&
      other.curve == curve &&
      other.background == background &&
      other.bgPadX == bgPadX &&
      other.bgPadY == bgPadY &&
      other.bgRadius == bgRadius &&
      listEquals(other.spans, spans);

  @override
  int get hashCode => Object.hash(
    props,
    text,
    fontFamily,
    fontSize,
    fontWeight,
    italic,
    fill,
    align,
    letterSpacing,
    lineHeight,
    strokeWidth,
    strokeColor,
    underline,
    boxWidth,
    Object.hash(
      strike,
      textCase,
      wordSpacing,
      curve,
      background,
      bgPadX,
      bgPadY,
      bgRadius,
      Object.hashAll(spans),
    ),
  );
}

enum ShapeKind {
  rectangle,
  ellipse,
  triangle,
  star,
  polygon,
  heart,
  line,
  diamond,
  parallelogram,
  trapezoid,
  cross,
  crescent,
  speechBubble,
  blockArrow,
  chevron,
  gear,
  frame,
}

@immutable
final class ShapeLayer extends Layer {
  ShapeLayer(
    super.props, {
    required this.shape,
    required this.width,
    required this.height,
    PixFill? fill,
    this.strokeWidth = 0,
    this.strokeColor = const Color(0xFF000000),
    this.cornerRadius = 0,
    this.sides = 5,
    Map<String, double> params = const {},
  }) : fill = fill ?? PixFill.white,
       params = Map.unmodifiable(params);

  final ShapeKind shape;
  final double width;
  final double height;
  final PixFill fill;
  final double strokeWidth;
  final Color strokeColor;

  /// Rectangle corner radius in layer pixels.
  final double cornerRadius;

  /// Points for stars, sides for polygons.
  final int sides;

  /// Per-shape options (sweep, inner radius, roundness, tail…); see
  /// `shapeParams` for what each shape understands. Missing = default.
  final Map<String, double> params;

  double param(String key, double fallback) => params[key] ?? fallback;

  @override
  LayerKind get kind => LayerKind.shape;

  @override
  ShapeLayer withProps(LayerProps props) => copyWith(props: props);

  ShapeLayer copyWith({
    LayerProps? props,
    ShapeKind? shape,
    double? width,
    double? height,
    PixFill? fill,
    double? strokeWidth,
    Color? strokeColor,
    double? cornerRadius,
    int? sides,
    Map<String, double>? params,
  }) => ShapeLayer(
    props ?? this.props,
    shape: shape ?? this.shape,
    width: width ?? this.width,
    height: height ?? this.height,
    fill: fill ?? this.fill,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    strokeColor: strokeColor ?? this.strokeColor,
    cornerRadius: cornerRadius ?? this.cornerRadius,
    sides: sides ?? this.sides,
    params: params ?? this.params,
  );

  ShapeLayer withParam(String key, double value) =>
      copyWith(params: {...params, key: value});

  @override
  Json contentToJson() => {
    'shape': shape.name,
    'w': width,
    'h': height,
    'fill': fill.toJson(),
    if (strokeWidth > 0) 'strokeWidth': strokeWidth,
    if (strokeWidth > 0) 'strokeColor': writeColor(strokeColor),
    if (cornerRadius > 0) 'radius': cornerRadius,
    if (shape == ShapeKind.star ||
        shape == ShapeKind.polygon ||
        shape == ShapeKind.gear)
      'sides': sides,
    if (params.isNotEmpty) 'params': params,
  };

  static ShapeLayer fromJson(LayerProps props, Json m) => ShapeLayer(
    props,
    shape: readEnum(ShapeKind.values, m['shape'], ShapeKind.rectangle),
    width: readDouble(m['w'], 100),
    height: readDouble(m['h'], 100),
    fill: PixFill.fromJson(m['fill']),
    strokeWidth: readDouble(m['strokeWidth']),
    strokeColor: readColor(m['strokeColor']),
    cornerRadius: readDouble(m['radius']),
    sides: readInt(m['sides'], 5).clamp(3, 64),
    params: {
      for (final e in readMap(m['params']).entries)
        if (parseScalar(e.value) case final num v) e.key: v.toDouble(),
    },
  );

  @override
  bool operator ==(Object other) =>
      other is ShapeLayer &&
      other.props == props &&
      other.shape == shape &&
      other.width == width &&
      other.height == height &&
      other.fill == fill &&
      other.strokeWidth == strokeWidth &&
      other.strokeColor == strokeColor &&
      other.cornerRadius == cornerRadius &&
      other.sides == sides &&
      mapEquals(other.params, params);

  @override
  int get hashCode => Object.hash(
    props,
    shape,
    width,
    height,
    fill,
    strokeWidth,
    strokeColor,
    cornerRadius,
    sides,
    Object.hashAll(params.entries.map((e) => Object.hash(e.key, e.value))),
  );
}

/// A folder of layers. Children are ordered bottom → top like the document.
///
/// A group composites its children in isolation and then applies its own
/// opacity, blend mode, effects and clipping to the result (Photoshop's
/// behaviour for groups not set to "Pass Through"). The group's own
/// transform is always identity: moving a group moves its children.
final class GroupLayer extends Layer {
  GroupLayer(
    super.props, {
    List<Layer> children = const [],
    this.expanded = true,
  }) : children = List.unmodifiable(children);

  final List<Layer> children;

  /// UI state for the layers panel, persisted so a project reopens as left.
  final bool expanded;

  @override
  LayerKind get kind => LayerKind.group;

  @override
  GroupLayer withProps(LayerProps props) =>
      GroupLayer(props, children: children, expanded: expanded);

  GroupLayer copyWith({List<Layer>? children, bool? expanded}) => GroupLayer(
    props,
    children: children ?? this.children,
    expanded: expanded ?? this.expanded,
  );

  @override
  Layer cloneWithNewId({String? name}) =>
      (super.cloneWithNewId(name: name) as GroupLayer).copyWith(
        children: [for (final c in children) c.cloneWithNewId()],
      );

  @override
  Json contentToJson() => {
    if (!expanded) 'expanded': false,
    'children': [for (final c in children) c.toJson()],
  };

  static GroupLayer fromJson(LayerProps props, Json m) => GroupLayer(
    props.copyWith(transform: const LayerTransform()),
    expanded: readBool(m['expanded'], true),
    children: [
      for (final c in readList(m['children']))
        if (c is Map) ?Layer.fromJson(readMap(c)),
    ],
  );

  @override
  bool operator ==(Object other) =>
      other is GroupLayer &&
      other.props == props &&
      other.expanded == expanded &&
      listEquals(other.children, children);

  @override
  int get hashCode => Object.hash(props, expanded, Object.hashAll(children));
}

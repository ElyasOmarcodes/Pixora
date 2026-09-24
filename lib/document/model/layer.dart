import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../core/utils/ids.dart';
import '../../core/utils/json.dart';
import 'blend.dart';
import 'effect.dart';
import 'fill.dart';
import 'layer_transform.dart';

enum LayerKind { raster, text, shape, group }

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
  }) : id = id ?? newId('ly'),
       effects = List.unmodifiable(effects);

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
      listEquals(other.effects, effects);

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
    Object.hashAll(effects),
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
      _ => null,
    };
  }
}

/// A bitmap. Pixels live in the project's asset store under [assetId]; the
/// layer only references them, so snapshots stay cheap.
final class RasterLayer extends Layer {
  const RasterLayer(
    super.props, {
    required this.assetId,
    required this.width,
    required this.height,
  });

  final String assetId;

  /// Natural pixel size of the asset.
  final double width;
  final double height;

  @override
  LayerKind get kind => LayerKind.raster;

  @override
  RasterLayer withProps(LayerProps props) =>
      RasterLayer(props, assetId: assetId, width: width, height: height);

  RasterLayer copyWith({String? assetId, double? width, double? height}) =>
      RasterLayer(
        props,
        assetId: assetId ?? this.assetId,
        width: width ?? this.width,
        height: height ?? this.height,
      );

  @override
  Json contentToJson() => {'asset': assetId, 'w': width, 'h': height};

  static RasterLayer fromJson(LayerProps props, Json m) => RasterLayer(
    props,
    assetId: readString(m['asset']),
    width: readDouble(m['w'], 1),
    height: readDouble(m['h'], 1),
  );

  @override
  bool operator ==(Object other) =>
      other is RasterLayer &&
      other.props == props &&
      other.assetId == assetId &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(props, assetId, width, height);
}

enum PixTextAlign { start, center, end }

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
  }) : fill = fill ?? PixFill.white;

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
      other.underline == underline;

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
  );
}

enum ShapeKind { rectangle, ellipse, triangle, star, polygon, heart, line }

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
  }) : fill = fill ?? PixFill.white;

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
  );

  @override
  Json contentToJson() => {
    'shape': shape.name,
    'w': width,
    'h': height,
    'fill': fill.toJson(),
    if (strokeWidth > 0) 'strokeWidth': strokeWidth,
    if (strokeWidth > 0) 'strokeColor': writeColor(strokeColor),
    if (cornerRadius > 0) 'radius': cornerRadius,
    if (shape == ShapeKind.star || shape == ShapeKind.polygon) 'sides': sides,
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
      other.sides == sides;

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

import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../core/utils/ids.dart';
import '../../core/utils/json.dart';
import 'fill.dart';
import 'layer.dart';

/// The whole editable design: canvas size, background and the layer stack.
///
/// Immutable. The editor keeps a history of these values; every edit is a
/// function `PixDocument -> PixDocument`. Layers are ordered bottom → top.
///
/// All lookups and replacements go through the methods here so that when
/// nested groups arrive only this class needs to learn tree traversal.
@immutable
class PixDocument {
  PixDocument({
    String? id,
    required this.name,
    required this.width,
    required this.height,
    this.background,
    List<Layer> layers = const [],
  }) : id = id ?? newId('doc'),
       layers = List.unmodifiable(layers);

  /// Bumped whenever the on-disk format changes incompatibly; readers
  /// migrate older files forward in [fromJson].
  static const int formatVersion = 1;

  final String id;
  final String name;
  final double width;
  final double height;

  /// `null` means a transparent canvas.
  final PixFill? background;
  final List<Layer> layers;

  Size get size => Size(width, height);
  Rect get bounds => Offset.zero & size;
  Offset get center => Offset(width / 2, height / 2);

  PixDocument copyWith({
    String? name,
    double? width,
    double? height,
    PixFill? background,
    bool clearBackground = false,
    List<Layer>? layers,
  }) => PixDocument(
    id: id,
    name: name ?? this.name,
    width: width ?? this.width,
    height: height ?? this.height,
    background: clearBackground ? null : (background ?? this.background),
    layers: layers ?? this.layers,
  );

  // ---------------------------------------------------------------- queries

  Layer? layerById(String? id) {
    if (id == null) return null;
    for (final l in layers) {
      if (l.id == id) return l;
    }
    return null;
  }

  int indexOf(String id) => layers.indexWhere((l) => l.id == id);

  /// Every asset id referenced by the layers (used to garbage-collect).
  Set<String> get referencedAssets => {
    for (final l in layers)
      if (l is RasterLayer) l.assetId,
  };

  // ----------------------------------------------------------- transforms

  PixDocument replaceLayer(Layer layer) {
    final i = indexOf(layer.id);
    if (i < 0) return this;
    final next = [...layers]..[i] = layer;
    return copyWith(layers: next);
  }

  PixDocument updateLayer(String id, Layer Function(Layer l) f) {
    final l = layerById(id);
    return l == null ? this : replaceLayer(f(l));
  }

  /// Inserts [layer] at [index] (defaults to the top of the stack).
  PixDocument insertLayer(Layer layer, [int? index]) {
    final next = [...layers];
    next.insert((index ?? next.length).clamp(0, next.length), layer);
    return copyWith(layers: next);
  }

  PixDocument removeLayer(String id) => copyWith(
    layers: [
      for (final l in layers)
        if (l.id != id) l,
    ],
  );

  /// Moves a layer to [newIndex] in the bottom→top list.
  PixDocument moveLayerTo(String id, int newIndex) {
    final i = indexOf(id);
    if (i < 0) return this;
    final next = [...layers];
    final l = next.removeAt(i);
    next.insert(newIndex.clamp(0, next.length), l);
    return copyWith(layers: next);
  }

  // ------------------------------------------------------------- json

  Json toJson() => {
    'format': formatVersion,
    'id': id,
    'name': name,
    'width': width,
    'height': height,
    if (background != null) 'background': background!.toJson(),
    'layers': [for (final l in layers) l.toJson()],
  };

  static PixDocument fromJson(Json m) => PixDocument(
    id: readString(m['id'], newId('doc')),
    name: readString(m['name'], 'Untitled'),
    width: readDouble(m['width'], 1080).clamp(1, 16384).toDouble(),
    height: readDouble(m['height'], 1080).clamp(1, 16384).toDouble(),
    background: m['background'] == null
        ? null
        : PixFill.fromJson(m['background']),
    layers: [
      for (final l in readList(m['layers']))
        if (l is Map) ?Layer.fromJson(readMap(l)),
    ],
  );

  @override
  bool operator ==(Object other) =>
      other is PixDocument &&
      other.id == id &&
      other.name == name &&
      other.width == width &&
      other.height == height &&
      other.background == background &&
      listEquals(other.layers, layers);

  @override
  int get hashCode =>
      Object.hash(id, name, width, height, background, Object.hashAll(layers));
}

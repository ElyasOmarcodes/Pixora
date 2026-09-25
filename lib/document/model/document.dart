import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../core/utils/ids.dart';
import '../../core/utils/json.dart';
import 'fill.dart';
import 'guides.dart';
import 'layer.dart';

/// The whole editable design: canvas size, background and the layer stack.
///
/// Immutable. The editor keeps a history of these values; every edit is a
/// function `PixDocument -> PixDocument`. Layers are ordered bottom → top.
@immutable
class PixDocument {
  PixDocument({
    String? id,
    required this.name,
    required this.width,
    required this.height,
    this.background,
    List<Layer> layers = const [],
    CanvasGuides? guides,
    this.dpi = 72,
  }) : id = id ?? newId('doc'),
       layers = List.unmodifiable(layers),
       guides = guides ?? CanvasGuides.none;

  /// Bumped whenever the on-disk format changes incompatibly; readers
  /// migrate older files forward in [fromJson]. 2 = groups + clipping.
  static const int formatVersion = 2;

  final String id;
  final String name;
  final double width;
  final double height;

  /// `null` means a transparent canvas.
  final PixFill? background;
  final List<Layer> layers;

  /// Grid and ruler guides (layout aids; never rendered into exports).
  final CanvasGuides guides;

  /// Resolution for print units (cm, mm, inches): pixels per inch.
  final double dpi;

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
    CanvasGuides? guides,
    double? dpi,
  }) => PixDocument(
    id: id,
    name: name ?? this.name,
    width: width ?? this.width,
    height: height ?? this.height,
    background: clearBackground ? null : (background ?? this.background),
    layers: layers ?? this.layers,
    guides: guides ?? this.guides,
    dpi: dpi ?? this.dpi,
  );

  // ---------------------------------------------------------------- queries
  //
  // The layer stack is a tree (groups contain layers). Every lookup and
  // structural edit goes through these methods so the rest of the app never
  // walks the tree by hand.

  Layer? layerById(String? id) => id == null ? null : _find(layers, id);

  static Layer? _find(List<Layer> list, String id) {
    for (final l in list) {
      if (l.id == id) return l;
      if (l is GroupLayer) {
        final hit = _find(l.children, id);
        if (hit != null) return hit;
      }
    }
    return null;
  }

  bool contains(String id) => layerById(id) != null;

  /// The group directly containing [id], or null for top-level layers.
  GroupLayer? parentOf(String id) => _parent(layers, id, null);

  static GroupLayer? _parent(List<Layer> list, String id, GroupLayer? owner) {
    for (final l in list) {
      if (l.id == id) return owner;
      if (l is GroupLayer) {
        final hit = _parent(l.children, id, l);
        if (hit != null) return hit;
      }
    }
    return null;
  }

  /// Groups enclosing [id], innermost first.
  List<GroupLayer> ancestorsOf(String id) {
    final out = <GroupLayer>[];
    var p = parentOf(id);
    while (p != null) {
      out.add(p);
      p = parentOf(p.id);
    }
    return out;
  }

  /// The list [id] lives in (its parent's children or the top level).
  List<Layer> siblingsOf(String id) => parentOf(id)?.children ?? layers;

  /// Index of [id] among its siblings (bottom = 0), or -1.
  int indexOf(String id) => siblingsOf(id).indexWhere((l) => l.id == id);

  /// Every layer in paint order (bottom → top); a group precedes its
  /// children.
  List<Layer> get allLayers {
    final out = <Layer>[];
    void walk(List<Layer> list) {
      for (final l in list) {
        out.add(l);
        if (l is GroupLayer) walk(l.children);
      }
    }

    walk(layers);
    return out;
  }

  /// Visible and not hidden by a collapsed-visibility ancestor.
  bool isEffectivelyVisible(String id) {
    final l = layerById(id);
    if (l == null || !l.props.visible) return false;
    return ancestorsOf(id).every((g) => g.props.visible);
  }

  /// Locked itself or inside a locked group.
  bool isEffectivelyLocked(String id) {
    final l = layerById(id);
    if (l == null) return false;
    return l.props.locked || ancestorsOf(id).any((g) => g.props.locked);
  }

  /// Every asset id referenced by the layers (used to garbage-collect).
  Set<String> get referencedAssets => {
    for (final l in allLayers) ...[
      if (l is RasterLayer) ...[l.assetId, ?l.sourceAssetId],
      ...l.props.maskAssets,
    ],
  };

  // ----------------------------------------------------------- transforms

  static List<Layer> _mapTree(List<Layer> list, Layer? Function(Layer) f) {
    final out = <Layer>[];
    for (final l in list) {
      var next = f(l);
      if (next is GroupLayer) {
        next = next.copyWith(children: _mapTree(next.children, f));
      }
      if (next != null) out.add(next);
    }
    return out;
  }

  PixDocument replaceLayer(Layer layer) {
    if (!contains(layer.id)) return this;
    return copyWith(
      layers: _mapTree(layers, (l) => l.id == layer.id ? layer : l),
    );
  }

  PixDocument updateLayer(String id, Layer Function(Layer l) f) {
    final l = layerById(id);
    return l == null ? this : replaceLayer(f(l));
  }

  /// Applies [f] to every layer in the tree (e.g. to scale the whole design).
  PixDocument mapLayers(Layer Function(Layer l) f) =>
      copyWith(layers: _mapTree(layers, f));

  PixDocument removeLayer(String id) =>
      copyWith(layers: _mapTree(layers, (l) => l.id == id ? null : l));

  PixDocument removeLayers(Set<String> ids) =>
      copyWith(layers: _mapTree(layers, (l) => ids.contains(l.id) ? null : l));

  /// Inserts [layer] into [parentId] (null = top level) at [index]
  /// (defaults to the top of that list).
  PixDocument insertLayer(Layer layer, {String? parentId, int? index}) {
    List<Layer> insertInto(List<Layer> list) {
      final next = [...list];
      next.insert((index ?? next.length).clamp(0, next.length), layer);
      return next;
    }

    if (parentId == null) return copyWith(layers: insertInto(layers));
    final parent = layerById(parentId);
    if (parent is! GroupLayer) return copyWith(layers: insertInto(layers));
    return replaceLayer(parent.copyWith(children: insertInto(parent.children)));
  }

  /// Moves [id] into [parentId] (null = top level) at [index] of that list
  /// (index counted after the layer has been removed from its old place).
  PixDocument moveLayer(String id, {String? parentId, required int index}) {
    final l = layerById(id);
    if (l == null || id == parentId) return this;
    // A group can't be moved into itself or one of its descendants.
    if (parentId != null &&
        l is GroupLayer &&
        ancestorsOf(parentId).any((g) => g.id == id)) {
      return this;
    }
    return removeLayer(id).insertLayer(l, parentId: parentId, index: index);
  }

  /// Moves a layer to [newIndex] among its current siblings.
  PixDocument moveLayerTo(String id, int newIndex) =>
      moveLayer(id, parentId: parentOf(id)?.id, index: newIndex);

  // ------------------------------------------------------------- json

  Json toJson() => {
    'format': formatVersion,
    'id': id,
    'name': name,
    'width': width,
    'height': height,
    if (background != null) 'background': background!.toJson(),
    'layers': [for (final l in layers) l.toJson()],
    if (!guides.isEmpty) 'guides': guides.toJson(),
    if (dpi != 72) 'dpi': dpi,
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
    guides: m['guides'] == null ? null : CanvasGuides.fromJson(m['guides']),
    dpi: readDouble(m['dpi'], 72).clamp(1, 9600).toDouble(),
  );

  @override
  bool operator ==(Object other) =>
      other is PixDocument &&
      other.id == id &&
      other.name == name &&
      other.width == width &&
      other.height == height &&
      other.background == background &&
      other.guides == guides &&
      other.dpi == dpi &&
      listEquals(other.layers, layers);

  @override
  int get hashCode => Object.hash(
    id,
    name,
    width,
    height,
    background,
    guides,
    dpi,
    Object.hashAll(layers),
  );
}

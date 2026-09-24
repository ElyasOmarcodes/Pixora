import 'dart:collection';
import 'dart:ui' as ui;

import '../model/layer.dart';

/// A layer rendered once into a bitmap: [rect] is where it sits in document
/// space relative to the layer's position.
class CachedLayer {
  CachedLayer(this.image, this.rect, this.pixelScale);
  final ui.Image image;
  final ui.Rect rect;
  final double pixelScale;

  int get pixels => image.width * image.height;
}

/// Keeps rendered bitmaps of expensive layers (layer styles, 3D, curved
/// text, masks) so the canvas redraws them as a single image instead of
/// recomputing every effect each frame. Moving a layer keeps its bitmap;
/// only a change to its content, effects, rotation, scale or the zoom
/// level renders it again.
class LayerRasterCache {
  LayerRasterCache({this.maxPixels = 64 * 1024 * 1024});

  /// Memory budget in pixels (4 bytes each).
  final int maxPixels;

  final LinkedHashMap<(Layer, double, int), CachedLayer> _entries =
      LinkedHashMap();
  int _pixels = 0;

  CachedLayer? lookup((Layer, double, int) key) {
    final hit = _entries.remove(key);
    if (hit != null) _entries[key] = hit;
    return hit;
  }

  void put((Layer, double, int) key, CachedLayer entry) {
    final old = _entries.remove(key);
    if (old != null) _drop(old);
    _entries[key] = entry;
    _pixels += entry.pixels;
    while (_pixels > maxPixels && _entries.length > 1) {
      final k = _entries.keys.first;
      _drop(_entries.remove(k)!);
    }
  }

  void _drop(CachedLayer e) {
    _pixels -= e.pixels;
    e.image.dispose();
  }

  void clear() {
    for (final e in _entries.values) {
      e.image.dispose();
    }
    _entries.clear();
    _pixels = 0;
  }

  int get length => _entries.length;
}

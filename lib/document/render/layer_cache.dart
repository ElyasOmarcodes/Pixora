import 'dart:collection';
import 'dart:ui' as ui;

import '../model/layer.dart';

/// One bitmap of a cached layer, composited with [mode] at [alpha]
/// (times the layer's opacity).
class CachedPart {
  CachedPart(this.image, this.mode, this.alpha);
  final ui.Image image;
  final ui.BlendMode mode;
  final double alpha;
}

/// A layer rendered once into bitmaps (one per differently blended part):
/// [rect] is where they sit in document space relative to the layer's
/// position.
class CachedLayer {
  CachedLayer(this.parts, this.rect, this.pixelScale);
  final List<CachedPart> parts;
  final ui.Rect rect;
  final double pixelScale;

  int get pixels {
    var n = 0;
    for (final p in parts) {
      n += p.image.width * p.image.height;
    }
    return n;
  }

  void dispose() {
    for (final p in parts) {
      p.image.dispose();
    }
  }
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

  final LinkedHashMap<(Layer, double, int, int), CachedLayer> _entries =
      LinkedHashMap();
  int _pixels = 0;

  CachedLayer? lookup((Layer, double, int, int) key) {
    final hit = _entries.remove(key);
    if (hit != null) _entries[key] = hit;
    return hit;
  }

  void put((Layer, double, int, int) key, CachedLayer entry) {
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
    e.dispose();
  }

  void clear() {
    for (final e in _entries.values) {
      e.dispose();
    }
    _entries.clear();
    _pixels = 0;
  }

  int get length => _entries.length;
}

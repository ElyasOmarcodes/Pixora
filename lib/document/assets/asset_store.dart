import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../core/utils/ids.dart';

/// Holds binary assets (encoded images) of an open project and their decoded
/// GPU images.
///
/// Assets are immutable and content never changes under an id, so any number
/// of document snapshots can share them. Listeners are notified when a decode
/// finishes so the canvas can repaint.
class AssetStore extends ChangeNotifier {
  final Map<String, Uint8List> _bytes = {};
  final Map<String, ui.Image> _images = {};
  final Map<String, Future<ui.Image?>> _pending = {};
  bool _disposed = false;

  Map<String, Uint8List> get allBytes => Map.unmodifiable(_bytes);

  Uint8List? bytesOf(String id) => _bytes[id];

  bool contains(String id) => _bytes.containsKey(id);

  /// Adds encoded image bytes and returns the new asset id.
  String add(Uint8List bytes, {String? id}) {
    final assetId = id ?? newId('as');
    _bytes[assetId] = bytes;
    return assetId;
  }

  void addAll(Map<String, Uint8List> assets) => _bytes.addAll(assets);

  /// The decoded image, or `null` while it is still decoding (a decode is
  /// started on first request).
  ui.Image? imageOf(String id) {
    final img = _images[id];
    if (img != null) return img;
    unawaited(decode(id));
    return null;
  }

  Future<ui.Image?> decode(String id) {
    final done = _images[id];
    if (done != null) return Future.value(done);
    return _pending[id] ??= _decode(id);
  }

  Future<ui.Image?> _decode(String id) async {
    final bytes = _bytes[id];
    if (bytes == null) return null;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (_disposed) {
        frame.image.dispose();
        return null;
      }
      _images[id] = frame.image;
      notifyListeners();
      return frame.image;
    } catch (e) {
      debugPrint('Pixora: failed to decode asset $id: $e');
      return null;
    } finally {
      _pending.removeWhere((key, _) => key == id);
    }
  }

  /// Decodes every asset; used before exporting so nothing is missing.
  Future<void> decodeAll(Iterable<String> ids) => Future.wait(ids.map(decode));

  /// Drops assets no longer referenced by [keep].
  void retainOnly(Set<String> keep) {
    for (final id in _bytes.keys.toList()) {
      if (!keep.contains(id)) {
        _bytes.remove(id);
        _images.remove(id)?.dispose();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final img in _images.values) {
      img.dispose();
    }
    _images.clear();
    super.dispose();
  }
}

/// Reads the pixel size of an encoded image without keeping it decoded.
/// (ImageDescriptor's size isn't available on the web, so there the first
/// frame is decoded instead.)
Future<ui.Size> measureImage(Uint8List bytes) async {
  if (!kIsWeb) {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final size = ui.Size(
      descriptor.width.toDouble(),
      descriptor.height.toDouble(),
    );
    descriptor.dispose();
    buffer.dispose();
    return size;
  }
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final size = ui.Size(
    frame.image.width.toDouble(),
    frame.image.height.toDouble(),
  );
  frame.image.dispose();
  codec.dispose();
  return size;
}

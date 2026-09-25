import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../document/assets/asset_store.dart';
import '../../document/model/patterns.dart';

/// One pattern the user made (Photoshop's Define Pattern).
@immutable
class MyPattern {
  const MyPattern(this.id, this.bytes);

  /// Content hash; also the asset id used inside projects (`pat_<id>`).
  final String id;

  /// PNG tile.
  final Uint8List bytes;

  String get assetId => 'pat_$id';
  String get patternId => Patterns.forAsset(assetId);
}

/// The user's own patterns, newest first, kept between sessions and shared
/// by every project. A pattern used in a project is also copied into the
/// project's assets, so the project file stays self-contained.
class PatternLibrary extends ChangeNotifier {
  PatternLibrary._();
  static final PatternLibrary instance = PatternLibrary._();

  static const max = 24;

  /// Longest side of a saved tile.
  static const maxSide = 512;
  static const _key = 'myPatterns';

  final List<MyPattern> _items = [];
  SharedPreferences? _prefs;

  List<MyPattern> get items => List.unmodifiable(_items);

  Future<void> load() async {
    try {
      final p = _prefs = await SharedPreferences.getInstance();
      _items.clear();
      for (final s in p.getStringList(_key) ?? const <String>[]) {
        final i = s.indexOf(':');
        if (i <= 0) continue;
        _items.add(
          MyPattern(s.substring(0, i), base64Decode(s.substring(i + 1))),
        );
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Pixora: patterns not loaded: $e');
    }
  }

  /// Adds a tile (resized to [maxSide]) and returns it.
  Future<MyPattern> add(Uint8List png) async {
    final bytes = await fitPng(png, maxSide);
    final p = MyPattern(contentHash(bytes), bytes);
    _items
      ..removeWhere((x) => x.id == p.id)
      ..insert(0, p);
    if (_items.length > max) _items.removeRange(max, _items.length);
    notifyListeners();
    _save();
    return p;
  }

  void remove(String id) {
    _items.removeWhere((x) => x.id == id);
    notifyListeners();
    _save();
  }

  void _save() {
    try {
      _prefs?.setStringList(_key, [
        for (final p in _items) '${p.id}:${base64Encode(p.bytes)}',
      ]);
    } catch (e) {
      debugPrint('Pixora: patterns not saved: $e');
    }
  }

  /// Puts [p] into a project's assets (once) and waits until it can draw.
  static Future<void> ensureIn(AssetStore assets, MyPattern p) async {
    if (!assets.contains(p.assetId)) assets.add(p.bytes, id: p.assetId);
    await assets.decode(p.assetId);
  }

  /// FNV-1a over the bytes, as hex.
  static String contentHash(Uint8List bytes) {
    var h = 0x811c9dc5;
    for (final b in bytes) {
      h ^= b;
      h = (h * 0x01000193) & 0xffffffff;
    }
    return '${h.toRadixString(16)}${bytes.length.toRadixString(36)}';
  }

  /// Re-encodes [bytes] as PNG with the longest side at most [max].
  static Future<Uint8List> fitPng(Uint8List bytes, int max) async {
    final probe = await ui.instantiateImageCodec(bytes);
    final first = await probe.getNextFrame();
    final w = first.image.width, h = first.image.height;
    first.image.dispose();
    probe.dispose();
    final scale = w > h ? max / w : max / h;
    final codec = scale < 1
        ? await ui.instantiateImageCodec(
            bytes,
            targetWidth: (w * scale).round().clamp(1, max),
            targetHeight: (h * scale).round().clamp(1, max),
          )
        : await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    codec.dispose();
    return data!.buffer.asUint8List();
  }
}

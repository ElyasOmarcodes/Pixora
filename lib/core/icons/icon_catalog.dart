import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../document/model/layer.dart';

/// A chosen icon: name, style and its SVG path data.
class IconPick {
  const IconPick({
    required this.name,
    required this.pathData,
    this.style = IconStyle.outlined,
    this.filled = false,
    this.weight = 400,
  });
  final String name;
  final String pathData;
  final IconStyle style;
  final bool filled;
  final int weight;
}

/// Google Material Symbols: every icon is bundled in the Outlined style
/// (works offline); the Rounded / Sharp styles, filled variants and other
/// weights are downloaded from Google Fonts on demand. Once added, an
/// icon's path lives in the project, so projects never need the network.
class IconCatalog {
  IconCatalog._();
  static final IconCatalog instance = IconCatalog._();

  static const _asset = 'assets/icons/material_symbols_outlined.json';

  Map<String, String>? _bundled;
  Future<Map<String, String>>? _loading;

  /// Downloaded styles: memory cache backed by a file on disk, so icons
  /// seen once keep working offline and on slow connections.
  final Map<String, String> _cache = {};
  final Map<String, Future<String?>> _inFlight = {};
  final Map<String, DateTime> _failedAt = {};
  bool _diskLoaded = false;
  Timer? _saveTimer;

  /// HTTP client (replaceable in tests).
  http.Client client = http.Client();

  /// At most this many downloads at once (weak connections stay usable).
  static const _maxParallel = 4;
  int _running = 0;
  final List<Completer<void>> _waiting = [];

  /// A few everyday icons shown first.
  static const List<String> popular = [
    'favorite',
    'star',
    'home',
    'person',
    'call',
    'mail',
    'location_on',
    'schedule',
    'check_circle',
    'shopping_cart',
    'photo_camera',
    'music_note',
    'lightbulb',
    'bolt',
    'rocket_launch',
    'celebration',
    'cake',
    'local_cafe',
    'restaurant',
    'flight',
    'directions_car',
    'school',
    'work',
    'pets',
    'eco',
    'wb_sunny',
    'dark_mode',
    'cloud',
    'water_drop',
    'local_fire_department',
    'sports_soccer',
    'fitness_center',
    'mosque',
    'menu_book',
    'brush',
    'palette',
    'chat',
    'thumb_up',
    'verified',
    'workspace_premium',
    'diamond',
    'redeem',
    'arrow_forward',
    'arrow_back',
    'arrow_upward',
    'arrow_downward',
    'north_east',
    'add',
    'close',
    'check',
    'search',
    'settings',
    'share',
    'download',
    'play_arrow',
    'pause',
    'mic',
    'wifi',
    'language',
    'public',
    'flag',
  ];

  Future<Map<String, String>> load() {
    if (_bundled != null) return SynchronousFuture(_bundled!);
    return _loading ??= rootBundle.loadString(_asset).then((s) async {
      final m = (jsonDecode(s) as Map).cast<String, String>();
      _bundled = m;
      await _loadDisk();
      return m;
    });
  }

  Future<File?> _file() async {
    if (kIsWeb) return null;
    try {
      final dir = await getApplicationSupportDirectory();
      return File('${dir.path}/icon_styles_cache.json');
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadDisk() async {
    if (_diskLoaded) return;
    _diskLoaded = true;
    try {
      final f = await _file();
      if (f == null || !await f.exists()) return;
      final m = jsonDecode(await f.readAsString());
      if (m is Map) {
        for (final e in m.entries) {
          if (e.key is String && e.value is String) {
            _cache.putIfAbsent(e.key as String, () => e.value as String);
          }
        }
      }
    } catch (e) {
      debugPrint('Pixora: icon cache unreadable: $e');
    }
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), () async {
      try {
        final f = await _file();
        await f?.writeAsString(jsonEncode(_cache));
      } catch (e) {
        debugPrint('Pixora: icon cache not saved: $e');
      }
    });
  }

  /// Bundled outlined path (for previews), if loaded.
  String? outlined(String name) => _bundled?[name];

  static String _variant(bool filled, int weight) {
    final w = weight == 400 ? '' : 'wght$weight';
    final f = filled ? 'fill1' : '';
    final v = '$w$f';
    return v.isEmpty ? 'default' : v;
  }

  static bool isBundled(IconStyle style, bool filled, int weight) =>
      style == IconStyle.outlined && !filled && weight == 400;

  static String _key(String name, IconStyle style, bool filled, int weight) =>
      '${style.name}/$name/${_variant(filled, weight)}';

  /// The path if it is available right now (bundled or already downloaded).
  String? cached(
    String name, {
    IconStyle style = IconStyle.outlined,
    bool filled = false,
    int weight = 400,
  }) => isBundled(style, filled, weight)
      ? (_bundled == null ? null : _bundled![name])
      : _cache[_key(name, style, filled, weight)];

  /// Path data for [name] in the given style. Outlined / regular / not
  /// filled comes from the app; anything else is fetched (and cached).
  /// Returns null when offline and the style isn't bundled. [wanted] lets
  /// a scrolled-away preview drop out of the download queue.
  Future<String?> pathFor(
    String name, {
    IconStyle style = IconStyle.outlined,
    bool filled = false,
    int weight = 400,
    bool Function()? wanted,
  }) async {
    final bundled = await load();
    if (isBundled(style, filled, weight)) return bundled[name];
    final key = _key(name, style, filled, weight);
    final hit = _cache[key];
    if (hit != null) return hit;
    // Don't hammer a failing connection: wait a little before retrying.
    final failed = _failedAt[key];
    if (failed != null &&
        DateTime.now().difference(failed) < const Duration(seconds: 20)) {
      return null;
    }
    return _inFlight[key] ??=
        _download(key, name, style, filled, weight, wanted).whenComplete(() {
          // (a block: returning the removed Future would await itself)
          _inFlight.remove(key);
        });
  }

  Future<String?> _download(
    String key,
    String name,
    IconStyle style,
    bool filled,
    int weight,
    bool Function()? wanted,
  ) async {
    // Queue behind other downloads.
    while (_running >= _maxParallel) {
      final c = Completer<void>();
      _waiting.add(c);
      await c.future;
    }
    if (wanted != null && !wanted()) {
      _release();
      return null;
    }
    _running++;
    try {
      final url = Uri.parse(
        'https://fonts.gstatic.com/s/i/short-term/release/'
        'materialsymbols${style.name}/$name/${_variant(filled, weight)}/24px.svg',
      );
      http.Response r;
      try {
        r = await client.get(url).timeout(const Duration(seconds: 15));
      } catch (_) {
        // One quiet retry: flaky mobile connections often drop a request.
        await Future<void>.delayed(const Duration(milliseconds: 800));
        r = await client.get(url).timeout(const Duration(seconds: 20));
      }
      if (r.statusCode != 200) {
        _failedAt[key] = DateTime.now();
        return null;
      }
      final ds = RegExp(r'<path[^>]*\sd="([^"]+)"')
          .allMatches(r.body)
          .map((m) => m.group(1)!)
          .join(' ');
      if (ds.isEmpty) return null;
      _cache[key] = ds;
      _failedAt.remove(key);
      _scheduleSave();
      return ds;
    } catch (e) {
      _failedAt[key] = DateTime.now();
      debugPrint('Pixora: icon download failed: $e');
      return null;
    } finally {
      _running--;
      _release();
    }
  }

  void _release() {
    if (_waiting.isNotEmpty) _waiting.removeAt(0).complete();
  }
}

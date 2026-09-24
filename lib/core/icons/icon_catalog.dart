import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

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
  final Map<String, String> _online = {};
  Future<Map<String, String>>? _loading;

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
    return _loading ??= rootBundle.loadString(_asset).then((s) {
      final m = (jsonDecode(s) as Map).cast<String, String>();
      _bundled = m;
      return m;
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

  /// Path data for [name] in the given style. Outlined / regular / not
  /// filled comes from the app; anything else is fetched (and cached).
  /// Returns null when offline and the style isn't bundled.
  Future<String?> pathFor(
    String name, {
    IconStyle style = IconStyle.outlined,
    bool filled = false,
    int weight = 400,
  }) async {
    final bundled = await load();
    if (style == IconStyle.outlined && !filled && weight == 400) {
      return bundled[name];
    }
    final key = '${style.name}/$name/${_variant(filled, weight)}';
    final hit = _online[key];
    if (hit != null) return hit;
    try {
      final url = Uri.parse(
        'https://fonts.gstatic.com/s/i/short-term/release/'
        'materialsymbols${style.name}/$name/${_variant(filled, weight)}/24px.svg',
      );
      final r = await http.get(url).timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return null;
      final ds = RegExp(r'<path[^>]*\sd="([^"]+)"')
          .allMatches(r.body)
          .map((m) => m.group(1)!)
          .join(' ');
      if (ds.isEmpty) return null;
      _online[key] = ds;
      return ds;
    } catch (e) {
      debugPrint('Pixora: icon download failed: $e');
      return null;
    }
  }
}

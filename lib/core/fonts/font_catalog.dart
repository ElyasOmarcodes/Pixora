import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../document/render/text_layout.dart';
import '../platform/platform_services.dart';
import '../settings/app_settings.dart';

enum FontScript { arabic, latin }

/// A font family shipped with the app.
class BundledFont {
  const BundledFont(this.family, this.script);
  final String family;
  final FontScript script;
}

/// A font the user imported (.ttf / .otf).
class UserFont {
  const UserFont(this.family, this.fileName);
  final String family;
  final String fileName;
}

/// All fonts available to text layers: bundled, imported by the user,
/// recently used and favourites.
class FontCatalog extends ChangeNotifier {
  FontCatalog(this._platform, this._settings);

  final PlatformServices _platform;
  final AppSettings _settings;

  static const String defaultFamily = 'Vazirmatn';

  static const List<BundledFont> bundled = [
    BundledFont('Vazirmatn', FontScript.arabic),
    BundledFont('Lalezar', FontScript.arabic),
    BundledFont('Amiri', FontScript.arabic),
    BundledFont('Noto Naskh Arabic', FontScript.arabic),
    BundledFont('Gulzar', FontScript.arabic),
    BundledFont('Reem Kufi', FontScript.arabic),
    BundledFont('El Messiri', FontScript.arabic),
    BundledFont('Changa', FontScript.arabic),
    BundledFont('Cairo', FontScript.arabic),
    BundledFont('Tajawal', FontScript.arabic),
    BundledFont('IBM Plex Sans Arabic', FontScript.arabic),
    BundledFont('Markazi Text', FontScript.arabic),
    BundledFont('Lateef', FontScript.arabic),
    BundledFont('Scheherazade New', FontScript.arabic),
    BundledFont('Aref Ruqaa', FontScript.arabic),
    BundledFont('Mirza', FontScript.arabic),
    BundledFont('Rakkas', FontScript.arabic),
    BundledFont('Jomhuria', FontScript.arabic),
    BundledFont('Katibeh', FontScript.arabic),
    BundledFont('Blaka', FontScript.arabic),
    BundledFont('Vibes', FontScript.arabic),
    BundledFont('Lemonada', FontScript.arabic),
    BundledFont('Poppins', FontScript.latin),
    BundledFont('Playfair Display', FontScript.latin),
    BundledFont('Oswald', FontScript.latin),
    BundledFont('Bebas Neue', FontScript.latin),
    BundledFont('Anton', FontScript.latin),
    BundledFont('Abril Fatface', FontScript.latin),
    BundledFont('Righteous', FontScript.latin),
    BundledFont('Lobster', FontScript.latin),
    BundledFont('Pacifico', FontScript.latin),
    BundledFont('Dancing Script', FontScript.latin),
    BundledFont('Permanent Marker', FontScript.latin),
    BundledFont('System', FontScript.latin),
  ];

  final List<UserFont> _user = [];
  List<UserFont> get userFonts => List.unmodifiable(_user);

  List<String> get recent => _settings.recentFonts;
  List<String> get favorites => _settings.favoriteFonts;

  bool isFavorite(String family) => favorites.contains(family);

  /// Whether [family] can be drawn (bundled or imported).
  bool isAvailable(String family) =>
      bundled.any((f) => f.family == family) ||
      _user.any((f) => f.family == family);

  /// Loads previously imported fonts. Call once at startup.
  Future<void> init() async {
    for (final f in await _platform.loadUserFonts()) {
      await _register(f.name, f.bytes);
    }
    notifyListeners();
  }

  /// Lets the user pick font files and adds them. Returns the families
  /// that were added.
  Future<List<String>> import() async {
    final added = <String>[];
    for (final f in await _platform.pickFontFiles()) {
      final family = await _register(f.name, f.bytes);
      if (family == null) continue;
      await _platform.saveUserFont(f.name, f.bytes);
      added.add(family);
    }
    if (added.isNotEmpty) notifyListeners();
    return added;
  }

  Future<void> remove(UserFont font) async {
    _user.removeWhere((f) => f.fileName == font.fileName);
    await _platform.deleteUserFont(font.fileName);
    // The family stays registered with the engine for this session.
    notifyListeners();
  }

  /// Family name from a file name: "IBMPlexSansArabic-Bold.ttf" →
  /// "IBMPlexSansArabic-Bold".
  static String familyFromFile(String fileName) {
    final dot = fileName.lastIndexOf('.');
    final base = dot > 0 ? fileName.substring(0, dot) : fileName;
    return base.replaceAll(RegExp(r'[_]+'), ' ').trim();
  }

  Future<String?> _register(String fileName, Uint8List bytes) async {
    final family = familyFromFile(fileName);
    if (family.isEmpty || _user.any((f) => f.family == family)) return null;
    try {
      final loader = FontLoader(family)
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
      _user.add(UserFont(family, fileName));
      TextLayoutCache.instance.clear();
      return family;
    } catch (e) {
      debugPrint('Pixora: could not load font $fileName: $e');
      return null;
    }
  }

  void markUsed(String family) {
    final r = [family, ...recent.where((f) => f != family)];
    _settings.recentFonts = r.take(16).toList();
    notifyListeners();
  }

  void toggleFavorite(String family) {
    final f = favorites;
    _settings.favoriteFonts = f.contains(family)
        ? (f..remove(family))
        : [...f, family];
    notifyListeners();
  }
}

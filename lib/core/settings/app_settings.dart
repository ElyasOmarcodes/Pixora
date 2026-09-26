import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../units/units.dart';

/// Accent colors the user can choose from.
const List<Color> kAccentColors = [
  Color(0xFF3D7BFF), // Pixora blue
  Color(0xFF7C5CFF), // violet
  Color(0xFF00B894), // mint
  Color(0xFFFF6B6B), // coral
  Color(0xFFFFA62B), // amber
  Color(0xFFE84393), // pink
  Color(0xFF0FB9B1), // teal
  Color(0xFF576574), // slate
];

/// Languages shipped with the app (code, native name).
const List<(String, String)> kLanguages = [
  ('ps', 'پښتو'),
  ('fa', 'دری / فارسی'),
  ('ar', 'العربية'),
  ('ur', 'اردو'),
  ('en', 'English'),
  ('es', 'Español'),
  ('fr', 'Français'),
  ('tr', 'Türkçe'),
];

/// User preferences, persisted with shared_preferences.
class AppSettings extends ChangeNotifier {
  AppSettings._(this._prefs);

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings._(prefs);
  }

  final SharedPreferences _prefs;

  static const _kLocale = 'locale';
  static const _kTheme = 'themeMode';
  static const _kAccent = 'accent';
  static const _kAutosave = 'autosave';
  static const _kHaptics = 'haptics';
  static const _kSnap = 'snap';
  static const _kExportFormat = 'exportFormat';
  static const _kExportQuality = 'exportQuality';
  static const _kStorageRoot = 'storageRoot';
  static const _kSnapCanvas = 'snapCanvas';
  static const _kSnapGuides = 'snapGuides';
  static const _kSnapLayers = 'snapLayers';
  static const _kSnapAngles = 'snapAngles';
  static const _kRulers = 'rulers';
  static const _kRulerLayer = 'rulerLayer';

  /// `null` follows the system language.
  Locale? get locale {
    final code = _prefs.getString(_kLocale);
    return code == null ? null : Locale(code);
  }

  set locale(Locale? value) {
    value == null
        ? _prefs.remove(_kLocale)
        : _prefs.setString(_kLocale, value.languageCode);
    notifyListeners();
  }

  ThemeMode get themeMode => ThemeMode.values.firstWhere(
    (m) => m.name == _prefs.getString(_kTheme),
    orElse: () => ThemeMode.system,
  );

  set themeMode(ThemeMode value) {
    _prefs.setString(_kTheme, value.name);
    notifyListeners();
  }

  int get accentIndex =>
      (_prefs.getInt(_kAccent) ?? 0).clamp(0, kAccentColors.length - 1);

  Color get accent => kAccentColors[accentIndex];

  set accentIndex(int value) {
    _prefs.setInt(_kAccent, value);
    notifyListeners();
  }

  bool get autosave => _prefs.getBool(_kAutosave) ?? true;
  set autosave(bool v) => _setBool(_kAutosave, v);

  bool get haptics => _prefs.getBool(_kHaptics) ?? true;
  set haptics(bool v) => _setBool(_kHaptics, v);

  /// Snap layers to the canvas centre and edges while dragging.
  bool get snapping => _prefs.getBool(_kSnap) ?? true;
  set snapping(bool v) => _setBool(_kSnap, v);

  /// What layers snap to while dragging (when [snapping] is on).
  bool get snapCanvas => _prefs.getBool(_kSnapCanvas) ?? true;
  set snapCanvas(bool v) => _setBool(_kSnapCanvas, v);

  bool get snapGuides => _prefs.getBool(_kSnapGuides) ?? true;
  set snapGuides(bool v) => _setBool(_kSnapGuides, v);

  /// Smart guides: other layers' edges and centres.
  bool get snapLayers => _prefs.getBool(_kSnapLayers) ?? true;
  set snapLayers(bool v) => _setBool(_kSnapLayers, v);

  /// Rotation snaps to 45° steps.
  bool get snapAngles => _prefs.getBool(_kSnapAngles) ?? true;
  set snapAngles(bool v) => _setBool(_kSnapAngles, v);

  bool get showRulers => _prefs.getBool(_kRulers) ?? false;
  set showRulers(bool v) => _setBool(_kRulers, v);

  /// Marks the selected layer's span and size on the rulers.
  bool get rulerLayer => _prefs.getBool(_kRulerLayer) ?? true;
  set rulerLayer(bool v) => _setBool(_kRulerLayer, v);

  /// 'png' or 'jpg'.
  String get exportFormat => _prefs.getString(_kExportFormat) ?? 'png';
  set exportFormat(String v) {
    _prefs.setString(_kExportFormat, v);
    notifyListeners();
  }

  /// JPEG quality 50..100.
  int get exportQuality =>
      (_prefs.getInt(_kExportQuality) ?? 92).clamp(50, 100);
  set exportQuality(int v) {
    _prefs.setInt(_kExportQuality, v);
    notifyListeners();
  }

  /// Custom Pixora folder (desktop only); null = default location.
  String? get storageRoot => _prefs.getString(_kStorageRoot);
  set storageRoot(String? v) {
    v == null
        ? _prefs.remove(_kStorageRoot)
        : _prefs.setString(_kStorageRoot, v);
    notifyListeners();
  }

  static const _kRulerUnit = 'rulerUnit';
  static const _kGuideColor = 'guideColor';

  /// Units shown on the rulers.
  MeasureUnit get rulerUnit => MeasureUnit.values.firstWhere(
    (u) => u.name == _prefs.getString(_kRulerUnit),
    orElse: () => MeasureUnit.px,
  );
  set rulerUnit(MeasureUnit v) {
    _prefs.setString(_kRulerUnit, v.name);
    notifyListeners();
  }

  /// Colour of ruler guides.
  Color get guideColor => Color(_prefs.getInt(_kGuideColor) ?? 0xFF00C2FF);
  set guideColor(Color v) {
    _prefs.setInt(_kGuideColor, v.toARGB32());
    notifyListeners();
  }

  static const _kRecentFonts = 'recentFonts';
  static const _kFavoriteFonts = 'favoriteFonts';

  /// Most recently used font families, newest first.
  List<String> get recentFonts => _prefs.getStringList(_kRecentFonts) ?? [];
  set recentFonts(List<String> v) {
    _prefs.setStringList(_kRecentFonts, v);
    notifyListeners();
  }

  List<String> get favoriteFonts => _prefs.getStringList(_kFavoriteFonts) ?? [];
  set favoriteFonts(List<String> v) {
    _prefs.setStringList(_kFavoriteFonts, v);
    notifyListeners();
  }

  void _setBool(String key, bool v) {
    _prefs.setBool(key, v);
    notifyListeners();
  }
}

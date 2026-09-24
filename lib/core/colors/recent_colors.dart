import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../document/model/fill.dart';

/// The last colours and gradients the user applied (newest first), shared
/// by every colour row in the app and kept between sessions.
class RecentColors extends ChangeNotifier {
  RecentColors._();
  static final RecentColors instance = RecentColors._();

  static const max = 20;
  static const _kColors = 'recentColors';
  static const _kGradients = 'recentGradients';

  final List<Color> _colors = [];
  final List<PixFill> _gradients = [];
  SharedPreferences? _prefs;

  List<Color> get colors => List.unmodifiable(_colors);
  List<PixFill> get gradients => List.unmodifiable(_gradients);

  /// Loads the saved lists (call once at start-up; safe to skip in tests).
  Future<void> load() async {
    try {
      final p = _prefs = await SharedPreferences.getInstance();
      _colors
        ..clear()
        ..addAll([
          for (final v in p.getStringList(_kColors) ?? const <String>[])
            if (int.tryParse(v) case final int c) Color(c),
        ]);
      _gradients.clear();
      for (final g in p.getStringList(_kGradients) ?? const <String>[]) {
        try {
          final f = PixFill.fromJson(jsonDecode(g));
          if (f.isGradient) _gradients.add(f);
        } catch (_) {}
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Pixora: recent colours not loaded: $e');
    }
  }

  void addColor(Color c) {
    final v = c.toARGB32();
    _colors
      ..removeWhere((x) => x.toARGB32() == v)
      ..insert(0, c);
    if (_colors.length > max) _colors.removeRange(max, _colors.length);
    notifyListeners();
    _prefs?.setStringList(_kColors, [
      for (final x in _colors) '${x.toARGB32()}',
    ]);
  }

  void addGradient(PixFill f) {
    if (!f.isGradient) return;
    _gradients
      ..removeWhere((x) => x == f)
      ..insert(0, f);
    if (_gradients.length > max) {
      _gradients.removeRange(max, _gradients.length);
    }
    notifyListeners();
    _prefs?.setStringList(_kGradients, [
      for (final x in _gradients) jsonEncode(x.toJson()),
    ]);
  }
}

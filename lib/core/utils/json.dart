import 'dart:ui';

/// Small helpers that make JSON (de)serialization tolerant of missing or
/// slightly malformed values. Project files must keep opening even after the
/// format evolves, so every reader falls back to a sensible default.
typedef Json = Map<String, dynamic>;

double readDouble(Object? v, [double fallback = 0]) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? fallback;
  return fallback;
}

int readInt(Object? v, [int fallback = 0]) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

bool readBool(Object? v, [bool fallback = false]) {
  if (v is bool) return v;
  if (v is String) {
    if (v == 'true' || v == '1') return true;
    if (v == 'false' || v == '0') return false;
  }
  return fallback;
}

String readString(Object? v, [String fallback = '']) => switch (v) {
  String s => s,
  num n => n.toString(),
  bool b => b.toString(),
  _ => fallback,
};

Json readMap(Object? v) => v is Map
    ? v.map((k, value) => MapEntry(k.toString(), value))
    : <String, dynamic>{};

List<Object?> readList(Object? v) => v is List ? v : const [];

Color readColor(Object? v, [Color fallback = const Color(0xFF000000)]) {
  if (v is int) return Color(v);
  if (v is String) {
    final hex = v.replaceFirst('#', '');
    final parsed = int.tryParse(hex.length == 6 ? 'FF$hex' : hex, radix: 16);
    if (parsed != null) return Color(parsed);
  }
  return fallback;
}

/// Colors are stored as `#AARRGGBB` so project files stay human-readable.
String writeColor(Color c) =>
    '#${c.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';

/// Parses a scalar that may arrive as a string (XML) into a number, if it
/// looks like one. Colors written as `#AARRGGBB` become ARGB ints.
Object? parseScalar(Object? v) {
  if (v is! String) return v;
  if (v.startsWith('#')) return readColor(v).toARGB32();
  return num.tryParse(v) ?? v;
}

T readEnum<T extends Enum>(List<T> values, Object? v, T fallback) {
  if (v is String) {
    for (final e in values) {
      if (e.name == v) return e;
    }
  }
  return fallback;
}

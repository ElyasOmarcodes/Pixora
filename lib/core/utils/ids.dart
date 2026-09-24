import 'dart:math';

final Random _random = Random.secure();

/// Generates a short, URL-safe unique id (e.g. `k3f9x2q7a1`).
///
/// Ids are used for documents, layers, effects and assets. They only need to
/// be unique inside one installation, so 60 bits of randomness plus a time
/// component is plenty.
String newId([String prefix = '']) {
  const chars = '0123456789abcdefghijklmnopqrstuvwxyz';
  final time = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final buffer = StringBuffer(prefix)..write(time);
  for (var i = 0; i < 6; i++) {
    buffer.write(chars[_random.nextInt(chars.length)]);
  }
  return buffer.toString();
}

import 'dart:convert';
import 'dart:typed_data';

import '../document/model/document.dart';
import '../document/model/layer.dart';

/// How an exported project carries the fonts its text uses.
enum FontEmbedding {
  /// Not included: the text falls back to another font where it's missing.
  none,

  /// Included as font files: whoever opens the project gets the fonts too.
  files,

  /// Included encoded: the project shows them, but they are never added
  /// to the recipient's fonts nor written out as font files again.
  locked,
}

/// Fonts embedded in a project travel with its assets under reserved ids
/// (`font:p:<family>` plain, `font:l:<family>` locked), so every save and
/// export path keeps them without special handling. In the `.pixora` file
/// they live in `fonts/`; locked ones scrambled so they can't simply be
/// unzipped and installed.
///
/// Locking is obfuscation, not encryption: it stops casual copying (the
/// file inside the project is not a font), not a determined attacker.
abstract final class ProjectFonts {
  static const _prefix = 'font:';

  static bool isKey(String assetId) => assetId.startsWith(_prefix);

  static String key(String family, {required bool locked}) =>
      '$_prefix${locked ? 'l' : 'p'}:$family';

  /// (family, locked) of a font asset id.
  static (String, bool)? parse(String assetId) {
    if (!isKey(assetId) || assetId.length < 7) return null;
    return (assetId.substring(7), assetId[5] == 'l');
  }

  /// Font families the document's text uses.
  static Set<String> usedFamilies(PixDocument doc) => {
    for (final l in doc.allLayers)
      if (l is TextLayer) l.fontFamily,
  };

  /// Whether the asset [assetId] is worth keeping with [doc]: a font its
  /// text still uses (other assets are kept by their own rules).
  static bool keepsFont(PixDocument doc, String assetId) {
    final p = parse(assetId);
    return p != null && usedFamilies(doc).contains(p.$1);
  }

  /// Scrambles (or unscrambles — it is symmetric) a locked font's bytes
  /// with a key stream derived from its family name.
  static Uint8List scramble(Uint8List bytes, String family) {
    var s = 0x9E3779B9;
    for (final c in utf8.encode('pixora-font:$family')) {
      s = ((s ^ c) * 0x01000193) & 0xFFFFFFFF;
    }
    if (s == 0) s = 0x2545F491;
    final out = Uint8List(bytes.length);
    for (var i = 0; i < bytes.length; i++) {
      // xorshift32
      s ^= (s << 13) & 0xFFFFFFFF;
      s ^= s >> 17;
      s ^= (s << 5) & 0xFFFFFFFF;
      out[i] = bytes[i] ^ (s & 0xFF);
    }
    return out;
  }
}

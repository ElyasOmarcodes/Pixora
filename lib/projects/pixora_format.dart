import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../core/utils/json.dart';
import '../document/model/document.dart';
import 'project_store.dart';

/// The `.pixora` project file.
///
/// A ZIP container — the same approach as OpenRaster (`.ora`), Krita
/// (`.kra`) and OpenDocument — holding:
///
/// ```
/// mimetype          "application/vnd.pixora.project+zip" (first, stored)
/// document.xml      the layer tree and every property, human-readable
/// assets/<id>.<ext> original image bytes, stored as-is (no recompression)
/// thumbnail.png     preview for file browsers and the projects screen
/// ```
///
/// Why XML: Photoshop's PSD is a proprietary binary format, so there is
/// nothing to copy there. XML is what the open layered formats (OpenRaster,
/// Krita, SVG, ODF) use for exactly this job: a deep, ordered tree of
/// elements with attributes, readable in any text editor and friendly to
/// diffing and hand repair. Binary data never goes into the XML; it lives
/// next to it in the ZIP, so even huge projects keep a small document.
///
/// The XML mirrors the document model generically (maps become elements,
/// scalars become attributes, lists become child elements), so new model
/// fields are saved automatically and unknown ones are ignored by older
/// readers.
abstract final class PixoraFormat {
  static const String extension = 'pixora';
  static const String mimeType = 'application/vnd.pixora.project+zip';
  static const int version = PixDocument.formatVersion;

  /// Encodes a project into `.pixora` bytes.
  static Uint8List encode(
    PixDocument doc,
    Map<String, Uint8List> assets, {
    Uint8List? thumbnail,
    String generator = 'Pixora',
  }) {
    final archive = Archive()
      ..add(
        ArchiveFile.noCompress(
          'mimetype',
          mimeType.length,
          utf8.encode(mimeType),
        ),
      );

    final keep = doc.referencedAssets;
    final paths = <String, String>{};
    for (final id in keep) {
      final bytes = assets[id];
      if (bytes == null) continue;
      final path = 'assets/$id.${_guessExtension(bytes)}';
      paths[id] = path;
      archive.add(ArchiveFile.noCompress(path, bytes.length, bytes));
    }

    final xml = documentToXml(doc, generator: generator, assetPaths: paths);
    archive.add(ArchiveFile.bytes('document.xml', utf8.encode(xml)));
    if (thumbnail != null) {
      archive.add(
        ArchiveFile.noCompress('thumbnail.png', thumbnail.length, thumbnail),
      );
    }
    return ZipEncoder().encodeBytes(
      archive,
      level: DeflateLevel.bestCompression,
    );
  }

  /// Decodes `.pixora` bytes. Throws [FormatException] for anything that
  /// isn't a Pixora project.
  static (StoredProject project, Uint8List? thumbnail) decode(Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      throw FormatException('Not a Pixora project (not a ZIP): $e');
    }
    final docFile = archive.find('document.xml');
    if (docFile == null) {
      throw const FormatException('Not a Pixora project (no document.xml)');
    }
    final (doc, assetPaths) = documentFromXml(
      utf8.decode(docFile.readBytes()!),
    );
    final assets = <String, Uint8List>{};
    for (final id in doc.referencedAssets) {
      final path = assetPaths[id] ?? _findAsset(archive, id);
      final bytes = path == null ? null : archive.find(path)?.readBytes();
      if (bytes != null) assets[id] = bytes;
    }
    return (
      StoredProject(doc, assets),
      archive.find('thumbnail.png')?.readBytes(),
    );
  }

  /// Reads the `<document>` attributes (id, name, size) from raw
  /// `document.xml` bytes, for fast listings.
  static Json peekXml(List<int> documentXml) {
    final root = XmlDocument.parse(utf8.decode(documentXml)).rootElement;
    final doc = root.getElement('document');
    if (doc == null) throw const FormatException('no <document>');
    return {for (final a in doc.attributes) a.name.local: a.value};
  }

  static String? _findAsset(Archive archive, String id) {
    for (final f in archive) {
      if (f.name.startsWith('assets/$id')) return f.name;
    }
    return null;
  }

  static String _guessExtension(Uint8List b) {
    bool starts(List<int> sig) {
      if (b.length < sig.length) return false;
      for (var i = 0; i < sig.length; i++) {
        if (b[i] != sig[i]) return false;
      }
      return true;
    }

    if (starts([0x89, 0x50, 0x4E, 0x47])) return 'png';
    if (starts([0xFF, 0xD8, 0xFF])) return 'jpg';
    if (starts([0x47, 0x49, 0x46])) return 'gif';
    if (starts([0x52, 0x49, 0x46, 0x46]) && b.length > 12 && b[8] == 0x57) {
      return 'webp';
    }
    if (starts([0x42, 0x4D])) return 'bmp';
    return 'bin';
  }

  // ------------------------------------------------------------------ XML

  /// Keys whose values are lists, and the element name used per item.
  static const Map<String, String> _lists = {
    'layers': 'layer',
    'children': 'layer',
    'effects': 'effect',
    'colors': 'color',
    'stops': 'stop',
    'vertical': 'x',
    'horizontal': 'y',
    'xLines': 'x',
    'yLines': 'y',
    'mask': 'stroke',
    'spans': 'span',
    'strokes': 'stroke',
    'contours': 'contour',
  };

  /// Keys written as child text elements instead of attributes (free text
  /// that may be long or multi-line).
  static const Set<String> _textElements = {'text', 'd', 'nodes'};

  static String documentToXml(
    PixDocument doc, {
    String generator = 'Pixora',
    Map<String, String> assetPaths = const {},
  }) {
    final json = doc.toJson()..remove('format');
    final b = XmlBuilder()..processing('xml', 'version="1.0" encoding="UTF-8"');
    b.element(
      'pixora',
      attributes: {'format': '$version', 'generator': generator},
      nest: () {
        _writeMap(b, 'document', json);
        if (assetPaths.isNotEmpty) {
          b.element(
            'assets',
            nest: () {
              for (final e in assetPaths.entries) {
                b.element('asset', attributes: {'id': e.key, 'path': e.value});
              }
            },
          );
        }
      },
    );
    return b.buildDocument().toXmlString(
      pretty: true,
      indent: '  ',
      // Free text must survive exactly (newlines, repeated spaces).
      preserveWhitespace: (node) =>
          node is XmlElement && _textElements.contains(node.name.local),
    );
  }

  static (PixDocument, Map<String, String>) documentFromXml(String xml) {
    final root = XmlDocument.parse(xml).rootElement;
    if (root.name.local != 'pixora') {
      throw const FormatException('Root element is not <pixora>');
    }
    final docEl = root.getElement('document');
    if (docEl == null) throw const FormatException('Missing <document>');
    final json = readMap(_readElement(docEl, 'document'));
    final paths = <String, String>{
      for (final a
          in root.getElement('assets')?.findElements('asset') ??
              const <XmlElement>[])
        a.getAttribute('id') ?? '': a.getAttribute('path') ?? '',
    };
    return (PixDocument.fromJson(json), paths);
  }

  static String _scalar(Object v) => switch (v) {
    double d when d == d.roundToDouble() && d.abs() < 1e15 =>
      d.toInt().toString(),
    _ => v.toString(),
  };

  static void _writeMap(XmlBuilder b, String tag, Json m) {
    final attrs = <String, String>{};
    final nested = <MapEntry<String, Object?>>[];
    for (final e in m.entries) {
      final v = e.value;
      if (v == null) continue;
      if (v is Map ||
          v is List ||
          (_textElements.contains(e.key) && v is String)) {
        nested.add(e);
      } else {
        attrs[e.key] = _scalar(v as Object);
      }
    }
    b.element(
      tag,
      attributes: attrs,
      nest: () {
        for (final e in nested) {
          final v = e.value;
          if (v is String) {
            b.element(e.key, nest: () => b.text(v));
          } else if (v is Map) {
            _writeMap(b, e.key, readMap(v));
          } else if (v is List) {
            final item = _lists[e.key] ?? 'item';
            b.element(
              e.key,
              nest: () {
                for (final x in v) {
                  if (x is Map) {
                    _writeMap(b, item, readMap(x));
                  } else if (x != null) {
                    b.element(item, nest: () => b.text(_scalar(x as Object)));
                  }
                }
              },
            );
          }
        }
      },
    );
  }

  static Object _readElement(XmlElement el, String key) {
    if (_lists.containsKey(key)) {
      return [
        for (final c in el.childElements)
          if (c.attributes.isEmpty && c.childElements.isEmpty)
            c.innerText
          else
            _readElement(c, c.name.local),
      ];
    }
    if (el.attributes.isEmpty && el.childElements.isEmpty) return el.innerText;
    final m = <String, dynamic>{
      for (final a in el.attributes) a.name.local: a.value,
    };
    for (final c in el.childElements) {
      m[c.name.local] = _readElement(c, c.name.local);
    }
    return m;
  }
}

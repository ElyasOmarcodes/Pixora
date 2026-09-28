import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixora/document/model/document.dart';
import 'package:pixora/document/model/layer.dart';
import 'package:pixora/projects/pixora_format.dart';
import 'package:pixora/projects/project_fonts.dart';

void main() {
  final ttf = File('assets/fonts/Anton-Regular.ttf').readAsBytesSync();
  PixDocument doc(List<String> families) => PixDocument(
    name: 't',
    width: 100,
    height: 100,
    layers: [
      for (final f in families)
        TextLayer(
          LayerProps(name: f),
          text: 'Hi',
          fontFamily: f,
        ),
    ],
  );

  test('plain and locked fonts travel with the project', () {
    final d = doc(['Mine', 'Secret']);
    final bytes = PixoraFormat.encode(d, {
      ProjectFonts.key('Mine', locked: false): ttf,
      ProjectFonts.key('Secret', locked: true): ttf,
      // No text uses it: left out.
      ProjectFonts.key('Unused', locked: false): ttf,
    });
    final zip = ZipDecoder().decodeBytes(bytes);
    final files = [for (final f in zip) f.name];
    expect(files.where((n) => n.startsWith('fonts/')).length, 2);
    // The locked one is not a font file inside the zip.
    final locked = zip.firstWhere((f) => f.name.endsWith('.pxfont'));
    final raw = Uint8List.fromList(locked.readBytes()!);
    expect(raw.length, ttf.length);
    expect(raw.sublist(0, 4), isNot(ttf.sublist(0, 4)));

    final (project, _) = PixoraFormat.decode(bytes);
    expect(project.assets[ProjectFonts.key('Mine', locked: false)], ttf);
    expect(project.assets[ProjectFonts.key('Secret', locked: true)], ttf);
    expect(project.assets.keys.any((k) => k.contains('Unused')), isFalse);
  });

  test('keys round-trip', () {
    final k = ProjectFonts.key('My Font', locked: true);
    expect(ProjectFonts.parse(k), ('My Font', true));
    expect(ProjectFonts.parse('as_123'), isNull);
  });
}

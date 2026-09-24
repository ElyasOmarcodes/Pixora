import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixora/document/effects/effect_registry.dart';
import 'package:pixora/document/model/blend.dart';
import 'package:pixora/document/model/document.dart';
import 'package:pixora/document/model/fill.dart';
import 'package:pixora/document/model/layer.dart';
import 'package:pixora/document/model/layer_transform.dart';
import 'package:pixora/projects/pixora_file_store.dart';
import 'package:pixora/projects/pixora_format.dart';

final _png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3, 4, 5]);

PixDocument richDoc() => PixDocument(
  name: 'پروژه "1" & <test>',
  width: 1080,
  height: 1350,
  background: PixFill.linear(const [
    Color(0xFF0A84FF),
    Color(0xFF021B4D),
  ], angle: 90),
  layers: [
    RasterLayer(
      LayerProps(name: '2024'),
      assetId: 'a1',
      width: 800,
      height: 600,
    ),
    GroupLayer(
      LayerProps(
        name: 'Folder',
        opacity: 0.8,
        blendMode: PixBlendMode.multiply,
      ),
      expanded: false,
      children: [
        ShapeLayer(
          LayerProps(
            name: 'Star',
            clip: true,
            transform: const LayerTransform(
              x: 100,
              y: 200,
              rotation: 0.5,
              scaleX: -2,
            ),
            effects: [
              EffectRegistry.instance['shadow']!.create({'color': 0xFF112233}),
              EffectRegistry.instance['brightness']!.create({'value': 0.25}),
            ],
          ),
          shape: ShapeKind.star,
          width: 300,
          height: 300,
          sides: 7,
          strokeWidth: 4,
          strokeColor: const Color(0x80FF0000),
        ),
        TextLayer(
          LayerProps(name: 'true', locked: true),
          text: 'هجران عمر\nline two   with  spaces',
          fontSize: 120.5,
          italic: true,
        ),
      ],
    ),
  ],
);

void main() {
  test('XML round-trip preserves the whole document', () {
    final doc = richDoc();
    final xml = PixoraFormat.documentToXml(doc);
    expect(xml, contains('<layer kind="group"'));
    expect(xml, contains('<text>'));
    final (back, _) = PixoraFormat.documentFromXml(xml);
    expect(back, doc);
  });

  test('.pixora archive round-trip with assets and thumbnail', () {
    final doc = richDoc();
    final bytes = PixoraFormat.encode(doc, {
      'a1': _png,
      'unused': _png,
    }, thumbnail: _png);
    final (project, thumb) = PixoraFormat.decode(bytes);
    expect(project.document, doc);
    expect(project.assets.keys, ['a1']);
    expect(project.assets['a1'], _png);
    expect(thumb, _png);
  });

  test('invalid files are rejected with FormatException', () {
    expect(
      () => PixoraFormat.decode(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
  });

  test('file store: save, list, rename, load, delete', () async {
    final dir = await Directory.systemTemp.createTemp('pixora_test');
    addTearDown(() => dir.delete(recursive: true));
    final store = PixoraFileStore(dir);
    final doc = richDoc();

    await store.save(doc, {'a1': _png}, _png);
    var list = await store.list();
    expect(list.single.id, doc.id);
    expect(list.single.thumbnail, _png);
    expect(dir.listSync().whereType<File>().single.path, endsWith('.pixora'));

    await store.save(doc.copyWith(name: 'Renamed'), {'a1': _png}, _png);
    list = await store.list();
    expect(list.single.name, 'Renamed');
    expect(
      dir.listSync().whereType<File>().single.path,
      endsWith('Renamed.pixora'),
    );

    final loaded = await store.load(doc.id);
    expect(loaded!.document.name, 'Renamed');
    expect(loaded.assets['a1'], _png);

    await store.delete(doc.id);
    expect(await store.list(), isEmpty);
  });
}

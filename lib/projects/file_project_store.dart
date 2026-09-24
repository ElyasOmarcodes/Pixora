import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../core/utils/json.dart';
import '../document/model/document.dart';
import 'project_store.dart';

/// Stores each project in its own folder:
///
/// ```
/// <root>/<projectId>/project.json   document + metadata
/// <root>/<projectId>/thumb.png      preview for the projects screen
/// <root>/<projectId>/assets/<id>    encoded images used by raster layers
/// ```
///
/// Writes go to a temporary file first and are then renamed, so a crash
/// mid-save never corrupts a project.
class FileProjectStore implements ProjectStore {
  FileProjectStore(this.root);

  final Directory root;

  Directory _dir(String id) => Directory('${root.path}/$id');
  File _json(String id) => File('${_dir(id).path}/project.json');
  File _thumb(String id) => File('${_dir(id).path}/thumb.png');
  Directory _assets(String id) => Directory('${_dir(id).path}/assets');

  @override
  Future<List<ProjectSummary>> list() async {
    if (!await root.exists()) return [];
    final out = <ProjectSummary>[];
    await for (final entity in root.list()) {
      if (entity is! Directory) continue;
      final id = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
      try {
        final file = _json(id);
        if (!await file.exists()) continue;
        final json = readMap(jsonDecode(await file.readAsString()));
        final doc = readMap(json['document']);
        final thumbFile = _thumb(id);
        out.add(
          ProjectSummary(
            id: id,
            name: readString(doc['name'], 'Untitled'),
            width: readDouble(doc['width'], 1080),
            height: readDouble(doc['height'], 1080),
            updatedAt:
                DateTime.tryParse(readString(json['updatedAt'])) ??
                (await file.lastModified()),
            thumbnail: await thumbFile.exists()
                ? await thumbFile.readAsBytes()
                : null,
          ),
        );
      } catch (_) {
        // Skip unreadable folders instead of failing the whole listing.
      }
    }
    out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return out;
  }

  @override
  Future<StoredProject?> load(String id) async {
    final file = _json(id);
    if (!await file.exists()) return null;
    final json = readMap(jsonDecode(await file.readAsString()));
    final doc = PixDocument.fromJson(readMap(json['document']));
    final assets = <String, Uint8List>{};
    for (final assetId in doc.referencedAssets) {
      final f = File('${_assets(id).path}/$assetId');
      if (await f.exists()) assets[assetId] = await f.readAsBytes();
    }
    return StoredProject(doc, assets);
  }

  @override
  Future<void> save(
    PixDocument document,
    Map<String, Uint8List> assets,
    Uint8List? thumbnail,
  ) async {
    final id = document.id;
    final assetDir = _assets(id);
    await assetDir.create(recursive: true);

    final keep = document.referencedAssets;
    for (final assetId in keep) {
      final f = File('${assetDir.path}/$assetId');
      final bytes = assets[assetId];
      if (bytes != null && !await f.exists()) await _atomicWrite(f, bytes);
    }
    await for (final f in assetDir.list()) {
      final name = f.uri.pathSegments.last;
      if (f is File && !keep.contains(name)) await f.delete();
    }

    final payload = jsonEncode({
      'app': 'pixora',
      'updatedAt': DateTime.now().toIso8601String(),
      'document': document.toJson(),
    });
    await _atomicWrite(_json(id), utf8.encode(payload));
    if (thumbnail != null) await _atomicWrite(_thumb(id), thumbnail);
  }

  @override
  Future<void> delete(String id) async {
    final dir = _dir(id);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  Future<void> _atomicWrite(File target, List<int> bytes) async {
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(target.path);
  }
}

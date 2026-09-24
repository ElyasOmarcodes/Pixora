import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';

import '../core/utils/json.dart';
import '../document/model/document.dart';
import 'pixora_format.dart';
import 'project_store.dart';

/// Keeps every project as one `.pixora` file in a folder the user can see
/// (e.g. `Documents/Pixora/Projects`). The files open in Pixora from any
/// file manager and can be copied, backed up or shared like any document.
class PixoraFileStore implements ProjectStore {
  PixoraFileStore(this.dir);

  final Directory dir;

  /// Document id → file, filled by [list] and updated by [save].
  final Map<String, File> _files = {};

  /// Listing cache keyed by path, invalidated by modification time.
  final Map<String, (DateTime, ProjectSummary)> _cache = {};

  String get path => dir.path;

  /// Where a project is stored, if known.
  File? fileOf(String id) => _files[id];

  @override
  Future<List<ProjectSummary>> list() async {
    if (!await dir.exists()) return [];
    final out = <ProjectSummary>[];
    final seen = <String>{};
    await for (final entity in dir.list()) {
      if (entity is! File ||
          !entity.path.toLowerCase().endsWith('.${PixoraFormat.extension}')) {
        continue;
      }
      try {
        final modified = await entity.lastModified();
        final cached = _cache[entity.path];
        final summary = cached != null && cached.$1 == modified
            ? cached.$2
            : await compute(_peek, entity.path).then(
                (r) => ProjectSummary(
                  id: readString(r.$1['id'], entity.path),
                  name: readString(r.$1['name'], 'Untitled'),
                  width: readDouble(r.$1['width'], 1080),
                  height: readDouble(r.$1['height'], 1080),
                  updatedAt: modified,
                  thumbnail: r.$2,
                ),
              );
        _cache[entity.path] = (modified, summary);
        // Two files with the same id (a manual copy): keep the newest.
        if (!seen.add(summary.id)) continue;
        _files[summary.id] = entity;
        out.add(summary);
      } catch (e) {
        debugPrint('Pixora: skipping unreadable ${entity.path}: $e');
      }
    }
    out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return out;
  }

  @override
  Future<StoredProject?> load(String id) async {
    final file = _files[id] ?? await _find(id);
    if (file == null || !await file.exists()) return null;
    final bytes = await file.readAsBytes();
    final (project, _) = await compute(PixoraFormat.decode, bytes);
    return project;
  }

  @override
  Future<void> save(
    PixDocument document,
    Map<String, Uint8List> assets,
    Uint8List? thumbnail,
  ) async {
    await dir.create(recursive: true);
    final keep = document.referencedAssets;
    final bytes = await compute(_encode, (
      document,
      {
        for (final e in assets.entries)
          if (keep.contains(e.key)) e.key: e.value,
      },
      thumbnail,
    ));

    final existing = _files[document.id] ?? await _find(document.id);
    final wanted = _fileNameFor(document.name);
    File file;
    if (existing == null) {
      file = await _uniqueFile(wanted);
    } else if (_baseName(existing.path) != wanted) {
      // The project was renamed: rename the file too (if the name is free).
      final target = await _uniqueFile(wanted, except: existing.path);
      try {
        file = await existing.rename(target.path);
      } catch (_) {
        file = existing;
      }
    } else {
      file = existing;
    }
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(file.path);
    _files[document.id] = file;
  }

  @override
  Future<void> delete(String id) async {
    final file = _files.remove(id) ?? await _find(id);
    if (file != null && await file.exists()) await file.delete();
  }

  /// The file holding project [id], if it exists.
  Future<File?> fileFor(String id) async => _files[id] ?? await _find(id);

  Future<File?> _find(String id) async {
    await list();
    return _files[id];
  }

  static String _baseName(String path) {
    final name = path.split(Platform.pathSeparator).last;
    return name.substring(0, name.length - PixoraFormat.extension.length - 1);
  }

  static String _fileNameFor(String projectName) {
    final cleaned = projectName
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_')
        .trim()
        .replaceAll(RegExp(r'\.+$'), '');
    return cleaned.isEmpty ? 'Untitled' : cleaned;
  }

  Future<File> _uniqueFile(String base, {String? except}) async {
    for (var i = 1; ; i++) {
      final name = i == 1 ? base : '$base ($i)';
      final f = File(
        '${dir.path}${Platform.pathSeparator}$name.${PixoraFormat.extension}',
      );
      if (f.path == except || !await f.exists()) return f;
    }
  }
}

(Json, Uint8List?) _peek(String path) {
  final input = InputFileStream(path);
  try {
    final archive = ZipDecoder().decodeStream(input);
    final doc = archive.find('document.xml')?.readBytes();
    if (doc == null) throw const FormatException('no document.xml');
    final thumb = archive.find('thumbnail.png')?.readBytes();
    final meta = PixoraFormat.peekXml(doc);
    return (meta, thumb == null ? null : Uint8List.fromList(thumb));
  } finally {
    input.closeSync();
  }
}

Uint8List _encode((PixDocument, Map<String, Uint8List>, Uint8List?) a) =>
    PixoraFormat.encode(a.$1, a.$2, thumbnail: a.$3);

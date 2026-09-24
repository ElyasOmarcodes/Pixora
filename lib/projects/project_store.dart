import 'dart:typed_data';

import '../document/model/document.dart';

/// Lightweight listing entry for the projects screen.
class ProjectSummary {
  const ProjectSummary({
    required this.id,
    required this.name,
    required this.width,
    required this.height,
    required this.updatedAt,
    this.thumbnail,
  });

  final String id;
  final String name;
  final double width;
  final double height;
  final DateTime updatedAt;
  final Uint8List? thumbnail;
}

/// A project loaded for editing: the document plus its binary assets.
class StoredProject {
  const StoredProject(this.document, this.assets);
  final PixDocument document;
  final Map<String, Uint8List> assets;
}

/// Persistence backend for projects.
///
/// Implementations are chosen per platform by `PlatformServices` (files on
/// mobile/desktop, browser storage on the web), so nothing above this layer
/// cares where projects live.
abstract interface class ProjectStore {
  Future<List<ProjectSummary>> list();
  Future<StoredProject?> load(String id);

  /// Writes the document, any assets not yet stored and the thumbnail.
  /// Assets no longer referenced by the document are removed.
  Future<void> save(
    PixDocument document,
    Map<String, Uint8List> assets,
    Uint8List? thumbnail,
  );

  Future<void> delete(String id);
}

/// Volatile store used on the web and in tests.
class MemoryProjectStore implements ProjectStore {
  final Map<String, (PixDocument, Map<String, Uint8List>, Uint8List?, DateTime)>
  _data = {};

  @override
  Future<List<ProjectSummary>> list() async {
    final items = [
      for (final e in _data.values)
        ProjectSummary(
          id: e.$1.id,
          name: e.$1.name,
          width: e.$1.width,
          height: e.$1.height,
          updatedAt: e.$4,
          thumbnail: e.$3,
        ),
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return items;
  }

  @override
  Future<StoredProject?> load(String id) async {
    final e = _data[id];
    return e == null ? null : StoredProject(e.$1, Map.of(e.$2));
  }

  @override
  Future<void> save(
    PixDocument document,
    Map<String, Uint8List> assets,
    Uint8List? thumbnail,
  ) async {
    final keep = document.referencedAssets;
    _data[document.id] = (
      document,
      {
        for (final e in assets.entries)
          if (keep.contains(e.key)) e.key: e.value,
      },
      thumbnail ?? _data[document.id]?.$3,
      DateTime.now(),
    );
  }

  @override
  Future<void> delete(String id) async => _data.remove(id);
}

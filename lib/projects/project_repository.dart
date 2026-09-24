import 'package:flutter/foundation.dart';

import '../core/utils/ids.dart';
import '../document/model/document.dart';
import 'pixora_format.dart';
import 'project_store.dart';

/// App-level access to projects; notifies listeners when the list changes so
/// the projects screen stays current.
class ProjectRepository extends ChangeNotifier {
  ProjectRepository(this._store);

  ProjectStore _store;

  /// Swaps the backing store (e.g. after the user moves the Pixora folder).
  void setStore(ProjectStore store) {
    _store = store;
    notifyListeners();
  }

  Future<List<ProjectSummary>> list() => _store.list();

  Future<StoredProject?> load(String id) => _store.load(id);

  Future<bool> exists(String id) async =>
      (await _store.list()).any((s) => s.id == id);

  Future<Uint8List?> _thumbnailOf(String id) async => (await _store.list())
      .where((s) => s.id == id)
      .map((s) => s.thumbnail)
      .firstOrNull;

  Future<void> save(
    PixDocument doc,
    Map<String, Uint8List> assets, {
    Uint8List? thumbnail,
  }) async {
    await _store.save(doc, assets, thumbnail ?? await _thumbnailOf(doc.id));
    notifyListeners();
  }

  Future<void> delete(String id) async {
    await _store.delete(id);
    notifyListeners();
  }

  Future<void> rename(String id, String name) async {
    final p = await _store.load(id);
    if (p == null) return;
    await save(p.document.copyWith(name: name), p.assets);
  }

  Future<String?> duplicate(String id, {required String nameSuffix}) async {
    final p = await _store.load(id);
    if (p == null) return null;
    final copy = _withNewId(p.document, name: '${p.document.name} $nameSuffix');
    await save(copy, p.assets, thumbnail: await _thumbnailOf(id));
    return copy.id;
  }

  /// Packs a stored project into `.pixora` bytes (for sharing / backup).
  Future<Uint8List?> exportArchive(String id) async {
    final p = await _store.load(id);
    if (p == null) return null;
    final thumb = await _thumbnailOf(id);
    return compute(_encode, (p.document, p.assets, thumb));
  }

  /// Unpacks `.pixora` bytes and adds the project to the library. If a
  /// project with the same id already exists the import becomes a copy, so
  /// nothing is ever overwritten. Throws [FormatException] for invalid files.
  Future<StoredProject> importArchive(Uint8List bytes) async {
    final (project, thumb) = await compute(PixoraFormat.decode, bytes);
    final exists = (await _store.list()).any(
      (s) => s.id == project.document.id,
    );
    final doc = exists ? _withNewId(project.document) : project.document;
    await save(doc, project.assets, thumbnail: thumb);
    return StoredProject(doc, project.assets);
  }

  static PixDocument _withNewId(PixDocument src, {String? name}) => PixDocument(
    id: newId('doc'),
    name: name ?? src.name,
    width: src.width,
    height: src.height,
    background: src.background,
    layers: src.layers,
    guides: src.guides,
    dpi: src.dpi,
  );

  /// Saves [doc] as a brand-new project (new id, [name]) and returns its id.
  Future<String> saveAsCopy(
    PixDocument doc,
    Map<String, Uint8List> assets, {
    required String name,
    Uint8List? thumbnail,
  }) async {
    final copy = _withNewId(doc, name: name);
    await save(copy, assets, thumbnail: thumbnail);
    return copy.id;
  }
}

Uint8List _encode((PixDocument, Map<String, Uint8List>, Uint8List?) a) =>
    PixoraFormat.encode(a.$1, a.$2, thumbnail: a.$3);

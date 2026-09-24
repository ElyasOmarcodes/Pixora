import 'package:flutter/foundation.dart';

import '../core/utils/ids.dart';
import '../document/model/document.dart';
import 'project_store.dart';

/// App-level access to projects; notifies listeners when the list changes so
/// the projects screen stays current.
class ProjectRepository extends ChangeNotifier {
  ProjectRepository(this._store);

  final ProjectStore _store;

  Future<List<ProjectSummary>> list() => _store.list();

  Future<StoredProject?> load(String id) => _store.load(id);

  Future<void> save(
    PixDocument doc,
    Map<String, Uint8List> assets, {
    Uint8List? thumbnail,
  }) async {
    await _store.save(doc, assets, thumbnail);
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
    final src = p.document;
    final copy = PixDocument(
      id: newId('doc'),
      name: '${src.name} $nameSuffix',
      width: src.width,
      height: src.height,
      background: src.background,
      layers: src.layers,
    );
    final thumb = (await _store.list())
        .where((s) => s.id == id)
        .map((s) => s.thumbnail)
        .firstOrNull;
    await save(copy, p.assets, thumbnail: thumb);
    return copy.id;
  }
}

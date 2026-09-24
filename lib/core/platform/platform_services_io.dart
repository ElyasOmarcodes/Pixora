import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../projects/legacy_folder_store.dart';
import '../../projects/pixora_file_store.dart';
import '../../projects/pixora_format.dart';
import '../../projects/project_store.dart';
import 'platform_info.dart';
import 'platform_services.dart';

PlatformServices createPlatformServices(PlatformInfo info) =>
    IoPlatformServices(info);

/// Android, iOS, Windows, macOS and Linux.
///
/// Folder layout (like PixelLab / PicsArt, a visible "Pixora" folder):
///
/// | Platform | Projects                               | Exports                  |
/// |----------|----------------------------------------|--------------------------|
/// | Android  | `Documents/Pixora/Projects` *          | Gallery › Pixora album   |
/// | iOS      | Files › On My iPhone › Pixora › Projects | Photos › Pixora album  |
/// | Desktop  | `Documents/Pixora/Projects` (movable)  | `Documents/Pixora/Exports` |
///
/// * If the public Documents folder isn't writable (very old or locked-down
///   Android), projects fall back to the app's own external folder.
class IoPlatformServices extends PlatformServices {
  IoPlatformServices(super.info);

  static const String _folder = 'Pixora';
  late StorageInfo _storage;

  @override
  StorageInfo get storage => _storage;

  String get _sep => Platform.pathSeparator;

  @override
  Future<ProjectStore> openProjectStore({String? customRoot}) async {
    final (root, isDefault) = await _resolveRoot(customRoot);
    final projects = Directory('${root.path}${_sep}Projects');
    await projects.create(recursive: true);
    final store = PixoraFileStore(projects);

    Directory? exports;
    if (info.isDesktop) {
      exports = Directory('${root.path}${_sep}Exports');
    }
    _storage = StorageInfo(
      projectsPath: projects.path,
      exportDestination: info.isMobile
          ? ExportDestination.gallery
          : ExportDestination.folder,
      exportsPath: exports?.path,
      canChangeFolder: info.isDesktop,
      isDefault: isDefault,
    );
    await _migrateLegacy(store);
    return store;
  }

  Future<(Directory, bool)> _resolveRoot(String? custom) async {
    if (custom != null && info.isDesktop) {
      final d = Directory(custom);
      if (await _writable(d)) return (d, false);
    }
    if (info.isAndroid) {
      final ext = await getExternalStorageDirectory();
      if (ext != null) {
        // /storage/emulated/0/Android/data/<pkg>/files → /storage/emulated/0
        final i = ext.path.indexOf('${_sep}Android$_sep');
        if (i > 0) {
          final public = Directory(
            '${ext.path.substring(0, i)}${_sep}Documents$_sep$_folder',
          );
          if (await _writable(public)) return (public, true);
          // Android 9 and older need the storage permission first.
          try {
            if (await Gal.requestAccess(toAlbum: true) &&
                await _writable(public)) {
              return (public, true);
            }
          } catch (_) {}
        }
        return (Directory('${ext.path}$_sep$_folder'), true);
      }
    }
    // iOS: app Documents (exposed in the Files app). Desktop: ~/Documents.
    final docs = await getApplicationDocumentsDirectory();
    return (
      Directory(info.isIOS ? docs.path : '${docs.path}$_sep$_folder'),
      true,
    );
  }

  Future<bool> _writable(Directory d) async {
    try {
      await d.create(recursive: true);
      final probe = File('${d.path}$_sep.pixora_probe');
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  static const _fontExts = ['ttf', 'otf'];

  @override
  Future<List<PickedFile>> pickFontFiles() async {
    // Font MIME types are unreliable on phones, so accept any file there
    // and filter by extension.
    final files = await FilePicker.pickFiles(
      type: info.isMobile ? FileType.any : FileType.custom,
      allowedExtensions: info.isMobile ? null : _fontExts,
    );
    return [
      for (final f in files)
        if (_fontExts.contains(f.name.split('.').last.toLowerCase()))
          PickedFile(f.name, await f.readAsBytes()),
    ];
  }

  Future<Directory> _fontDir() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}${_sep}fonts').create(recursive: true);
  }

  @override
  Future<void> saveUserFont(String fileName, Uint8List bytes) async {
    final dir = await _fontDir();
    await File('${dir.path}$_sep$fileName').writeAsBytes(bytes, flush: true);
  }

  @override
  Future<List<PickedFile>> loadUserFonts() async {
    try {
      final dir = await _fontDir();
      return [
        await for (final e in dir.list())
          if (e is File)
            PickedFile(e.uri.pathSegments.last, await e.readAsBytes()),
      ];
    } catch (e) {
      debugPrint('Pixora: could not load user fonts: $e');
      return const [];
    }
  }

  @override
  Future<void> deleteUserFont(String fileName) async {
    final f = File('${(await _fontDir()).path}$_sep$fileName');
    if (await f.exists()) await f.delete();
  }

  /// Converts 0.1-style project folders into `.pixora` files, once.
  Future<void> _migrateLegacy(PixoraFileStore store) async {
    final base = info.isMobile
        ? await getApplicationDocumentsDirectory()
        : await getApplicationSupportDirectory();
    final old = Directory('${base.path}${_sep}projects');
    if (!await old.exists()) return;
    try {
      final legacy = LegacyFolderStore(old);
      for (final s in await legacy.list()) {
        final p = await legacy.load(s.id);
        if (p != null) await store.save(p.document, p.assets, s.thumbnail);
      }
      await old.rename('${old.path}_migrated');
    } catch (e) {
      debugPrint('Pixora: legacy migration failed: $e');
    }
  }

  @override
  Future<PickedFile?> pickImage() async {
    final file = await FilePicker.pickFile(type: FileType.image);
    if (file == null) return null;
    return PickedFile(file.name, await file.readAsBytes());
  }

  @override
  Future<PickedFile?> pickProjectFile() async {
    // Custom extensions aren't reliably filterable on Android/iOS (no MIME
    // type is registered for .pixora), so accept any file and validate.
    final file = await FilePicker.pickFile(
      type: info.isMobile ? FileType.any : FileType.custom,
      allowedExtensions: info.isMobile ? null : [PixoraFormat.extension],
    );
    if (file == null) return null;
    return PickedFile(file.name, await file.readAsBytes());
  }

  @override
  Future<String?> pickFolder() =>
      info.isDesktop ? FilePicker.getDirectoryPath() : Future.value(null);

  @override
  Future<ExportResult> exportImage(
    Uint8List bytes,
    String fileName,
    String mimeType,
  ) async {
    if (info.isMobile) {
      try {
        if (!await Gal.hasAccess(toAlbum: true)) {
          await Gal.requestAccess(toAlbum: true);
        }
        final dot = fileName.lastIndexOf('.');
        await Gal.putImageBytes(
          bytes,
          album: _folder,
          name: dot > 0 ? fileName.substring(0, dot) : fileName,
        );
        return const ExportResult(SaveOutcome.saved, ExportDestination.gallery);
      } catch (e) {
        debugPrint('Pixora: gallery save failed: $e');
        return const ExportResult(
          SaveOutcome.failed,
          ExportDestination.gallery,
        );
      }
    }
    try {
      final dir = Directory(_storage.exportsPath!);
      await dir.create(recursive: true);
      final file = await _unique(dir, fileName);
      await file.writeAsBytes(bytes, flush: true);
      return ExportResult(
        SaveOutcome.saved,
        ExportDestination.folder,
        location: file.path,
      );
    } catch (e) {
      debugPrint('Pixora: export failed: $e');
      return const ExportResult(SaveOutcome.failed, ExportDestination.folder);
    }
  }

  Future<File> _unique(Directory dir, String fileName) async {
    final dot = fileName.lastIndexOf('.');
    final base = dot > 0 ? fileName.substring(0, dot) : fileName;
    final ext = dot > 0 ? fileName.substring(dot) : '';
    for (var i = 1; ; i++) {
      final f = File('${dir.path}$_sep${i == 1 ? base : '$base ($i)'}$ext');
      if (!await f.exists()) return f;
    }
  }

  @override
  Future<SaveOutcome> saveFileAs(
    Uint8List bytes,
    String fileName,
    String mimeType,
  ) async {
    try {
      final uri = await FilePicker.saveFile(
        fileName: fileName,
        bytes: bytes,
        mimeType: mimeType,
        initialDirectory: _storage.exportsPath,
      );
      return uri == null ? SaveOutcome.cancelled : SaveOutcome.saved;
    } catch (e) {
      debugPrint('Pixora: save failed: $e');
      return SaveOutcome.failed;
    }
  }

  @override
  Future<void> share(Uint8List bytes, String fileName, String mimeType) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}$_sep$fileName');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: mimeType)],
        title: fileName,
      ),
    );
  }

  @override
  Future<List<PickedFile>> launchFiles(List<String> args) async {
    final out = <PickedFile>[];
    for (final a in args) {
      if (!a.toLowerCase().endsWith('.${PixoraFormat.extension}')) continue;
      final f = File(a);
      if (await f.exists()) {
        out.add(PickedFile(f.uri.pathSegments.last, await f.readAsBytes()));
      }
    }
    return out;
  }
}

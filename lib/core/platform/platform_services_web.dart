import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

import '../../projects/project_store.dart';
import 'platform_info.dart';
import 'platform_services.dart';

PlatformServices createPlatformServices(PlatformInfo info) =>
    WebPlatformServices(info);

/// Browser build (mainly for previews and quick tests). Projects live in
/// memory; use "Export project file" to keep them.
class WebPlatformServices extends PlatformServices {
  WebPlatformServices(super.info);

  final MemoryProjectStore _store = MemoryProjectStore();

  @override
  Future<ProjectStore> openProjectStore({String? customRoot}) async => _store;

  @override
  StorageInfo get storage => const StorageInfo(
    projectsPath: 'Browser memory',
    exportDestination: ExportDestination.download,
  );

  Future<PickedFile?> _pick(FileType type) async {
    final file = await FilePicker.pickFile(type: type);
    if (file == null) return null;
    return PickedFile(file.name, await file.readAsBytes());
  }

  @override
  Future<PickedFile?> pickImage() => _pick(FileType.image);

  @override
  Future<PickedFile?> pickProjectFile() => _pick(FileType.any);

  @override
  Future<List<PickedFile>> pickFontFiles() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['ttf', 'otf'],
    );
    return [for (final f in files) PickedFile(f.name, await f.readAsBytes())];
  }

  @override
  Future<ExportResult> exportImage(
    Uint8List bytes,
    String fileName,
    String mimeType,
  ) async {
    final r = await saveFileAs(bytes, fileName, mimeType);
    return ExportResult(r, ExportDestination.download);
  }

  @override
  Future<SaveOutcome> saveFileAs(
    Uint8List bytes,
    String fileName,
    String mimeType,
  ) async {
    try {
      await FilePicker.saveFile(
        fileName: fileName,
        bytes: bytes,
        mimeType: mimeType,
      );
      return SaveOutcome.saved;
    } catch (e) {
      debugPrint('Pixora: download failed: $e');
      return SaveOutcome.failed;
    }
  }

  @override
  Future<void> share(Uint8List bytes, String fileName, String mimeType) =>
      SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(bytes, mimeType: mimeType, name: fileName)],
        ),
      );
}

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

import '../../projects/project_store.dart';
import 'platform_info.dart';
import 'platform_services.dart';

PlatformServices createPlatformServices(PlatformInfo info) =>
    WebPlatformServices(info);

/// Browser build (mainly for previews and quick tests).
class WebPlatformServices extends PlatformServices {
  WebPlatformServices(super.info);

  final MemoryProjectStore _store = MemoryProjectStore();

  @override
  Future<ProjectStore> openProjectStore() async => _store;

  @override
  Future<PickedImage?> pickImage() async {
    final file = await FilePicker.pickFile(type: FileType.image);
    if (file == null) return null;
    return PickedImage(file.name, await file.readAsBytes());
  }

  @override
  Future<SaveOutcome> saveFile(
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

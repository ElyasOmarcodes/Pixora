import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../projects/file_project_store.dart';
import '../../projects/project_store.dart';
import 'platform_info.dart';
import 'platform_services.dart';

PlatformServices createPlatformServices(PlatformInfo info) =>
    IoPlatformServices(info);

/// Android, iOS, Windows, macOS and Linux.
class IoPlatformServices extends PlatformServices {
  IoPlatformServices(super.info);

  @override
  Future<ProjectStore> openProjectStore() async {
    // Mobile: app documents (backed up, private). Desktop: app support dir,
    // which keeps project folders out of the user's Documents clutter.
    final base = info.isMobile
        ? await getApplicationDocumentsDirectory()
        : await getApplicationSupportDirectory();
    final root = Directory('${base.path}${Platform.pathSeparator}projects');
    await root.create(recursive: true);
    return FileProjectStore(root);
  }

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
      final uri = await FilePicker.saveFile(
        fileName: fileName,
        bytes: bytes,
        mimeType: mimeType,
        type: FileType.image,
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
    final file = File('${dir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: mimeType)],
        title: fileName,
      ),
    );
  }
}

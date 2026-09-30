import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';
import 'package:web/web.dart' as web;

import '../../projects/project_store.dart';
import 'platform_info.dart';
import 'platform_services.dart';
import '../imaging/image_formats.dart';

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
  Future<PickedFile?> pickImage() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ImageFormats.openable,
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    return PickedFile(
      file.name,
      await ImageFormats.normalize(file.name, bytes),
    );
  }

  /// The browser's own encoder (a canvas): Dart runs on the page's only
  /// thread here, so encoding big pictures in Dart froze the page.
  @override
  Future<Uint8List?> encodeNative(
    ui.Image image,
    String format, {
    int quality = 92,
    bool lossless = false,
  }) async {
    final mime = switch (format) {
      'webp' => 'image/webp',
      'jpg' => 'image/jpeg',
      _ => null,
    };
    if (mime == null) return null;
    try {
      final data = await image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      if (data == null) return null;
      final w = image.width, h = image.height;
      final canvas =
          web.document.createElement('canvas') as web.HTMLCanvasElement
            ..width = w
            ..height = h;
      final ctx = canvas.getContext('2d') as web.CanvasRenderingContext2D;
      final pixels = Uint8ClampedList.view(
        data.buffer,
        data.offsetInBytes,
        data.lengthInBytes,
      );
      ctx.putImageData(web.ImageData(pixels.toJS, w, h.toJS), 0, 0);
      final done = Completer<web.Blob?>();
      canvas.toBlob(
        ((web.Blob? b) => done.complete(b)).toJS,
        mime,
        // Chrome writes lossless WebP at quality 1.
        (lossless ? 1.0 : quality / 100).toJS,
      );
      final blob = await done.future;
      canvas
        ..width = 0
        ..height = 0;
      // Browsers without the format hand back a PNG instead.
      if (blob == null || blob.type != mime) return null;
      final buffer = await blob.arrayBuffer().toDart;
      return buffer.toDart.asUint8List();
    } catch (e) {
      debugPrint('Pixora: browser encode failed: $e');
      return null;
    }
  }

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

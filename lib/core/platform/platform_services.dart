import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../projects/project_store.dart';
import 'platform_info.dart';
import 'platform_services_stub.dart'
    if (dart.library.io) 'platform_services_io.dart'
    if (dart.library.js_interop) 'platform_services_web.dart';

/// A file chosen by the user or handed to the app by the OS.
class PickedFile {
  const PickedFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

enum SaveOutcome { saved, cancelled, failed }

enum ExportDestination { gallery, folder, download }

class ExportResult {
  const ExportResult(this.outcome, this.destination, {this.location});
  final SaveOutcome outcome;
  final ExportDestination destination;

  /// Human-readable place the file went (a folder path), if applicable.
  final String? location;
}

/// Where projects and exports live on this device.
class StorageInfo {
  const StorageInfo({
    required this.projectsPath,
    required this.exportDestination,
    this.exportsPath,
    this.canChangeFolder = false,
    this.isDefault = true,
  });

  final String projectsPath;
  final ExportDestination exportDestination;
  final String? exportsPath;

  /// Desktop users can move the Pixora folder anywhere.
  final bool canChangeFolder;
  final bool isDefault;
}

/// Everything that genuinely differs between platforms, behind one API.
///
/// The right implementation is selected at compile time with conditional
/// imports (`dart:io` platforms vs. the web) and, inside it, at runtime via
/// [PlatformInfo] (e.g. gallery album on phones vs. a folder on desktops).
/// Screens only ever talk to this interface.
abstract class PlatformServices {
  PlatformServices(this.info);

  factory PlatformServices.create() =>
      createPlatformServices(PlatformInfo.current());

  final PlatformInfo info;

  /// Opens the persistent project store. [customRoot] overrides the Pixora
  /// folder on desktops.
  Future<ProjectStore> openProjectStore({String? customRoot});

  /// Valid after [openProjectStore].
  StorageInfo get storage;

  Future<PickedFile?> pickImage();

  /// Lets the user pick a `.pixora` project file.
  Future<PickedFile?> pickProjectFile();

  /// Lets the user pick a folder (desktop only; null elsewhere).
  Future<String?> pickFolder() async => null;

  /// Saves an exported image to the platform's natural place: the gallery
  /// (Pixora album) on phones, `Pixora/Exports` on desktops, a download on
  /// the web.
  Future<ExportResult> exportImage(
    Uint8List bytes,
    String fileName,
    String mimeType,
  );

  /// Lets the user choose where to save a file (save dialog / document
  /// picker / download).
  Future<SaveOutcome> saveFileAs(
    Uint8List bytes,
    String fileName,
    String mimeType,
  );

  /// Opens the system share sheet (or the closest equivalent).
  Future<void> share(Uint8List bytes, String fileName, String mimeType);

  /// Files the app was launched with (command line on desktop).
  Future<List<PickedFile>> launchFiles(List<String> args) async => const [];

  /// Whether a native share sheet is the natural way to hand off files.
  bool get prefersShare => info.isMobile;

  // ------------------------------------------------------------- open-with

  static const MethodChannel _openChannel = MethodChannel('pixora/open_file');
  final StreamController<PickedFile> _opened = StreamController.broadcast();
  final List<PickedFile> _pendingOpened = [];

  /// Files opened with Pixora from the OS ("Open with", double-click,
  /// share-to) while the app runs.
  Stream<PickedFile> get openedFiles => _opened.stream;

  /// Takes files that arrived before anyone listened (e.g. during launch).
  List<PickedFile> takePendingOpenedFiles() {
    final out = [..._pendingOpened];
    _pendingOpened.clear();
    return out;
  }

  /// Wires the native "open file" channel (Android, iOS, macOS) and reads
  /// command-line files (Windows, Linux).
  Future<void> initFileOpening(List<String> args) async {
    _pendingOpened.addAll(await launchFiles(args));
    if (!(info.isAndroid || info.isApple)) return;
    _openChannel.setMethodCallHandler((call) async {
      if (call.method == 'openFile') {
        final f = _decode(call.arguments);
        if (f != null) _deliver(f);
      }
    });
    try {
      final initial = await _openChannel.invokeMethod<List<Object?>>(
        'getInitialFiles',
      );
      for (final item in initial ?? const []) {
        final f = _decode(item);
        if (f != null) _pendingOpened.add(f);
      }
    } on MissingPluginException {
      // Older native shell without the channel.
    } catch (e) {
      debugPrint('Pixora: could not read launch files: $e');
    }
  }

  void _deliver(PickedFile f) {
    if (_opened.hasListener) {
      _opened.add(f);
    } else {
      _pendingOpened.add(f);
    }
  }

  static PickedFile? _decode(Object? v) {
    if (v is! Map) return null;
    final bytes = v['bytes'];
    final name = v['name'];
    if (bytes is! Uint8List) return null;
    return PickedFile(name is String ? name : 'project.pixora', bytes);
  }
}

import 'dart:typed_data';

import '../../projects/project_store.dart';
import 'platform_info.dart';
import 'platform_services_stub.dart'
    if (dart.library.io) 'platform_services_io.dart'
    if (dart.library.js_interop) 'platform_services_web.dart';

/// An image picked by the user.
class PickedImage {
  const PickedImage(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

enum SaveOutcome { saved, cancelled, failed }

/// Everything that genuinely differs between platforms, behind one API.
///
/// The right implementation is selected at compile time with conditional
/// imports (`dart:io` platforms vs. the web) and, inside it, at runtime via
/// [PlatformInfo] (e.g. mobile share sheet vs. desktop save dialog). Screens
/// only ever talk to this interface.
abstract class PlatformServices {
  PlatformServices(this.info);

  factory PlatformServices.create() =>
      createPlatformServices(PlatformInfo.current());

  final PlatformInfo info;

  /// Opens the persistent project store for this platform.
  Future<ProjectStore> openProjectStore();

  Future<PickedImage?> pickImage();

  /// Lets the user save a file (save dialog / document picker / download).
  Future<SaveOutcome> saveFile(
    Uint8List bytes,
    String fileName,
    String mimeType,
  );

  /// Opens the system share sheet (or the closest equivalent).
  Future<void> share(Uint8List bytes, String fileName, String mimeType);

  /// Whether a native share sheet is the natural way to hand off files.
  bool get prefersShare => info.isMobile;
}

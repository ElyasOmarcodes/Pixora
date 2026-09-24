import 'package:flutter/foundation.dart';

enum PixPlatform { android, ios, windows, macos, linux, web, other }

/// Answers "where am I running?" in one place.
///
/// Code that must behave differently per platform asks this class (or goes
/// through `PlatformServices`, which picks a platform implementation) rather
/// than sprinkling `Platform.isX` checks around. It avoids `dart:io`, so it is
/// safe on the web too.
class PlatformInfo {
  const PlatformInfo(this.platform);

  factory PlatformInfo.current() {
    if (kIsWeb) return const PlatformInfo(PixPlatform.web);
    return PlatformInfo(switch (defaultTargetPlatform) {
      TargetPlatform.android => PixPlatform.android,
      TargetPlatform.iOS => PixPlatform.ios,
      TargetPlatform.windows => PixPlatform.windows,
      TargetPlatform.macOS => PixPlatform.macos,
      TargetPlatform.linux => PixPlatform.linux,
      TargetPlatform.fuchsia => PixPlatform.other,
    });
  }

  final PixPlatform platform;

  bool get isWeb => platform == PixPlatform.web;
  bool get isAndroid => platform == PixPlatform.android;
  bool get isIOS => platform == PixPlatform.ios;
  bool get isMobile => isAndroid || isIOS;
  bool get isDesktop =>
      platform == PixPlatform.windows ||
      platform == PixPlatform.macos ||
      platform == PixPlatform.linux;
  bool get isApple => isIOS || platform == PixPlatform.macos;

  /// Mouse + keyboard is the primary input (show shortcuts, hover states,
  /// scroll-to-zoom).
  bool get prefersPointer => isDesktop || isWeb;

  /// Haptic feedback is meaningful here.
  bool get supportsHaptics => isMobile;

  /// Primary modifier for shortcuts (⌘ on Apple, Ctrl elsewhere).
  String get modifierLabel => isApple ? '⌘' : 'Ctrl';

  @override
  String toString() => platform.name;
}

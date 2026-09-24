// Renders the Pixora logo to assets/branding/icon.png (1024×1024), the
// source image for flutter_launcher_icons. Run: flutter test tool/render_icon_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixora/core/settings/app_settings.dart';
import 'package:pixora/ui/widgets/pixora_logo.dart';

void main() {
  testWidgets('render app icon', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      Center(
        child: RepaintBoundary(
          key: key,
          child: PixoraLogo(size: 512, accent: kAccentColors.first),
        ),
      ),
    );
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('assets/branding/icon.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  });
}

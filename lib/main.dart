import 'package:flutter/material.dart';

import 'app/app_scope.dart';
import 'app/pixora_app.dart';
import 'core/colors/recent_colors.dart';
import 'core/fonts/font_catalog.dart';
import 'core/patterns/pattern_library.dart';
import 'core/platform/platform_services.dart';
import 'core/settings/app_settings.dart';
import 'editor/actions/action_registry.dart';
import 'projects/project_repository.dart';

/// [args] carries files passed on the command line — how Windows and Linux
/// hand over a double-clicked `.pixora` file.
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  final platform = PlatformServices.create();
  final settings = await AppSettings.load();
  final store = await platform.openProjectStore(
    customRoot: settings.storageRoot,
  );
  await platform.initFileOpening(args);
  final fonts = FontCatalog(platform, settings);
  // Imported fonts load in the background; text re-lays out when ready.
  fonts.init().ignore();
  RecentColors.instance.load().ignore();
  PatternLibrary.instance.load().ignore();

  final services = AppServices(
    settings: settings,
    platform: platform,
    projects: ProjectRepository(store),
    actions: ActionRegistry(),
    fonts: fonts,
  );

  runApp(AppScope(services: services, child: const PixoraApp()));
}

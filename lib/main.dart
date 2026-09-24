import 'package:flutter/material.dart';

import 'app/app_scope.dart';
import 'app/pixora_app.dart';
import 'core/platform/platform_services.dart';
import 'core/settings/app_settings.dart';
import 'editor/actions/action_registry.dart';
import 'projects/project_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final platform = PlatformServices.create();
  final settings = AppSettings.load();
  final store = platform.openProjectStore();

  final services = AppServices(
    settings: await settings,
    platform: platform,
    projects: ProjectRepository(await store),
    actions: ActionRegistry(),
  );

  runApp(AppScope(services: services, child: const PixoraApp()));
}

import 'package:flutter/widgets.dart';

import '../core/fonts/font_catalog.dart';
import '../core/platform/platform_services.dart';
import '../core/settings/app_settings.dart';
import '../editor/actions/action_registry.dart';
import '../projects/project_repository.dart';

/// App-wide services, created once at startup and handed down the tree.
class AppServices {
  AppServices({
    required this.settings,
    required this.platform,
    required this.projects,
    required this.actions,
    required this.fonts,
  });

  final AppSettings settings;
  final PlatformServices platform;
  final ProjectRepository projects;
  final ActionRegistry actions;
  final FontCatalog fonts;
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.services;

  @override
  bool updateShouldNotify(AppScope oldWidget) => services != oldWidget.services;
}

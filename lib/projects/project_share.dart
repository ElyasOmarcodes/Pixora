import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/platform/platform_services.dart';
import '../l10n/app_localizations.dart';
import 'pixora_format.dart';

/// Hands a `.pixora` file to the user: the share sheet on phones (send it,
/// save it to Files/Drive…), a save dialog on desktops.
Future<void> deliverProjectFile(
  BuildContext context,
  PlatformServices platform,
  Uint8List bytes,
  String projectName,
) async {
  final l = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final safe = projectName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  final name = '${safe.isEmpty ? 'project' : safe}.${PixoraFormat.extension}';
  try {
    if (platform.prefersShare) {
      await platform.share(bytes, name, 'application/octet-stream');
    } else {
      final r = await platform.saveFileAs(
        bytes,
        name,
        'application/octet-stream',
      );
      if (r == SaveOutcome.failed) {
        messenger.showSnackBar(SnackBar(content: Text(l.exportFailed)));
      }
    }
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('${l.exportFailed}: $e')));
  }
}

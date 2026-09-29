import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'pix_dialog.dart';

/// Soft confirmation dialog for destructive actions. Returns true when the
/// user confirms.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  String? confirmLabel,
  IconData icon = Icons.delete_outline_rounded,
  bool destructive = true,
}) async {
  final ok = await showPixDialog<bool>(
    context: context,
    builder: (context) {
      final l = AppLocalizations.of(context);
      final scheme = Theme.of(context).colorScheme;
      return PixDialogCard(
        icon: icon,
        accent: destructive ? scheme.error : scheme.primary,
        title: title,
        message: message,
        actions: [
          Row(
            children: [
              Expanded(
                child: PixDialogButton(
                  kind: PixButtonKind.quiet,
                  label: l.cancel,
                  onPressed: () => Navigator.pop(context, false),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: destructive
                    ? PixDialogButton(
                        kind: PixButtonKind.solidDanger,
                        autofocus: true,
                        label: confirmLabel ?? l.delete,
                        onPressed: () => Navigator.pop(context, true),
                      )
                    : PixDialogButton(
                        autofocus: true,
                        label: confirmLabel ?? l.delete,
                        onPressed: () => Navigator.pop(context, true),
                      ),
              ),
            ],
          ),
        ],
      );
    },
  );
  return ok ?? false;
}

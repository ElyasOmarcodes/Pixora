import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

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
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) {
      final l = AppLocalizations.of(context);
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      final accent = destructive ? scheme.error : scheme.primary;
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 32, color: accent),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (message != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 50),
                        ),
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(l.cancel),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 50),
                          backgroundColor: accent,
                          foregroundColor: destructive
                              ? scheme.onError
                              : scheme.onPrimary,
                        ),
                        autofocus: true,
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(confirmLabel ?? l.delete),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  return ok ?? false;
}

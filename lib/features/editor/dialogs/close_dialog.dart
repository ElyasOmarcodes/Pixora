import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

enum CloseChoice { save, discard }

/// Asked when leaving a project with changes: save, don't save, or cancel
/// (returns null).
Future<CloseChoice?> showCloseProjectDialog(
  BuildContext context,
) => showDialog<CloseChoice>(
  context: context,
  builder: (context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.save_as_rounded,
                    size: 32,
                    color: scheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                l.closeProjectTitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l.closeProjectBody,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
                autofocus: true,
                onPressed: () => Navigator.pop(context, CloseChoice.save),
                icon: const Icon(Icons.check_rounded),
                label: Text(l.saveAndClose),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 52),
                  foregroundColor: scheme.error,
                  side: BorderSide(color: scheme.error.withValues(alpha: 0.5)),
                ),
                onPressed: () => Navigator.pop(context, CloseChoice.discard),
                icon: const Icon(Icons.delete_sweep_rounded),
                label: Text(l.dontSave),
              ),
              const SizedBox(height: 4),
              TextButton(
                style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: () => Navigator.pop(context),
                child: Text(l.cancel),
              ),
            ],
          ),
        ),
      ),
    );
  },
);

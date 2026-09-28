import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../ui/widgets/pix_dialog.dart';

enum CloseChoice { save, discard }

/// Asked when leaving a project with changes: save, don't save, or cancel
/// (returns null).
Future<CloseChoice?> showCloseProjectDialog(BuildContext context) =>
    showPixDialog<CloseChoice>(
      context: context,
      builder: (context) {
        final l = AppLocalizations.of(context);
        return PixDialogCard(
          icon: Icons.save_as_rounded,
          title: l.closeProjectTitle,
          message: l.closeProjectBody,
          actions: [
            PixDialogButton(
              autofocus: true,
              icon: Icons.check_rounded,
              label: l.saveAndClose,
              onPressed: () => Navigator.pop(context, CloseChoice.save),
            ),
            PixDialogButton(
              kind: PixButtonKind.danger,
              icon: Icons.delete_sweep_rounded,
              label: l.dontSave,
              onPressed: () => Navigator.pop(context, CloseChoice.discard),
            ),
            PixDialogButton(
              kind: PixButtonKind.quiet,
              label: l.cancel,
              onPressed: () => Navigator.pop(context),
            ),
          ],
        );
      },
    );

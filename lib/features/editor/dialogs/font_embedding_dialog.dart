import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../projects/project_fonts.dart';
import '../../../ui/widgets/pix_dialog.dart';

/// Asks how the exported project should carry [families] (fonts that
/// don't ship with Pixora). Null when cancelled.
Future<FontEmbedding?> showFontEmbeddingDialog(
  BuildContext context,
  List<String> families,
) => showPixDialog<FontEmbedding>(
  context: context,
  builder: (context) => _FontEmbeddingDialog(families: families),
);

class _FontEmbeddingDialog extends StatefulWidget {
  const _FontEmbeddingDialog({required this.families});
  final List<String> families;

  @override
  State<_FontEmbeddingDialog> createState() => _FontEmbeddingDialogState();
}

class _FontEmbeddingDialogState extends State<_FontEmbeddingDialog> {
  FontEmbedding _choice = FontEmbedding.locked;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    Widget option(FontEmbedding v, IconData icon, String title, String hint) =>
        RadioListTile<FontEmbedding>(
          value: v,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          secondary: Icon(icon),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(hint),
        );
    return AlertDialog(
      title: Text(l.embedFontsTitle),
      content: SingleChildScrollView(
        child: RadioGroup<FontEmbedding>(
          groupValue: _choice,
          onChanged: (v) => setState(() => _choice = v ?? _choice),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.families.join('، '),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              option(
                FontEmbedding.none,
                Icons.block_rounded,
                l.embedFontsNone,
                l.embedFontsNoneHint,
              ),
              option(
                FontEmbedding.files,
                Icons.font_download_rounded,
                l.embedFontsFiles,
                l.embedFontsFilesHint,
              ),
              option(
                FontEmbedding.locked,
                Icons.lock_rounded,
                l.embedFontsLocked,
                l.embedFontsLockedHint,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _choice),
          child: Text(l.exportProject),
        ),
      ],
    );
  }
}

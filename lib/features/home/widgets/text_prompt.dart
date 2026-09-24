import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

/// Asks for a single line of text. Returns null when cancelled.
Future<String?> showTextPrompt(
  BuildContext context, {
  required String title,
  required String label,
  String initial = '',
}) {
  return showDialog<String>(
    context: context,
    builder: (context) =>
        _TextPrompt(title: title, label: label, initial: initial),
  );
}

class _TextPrompt extends StatefulWidget {
  const _TextPrompt({
    required this.title,
    required this.label,
    required this.initial,
  });
  final String title;
  final String label;
  final String initial;

  @override
  State<_TextPrompt> createState() => _TextPromptState();
}

class _TextPromptState extends State<_TextPrompt> {
  late final TextEditingController _c =
      TextEditingController(text: widget.initial)
        ..selection = TextSelection(
          baseOffset: 0,
          extentOffset: widget.initial.length,
        );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _c,
        autofocus: true,
        decoration: InputDecoration(labelText: widget.label),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _c.text),
          child: Text(l.ok),
        ),
      ],
    );
  }
}

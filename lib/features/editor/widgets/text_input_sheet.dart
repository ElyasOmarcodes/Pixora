import 'package:flutter/material.dart';

import '../../../document/render/text_layout.dart';
import '../../../l10n/app_localizations.dart';

/// Bottom sheet for typing or editing layer text. The field switches to
/// right-to-left automatically for Pashto, Dari, Arabic and Urdu.
Future<String?> showTextInputSheet(
  BuildContext context, {
  String initial = '',
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _TextInputSheet(initial: initial),
  );
}

class _TextInputSheet extends StatefulWidget {
  const _TextInputSheet({required this.initial});
  final String initial;

  @override
  State<_TextInputSheet> createState() => _TextInputSheetState();
}

class _TextInputSheetState extends State<_TextInputSheet> {
  late final TextEditingController _c =
      TextEditingController(text: widget.initial)
        ..selection = TextSelection(
          baseOffset: 0,
          extentOffset: widget.initial.length,
        )
        ..addListener(() => setState(() {}));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final dir = _c.text.trim().isEmpty
        ? Directionality.of(context)
        : detectTextDirection(_c.text);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                widget.initial.isEmpty ? l.text : l.editText,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _c.text.trim().isEmpty
                    ? null
                    : () => Navigator.pop(context, _c.text),
                icon: const Icon(Icons.check_rounded),
                label: Text(l.done),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _c,
            autofocus: true,
            minLines: 2,
            maxLines: 6,
            textDirection: dir,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
            keyboardType: TextInputType.multiline,
            decoration: InputDecoration(hintText: l.typeSomething),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../document/render/text_layout.dart';
import '../../../l10n/app_localizations.dart';
import 'font_picker.dart';

/// Result of [showTextDialog].
class TextDialogResult {
  const TextDialogResult(this.text, this.fontFamily);
  final String text;
  final String fontFamily;
}

/// Centered dialog for typing or editing layer text, PixelLab style: a big
/// field plus quick buttons for the font, paste and clear. The field turns
/// right-to-left automatically for Pashto, Dari, Arabic and Urdu, and shows
/// the text in the chosen font.
Future<TextDialogResult?> showTextDialog(
  BuildContext context, {
  String initial = '',
  required String fontFamily,
}) => showDialog<TextDialogResult>(
  context: context,
  builder: (_) => _TextDialog(initial: initial, fontFamily: fontFamily),
);

class _TextDialog extends StatefulWidget {
  const _TextDialog({required this.initial, required this.fontFamily});
  final String initial;
  final String fontFamily;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final TextEditingController _c =
      TextEditingController(text: widget.initial)
        ..selection = TextSelection(
          baseOffset: 0,
          extentOffset: widget.initial.length,
        )
        ..addListener(() => setState(() {}));
  late String _font = widget.fontFamily;
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _done() {
    if (_c.text.trim().isEmpty) return;
    Navigator.pop(context, TextDialogResult(_c.text, _font));
  }

  Future<void> _pickFont() async {
    final f = await showFontPicker(context, current: _font, sample: _c.text);
    if (f != null) setState(() => _font = f);
    _focus.requestFocus();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final t = data?.text;
    if (t == null || t.isEmpty) return;
    final sel = _c.selection;
    final text = _c.text;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    _c.value = TextEditingValue(
      text: text.replaceRange(start, end, t),
      selection: TextSelection.collapsed(offset: start + t.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dir = _c.text.trim().isEmpty
        ? Directionality.of(context)
        : detectTextDirection(_c.text);
    final size = MediaQuery.sizeOf(context);

    Widget quick(IconData icon, String tip, VoidCallback? onTap) => Tooltip(
      message: tip,
      child: Material(
        color: scheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: SizedBox(
            width: 46,
            height: 44,
            child: Icon(
              icon,
              color: onTap == null
                  ? scheme.primary.withValues(alpha: 0.35)
                  : scheme.primary,
            ),
          ),
        ),
      ),
    );

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: size.height * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.title_rounded, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l.text,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  quick(Icons.font_download_rounded, l.font, _pickFont),
                  const SizedBox(width: 6),
                  quick(Icons.content_paste_rounded, l.paste, _paste),
                  const SizedBox(width: 6),
                  quick(
                    Icons.backspace_rounded,
                    l.clearText,
                    _c.text.isEmpty ? null : _c.clear,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 160),
                  child: TextField(
                    controller: _c,
                    focusNode: _focus,
                    autofocus: true,
                    maxLines: null,
                    minLines: 5,
                    textDirection: dir,
                    textAlign: TextAlign.start,
                    keyboardType: TextInputType.multiline,
                    style: TextStyle(
                      fontFamily: _font == 'System' ? null : _font,
                      fontSize: 24,
                      height: 1.45,
                    ),
                    decoration: InputDecoration(
                      hintText: l.typeSomething,
                      filled: true,
                      fillColor: scheme.onSurface.withValues(alpha: 0.04),
                      contentPadding: const EdgeInsets.all(16),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(
                          color: scheme.primary,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: ActionChip(
                  avatar: const Icon(Icons.font_download_outlined, size: 18),
                  label: Text(
                    _font,
                    style: TextStyle(
                      fontFamily: _font == 'System' ? null : _font,
                    ),
                  ),
                  onPressed: _pickFont,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(l.cancel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _c.text.trim().isEmpty ? null : _done,
                      icon: const Icon(Icons.check_rounded),
                      label: Text(l.done),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

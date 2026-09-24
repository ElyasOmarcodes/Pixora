import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/app_scope.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/fonts/font_catalog.dart';
import '../../../document/render/text_layout.dart';
import '../../../l10n/app_localizations.dart';
import 'font_picker.dart';

/// Result of [showTextDialog].
class TextDialogResult {
  const TextDialogResult(this.text, this.fontFamily);
  final String text;
  final String fontFamily;
}

/// Full-page text editor: a big, calm writing area in the chosen font,
/// a strip of quick fonts and tools above the keyboard. Right-to-left is
/// picked automatically for Pashto, Dari, Arabic and Urdu.
Future<TextDialogResult?> showTextDialog(
  BuildContext context, {
  String initial = '',
  required String fontFamily,
}) => Navigator.of(context).push<TextDialogResult>(
  PageRouteBuilder(
    fullscreenDialog: true,
    transitionDuration: PixTokens.medium,
    reverseTransitionDuration: PixTokens.fast,
    pageBuilder: (_, _, _) =>
        _TextEditorPage(initial: initial, fontFamily: fontFamily),
    transitionsBuilder: (_, a, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.05),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: a, curve: PixTokens.emphasized)),
        child: child,
      ),
    ),
  ),
);

class _TextEditorPage extends StatefulWidget {
  const _TextEditorPage({required this.initial, required this.fontFamily});
  final String initial;
  final String fontFamily;

  @override
  State<_TextEditorPage> createState() => _TextEditorPageState();
}

class _TextEditorPageState extends State<_TextEditorPage> {
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

  bool get _canSave => _c.text.trim().isNotEmpty;

  void _done() {
    if (!_canSave) return;
    Navigator.pop(context, TextDialogResult(_c.text, _font));
  }

  Future<void> _allFonts() async {
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

  /// Recent and favourite fonts first, then a few bundled ones.
  List<String> _quickFonts(FontCatalog c) {
    final out = <String>[];
    void add(String f) {
      if (!out.contains(f) && c.isAvailable(f)) out.add(f);
    }

    add(_font);
    c.recent.forEach(add);
    c.favorites.forEach(add);
    for (final f in FontCatalog.bundled.take(14)) {
      add(f.family);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final catalog = AppScope.of(context).fonts;
    final dir = _c.text.trim().isEmpty
        ? Directionality.of(context)
        : detectTextDirection(_c.text);
    final fontFamily = _font == 'System' ? null : _font;

    return Scaffold(
      backgroundColor: scheme.surface,
      resizeToAvoidBottomInset: true,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              scheme.primary.withValues(alpha: 0.10),
              scheme.surface,
              scheme.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header.
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 12, 0),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: l.cancel,
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        widget.initial.isEmpty ? l.text : l.editText,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    AnimatedOpacity(
                      duration: PixTokens.fast,
                      opacity: _canSave ? 1 : 0.5,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                        ),
                        onPressed: _canSave ? _done : null,
                        icon: const Icon(Icons.check_rounded),
                        label: Text(l.done),
                      ),
                    ),
                  ],
                ),
              ),
              // Writing area.
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: _focus.hasFocus
                            ? scheme.primary.withValues(alpha: 0.6)
                            : scheme.outlineVariant,
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: scheme.primary.withValues(alpha: 0.08),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Focus(
                      onFocusChange: (_) => setState(() {}),
                      child: Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
                          child: TextField(
                            controller: _c,
                            focusNode: _focus,
                            autofocus: true,
                            maxLines: null,
                            textAlign: TextAlign.center,
                            textDirection: dir,
                            keyboardType: TextInputType.multiline,
                            cursorColor: scheme.primary,
                            cursorWidth: 2.5,
                            style: TextStyle(
                              fontFamily: fontFamily,
                              fontFamilyFallback: FontCatalog.fallback,
                              fontSize: 32,
                              height: 1.45,
                              color: scheme.onSurface,
                            ),
                            decoration: InputDecoration(
                              hintText: l.typeSomething,
                              hintStyle: TextStyle(
                                fontFamily: fontFamily,
                                color: scheme.onSurfaceVariant.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Quick fonts.
              ListenableBuilder(
                listenable: catalog,
                builder: (context, _) {
                  final fonts = _quickFonts(catalog);
                  return SizedBox(
                    height: 76,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: [
                        _FontChip(
                          label: l.allFonts,
                          preview: null,
                          selected: false,
                          onTap: _allFonts,
                        ),
                        for (final f in fonts)
                          _FontChip(
                            label: f,
                            preview: f,
                            selected: f == _font,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _font = f);
                            },
                          ),
                      ],
                    ),
                  );
                },
              ),
              // Tools.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: Row(
                  children: [
                    _Tool(
                      icon: Icons.content_paste_rounded,
                      label: l.paste,
                      onTap: _paste,
                    ),
                    const SizedBox(width: 8),
                    _Tool(
                      icon: Icons.backspace_rounded,
                      label: l.clearText,
                      onTap: _c.text.isEmpty ? null : _c.clear,
                    ),
                    const Spacer(),
                    Text(
                      '${_c.text.characters.length}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FontChip extends StatelessWidget {
  const _FontChip({
    required this.label,
    required this.preview,
    required this.selected,
    required this.onTap,
  });

  final String label;

  /// Font family to preview in; null for the "all fonts" chip.
  final String? preview;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final all = preview == null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Material(
        color: all
            ? scheme.primary
            : selected
            ? scheme.primary.withValues(alpha: 0.12)
            : scheme.onSurface.withValues(alpha: 0.05),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: selected ? scheme.primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minWidth: 76),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (all)
                  Icon(Icons.font_download_rounded, color: scheme.onPrimary)
                else
                  Text(
                    'Aa اب',
                    style: TextStyle(
                      fontFamily: preview == 'System' ? null : preview,
                      fontFamilyFallback: FontCatalog.fallback,
                      fontSize: 20,
                      height: 1.2,
                      color: selected ? scheme.primary : scheme.onSurface,
                    ),
                  ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: all
                        ? scheme.onPrimary
                        : selected
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                    fontWeight: selected || all ? FontWeight.w800 : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tool extends StatelessWidget {
  const _Tool({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FilledButton.tonalIcon(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 42),
        padding: const EdgeInsets.symmetric(horizontal: 14),
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 18, color: onTap == null ? null : scheme.primary),
      label: Text(label),
    );
  }
}

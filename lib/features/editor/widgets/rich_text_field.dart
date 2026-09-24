import 'package:flutter/material.dart';

import '../../../core/fonts/font_catalog.dart';
import '../../../document/model/text_span_style.dart';
import '../../../document/render/text_layout.dart';
import '../../../l10n/app_localizations.dart';

/// Text controller that shows per-range fonts and colours while typing and
/// keeps the ranges attached to their words as the text changes.
class RichTextController extends TextEditingController {
  RichTextController({super.text, List<TextSpanStyle> spans = const []})
    : _spans = TextSpans.normalize(spans),
      _last = text ?? '';

  List<TextSpanStyle> _spans;
  String _last;

  List<TextSpanStyle> get spans => _spans;
  set spans(List<TextSpanStyle> v) {
    _spans = TextSpans.normalize(v);
    notifyListeners();
  }

  @override
  set value(TextEditingValue v) {
    if (v.text != _last) {
      _spans = TextSpans.adjust(_spans, _last, v.text);
      _last = v.text;
    }
    super.value = v;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (_spans.isEmpty) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final t = text;
    final children = <InlineSpan>[];
    var cursor = 0;
    for (final s in _spans) {
      final a = s.start.clamp(0, t.length), b = s.end.clamp(0, t.length);
      if (b <= a || a < cursor) continue;
      if (a > cursor) children.add(TextSpan(text: t.substring(cursor, a)));
      children.add(
        TextSpan(
          text: t.substring(a, b),
          style: TextStyle(
            fontFamily: s.fontFamily == 'System' ? null : s.fontFamily,
            fontFamilyFallback: FontCatalog.fallback,
            color: s.color,
          ),
        ),
      );
      cursor = b;
    }
    if (cursor < t.length) children.add(TextSpan(text: t.substring(cursor)));
    return TextSpan(style: style, children: children);
  }
}

/// "Whole text / part of text" chooser. In part mode the text is shown and
/// the user selects the part to style; [onChanged] gets the range, or null
/// for the whole text.
class TextPartSelector extends StatefulWidget {
  const TextPartSelector({
    super.key,
    required this.text,
    required this.spans,
    required this.fontFamily,
    required this.onChanged,
    this.initial,
  });

  final String text;
  final List<TextSpanStyle> spans;
  final String fontFamily;
  final TextRange? initial;
  final ValueChanged<TextRange?> onChanged;

  @override
  State<TextPartSelector> createState() => _TextPartSelectorState();
}

class _TextPartSelectorState extends State<TextPartSelector> {
  late bool _part = widget.initial != null;
  late final RichTextController _c = RichTextController(
    text: widget.text,
    spans: widget.spans,
  )..addListener(_onSel);
  TextRange? _last;

  @override
  void initState() {
    super.initState();
    final r = widget.initial;
    if (r != null) {
      _c.selection = TextSelection(baseOffset: r.start, extentOffset: r.end);
      _last = r;
    }
  }

  @override
  void didUpdateWidget(TextPartSelector old) {
    super.didUpdateWidget(old);
    if (old.spans != widget.spans) _c.spans = widget.spans;
  }

  void _onSel() {
    if (!_part) return;
    final s = _c.selection;
    final r = s.isValid && !s.isCollapsed
        ? TextRange(start: s.start, end: s.end)
        : null;
    if (r == _last) return;
    _last = r;
    widget.onChanged(r);
    setState(() {});
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: false,
                icon: const Icon(Icons.notes_rounded, size: 18),
                label: Text(l.wholeText),
              ),
              ButtonSegment(
                value: true,
                icon: const Icon(Icons.highlight_alt_rounded, size: 18),
                label: Text(l.partOfText),
              ),
            ],
            selected: {_part},
            onSelectionChanged: (v) {
              setState(() => _part = v.first);
              if (!_part) {
                _last = null;
                widget.onChanged(null);
              } else {
                _onSel();
              }
            },
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: !_part
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: scheme.onSurface.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _last == null
                                ? scheme.outlineVariant
                                : scheme.primary,
                            width: 1.5,
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        child: TextField(
                          controller: _c,
                          readOnly: true,
                          showCursor: true,
                          enableInteractiveSelection: true,
                          maxLines: 3,
                          minLines: 1,
                          textAlign: TextAlign.center,
                          textDirection: detectTextDirection(widget.text),
                          style: TextStyle(
                            fontFamily: widget.fontFamily == 'System'
                                ? null
                                : widget.fontFamily,
                            fontFamilyFallback: FontCatalog.fallback,
                            fontSize: 22,
                            height: 1.4,
                            color: scheme.onSurface,
                          ),
                          decoration: const InputDecoration(
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _last == null
                            ? l.selectPartHint
                            : l.partSelected(_last!.end - _last!.start),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: _last == null
                              ? scheme.onSurfaceVariant
                              : scheme.primary,
                          fontWeight: _last == null ? null : FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

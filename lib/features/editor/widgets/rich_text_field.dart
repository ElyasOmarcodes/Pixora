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

/// "Whole text / part of text" chooser. In part mode the text is shown as
/// word chips: tap a word to select it, another to select everything
/// between; arrows move either end by one letter. [onChanged] gets the
/// range, or null for the whole text.
class TextPartSelector extends StatefulWidget {
  const TextPartSelector({
    super.key,
    required this.text,
    required this.spans,
    required this.fontFamily,
    required this.onChanged,
    this.initial,
    this.onPartMode,
  });

  final String text;
  final List<TextSpanStyle> spans;
  final String fontFamily;
  final TextRange? initial;
  final ValueChanged<TextRange?> onChanged;

  /// Told when "part of text" is switched on or off (a part may not be
  /// chosen yet).
  final ValueChanged<bool>? onPartMode;

  @override
  State<TextPartSelector> createState() => _TextPartSelectorState();
}

class _TextPartSelectorState extends State<TextPartSelector> {
  late bool _part = widget.initial != null;
  late final ValueNotifier<TextRange?> _sel = ValueNotifier(widget.initial);

  void _select(TextRange? r) {
    if (r == _sel.value) return;
    _sel.value = r;
    if (_part) widget.onChanged(r);
    setState(() {});
  }

  @override
  void dispose() {
    _sel.dispose();
    super.dispose();
  }

  /// A whole page of word chips, for long texts. It edits the same
  /// selection.
  Future<void> _fullPage() async {
    final l = AppLocalizations.of(context);
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: Text(l.partOfText),
            actions: [
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 12),
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.check_rounded),
                  label: Text(l.done),
                ),
              ),
            ],
          ),
          body: SafeArea(
            child: ValueListenableBuilder<TextRange?>(
              valueListenable: _sel,
              builder: (context, sel, _) => Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SelectionInfo(selection: sel),
                    const SizedBox(height: 8),
                    Expanded(
                      child: _WordPicker(
                        text: widget.text,
                        selection: sel,
                        fontFamily: widget.fontFamily,
                        expand: true,
                        onSelect: _select,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
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
              widget.onPartMode?.call(_part);
              widget.onChanged(_part ? _sel.value : null);
            },
          ),
        ),
        if (_part)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: _WordPicker(
              text: widget.text,
              selection: _sel.value,
              fontFamily: widget.fontFamily,
              // A small scrolling area, so the options below stay in view.
              maxHeight: 96,
              onSelect: _select,
              onFullPage: _fullPage,
            ),
          ),
      ],
    );
  }
}

/// "N characters selected" / the hint, as a soft banner.
class _SelectionInfo extends StatelessWidget {
  const _SelectionInfo({required this.selection});
  final TextRange? selection;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final n = selection == null ? 0 : selection!.end - selection!.start;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: n > 0
            ? scheme.primary.withValues(alpha: 0.1)
            : scheme.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        n > 0 ? l.partSelected(n) : l.selectPartHint,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(
          color: n > 0 ? scheme.primary : scheme.onSurfaceVariant,
          fontWeight: n > 0 ? FontWeight.w700 : null,
        ),
      ),
    );
  }
}

/// The text as tappable word chips: tap one to select it, another to
/// select everything from the first to it; the arrows move either end by
/// one letter. Laid out in the text's own direction, so right-to-left text
/// reads — and selects — naturally.
class _WordPicker extends StatefulWidget {
  const _WordPicker({
    required this.text,
    required this.selection,
    required this.fontFamily,
    required this.onSelect,
    this.maxHeight = 96,
    this.expand = false,
    this.onFullPage,
  });
  final String text;
  final TextRange? selection;
  final String fontFamily;
  final ValueChanged<TextRange> onSelect;
  final double maxHeight;

  /// Fills the height it is given (the full page).
  final bool expand;
  final VoidCallback? onFullPage;

  @override
  State<_WordPicker> createState() => _WordPickerState();
}

class _WordPickerState extends State<_WordPicker> {
  /// The word the current range was started from.
  int? _anchor;
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  List<TextRange> get _words => [
    for (final m in RegExp(r'\S+').allMatches(widget.text))
      TextRange(start: m.start, end: m.end),
  ];

  void _tap(List<TextRange> words, int i) {
    final w = words[i];
    final sel = widget.selection;
    final a = _anchor;
    if (a != null && a < words.length && sel != null && a != i) {
      // Everything between the first tapped word and this one.
      final from = words[a < i ? a : i], to = words[a < i ? i : a];
      widget.onSelect(TextRange(start: from.start, end: to.end));
      _anchor = null;
    } else {
      widget.onSelect(w);
      _anchor = i;
    }
    setState(() {});
  }

  void _nudge({required bool start, required int by}) {
    final sel = widget.selection;
    if (sel == null) return;
    final n = widget.text.length;
    var s = sel.start, e = sel.end;
    if (start) {
      s = (s + by).clamp(0, e - 1);
    } else {
      e = (e + by).clamp(s + 1, n);
    }
    widget.onSelect(TextRange(start: s, end: e));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final words = _words;
    final dir = detectTextDirection(widget.text);
    final sel = widget.selection;
    bool inside(TextRange w) =>
        sel != null && w.start < sel.end && w.end > sel.start;
    final font = widget.fontFamily == 'System' ? null : widget.fontFamily;
    Widget arrow(IconData icon, String tip, VoidCallback f) => IconButton(
      tooltip: tip,
      visualDensity: VisualDensity.compact,
      onPressed: sel == null ? null : f,
      icon: Icon(icon, size: 20),
    );
    // In reading order the start of the text is on the right for RTL.
    final rtl = dir == TextDirection.rtl;
    final chips = Scrollbar(
      controller: _scroll,
      thumbVisibility: !widget.expand,
      child: SingleChildScrollView(
        controller: _scroll,
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Directionality(
          textDirection: dir,
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            alignment: WrapAlignment.center,
            children: [
              for (var i = 0; i < words.length; i++)
                _WordChip(
                  text: widget.text.substring(words[i].start, words[i].end),
                  font: font,
                  selected: inside(words[i]),
                  anchor: _anchor == i,
                  onTap: () => _tap(words, i),
                ),
            ],
          ),
        ),
      ),
    );
    return Column(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.expand)
          Expanded(child: chips)
        else
          DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.onSurface.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: sel == null ? scheme.outlineVariant : scheme.primary,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: widget.maxHeight),
                child: chips,
              ),
            ),
          ),
        Row(
          children: [
            // The text's start end.
            arrow(
              rtl ? Icons.chevron_right_rounded : Icons.chevron_left_rounded,
              l.growSelection,
              () => _nudge(start: true, by: -1),
            ),
            arrow(
              rtl ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
              l.shrinkSelection,
              () => _nudge(start: true, by: 1),
            ),
            Expanded(
              child: Text(
                sel == null
                    ? l.tapWordsHint
                    : l.partSelected(sel.end - sel.start),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: sel == null ? scheme.onSurfaceVariant : scheme.primary,
                  fontWeight: sel == null ? null : FontWeight.w700,
                ),
              ),
            ),
            if (widget.onFullPage != null)
              IconButton(
                tooltip: l.selectFullPage,
                visualDensity: VisualDensity.compact,
                onPressed: widget.onFullPage,
                icon: Icon(
                  Icons.open_in_full_rounded,
                  size: 18,
                  color: scheme.primary,
                ),
              ),
            // The text's finishing end.
            arrow(
              rtl ? Icons.chevron_right_rounded : Icons.chevron_left_rounded,
              l.shrinkSelection,
              () => _nudge(start: false, by: -1),
            ),
            arrow(
              rtl ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
              l.growSelection,
              () => _nudge(start: false, by: 1),
            ),
          ],
        ),
      ],
    );
  }
}

class _WordChip extends StatelessWidget {
  const _WordChip({
    required this.text,
    required this.font,
    required this.selected,
    required this.anchor,
    required this.onTap,
  });
  final String text;
  final String? font;
  final bool selected;
  final bool anchor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? scheme.primary
          : scheme.onSurface.withValues(alpha: 0.06),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: anchor ? scheme.tertiary : Colors.transparent,
          width: 1.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          child: Text(
            text,
            style: TextStyle(
              fontFamily: font,
              fontFamilyFallback: FontCatalog.fallback,
              fontSize: 14,
              height: 1.25,
              color: selected ? scheme.onPrimary : scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

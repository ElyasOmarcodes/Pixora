import 'package:flutter/widgets.dart';

/// Makes ← and → (with Shift / Alt / Ctrl) move the caret and selection
/// the way the arrow points in right-to-left text fields too.
///
/// Flutter maps → to "forward in the text" whatever its direction, so in
/// Pashto, Persian, Arabic or Urdu the caret went the opposite way and
/// Shift+arrow selected the wrong side. The text fields' own actions are
/// overridable: this flips the direction when the focused field is RTL.
class RtlTextKeys extends StatelessWidget {
  const RtlTextKeys({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Actions(
    actions: <Type, Action<Intent>>{
      ExtendSelectionByCharacterIntent: _Flip<ExtendSelectionByCharacterIntent>(
        (i) => ExtendSelectionByCharacterIntent(
          forward: !i.forward,
          collapseSelection: i.collapseSelection,
        ),
      ),
      ExtendSelectionToNextWordBoundaryIntent:
          _Flip<ExtendSelectionToNextWordBoundaryIntent>(
            (i) => ExtendSelectionToNextWordBoundaryIntent(
              forward: !i.forward,
              collapseSelection: i.collapseSelection,
            ),
          ),
      ExtendSelectionToNextWordBoundaryOrCaretLocationIntent:
          _Flip<ExtendSelectionToNextWordBoundaryOrCaretLocationIntent>(
            (i) => ExtendSelectionToNextWordBoundaryOrCaretLocationIntent(
              forward: !i.forward,
            ),
          ),
    },
    child: child,
  );
}

/// Whether the text field that owns [context] lays its text out RTL.
bool _isRtl(BuildContext? context) {
  if (context == null) return false;
  EditableTextState? state;
  if (context is StatefulElement && context.state is EditableTextState) {
    state = context.state as EditableTextState;
  } else {
    state = context.findAncestorStateOfType<EditableTextState>();
  }
  final dir = state?.widget.textDirection ?? Directionality.maybeOf(context);
  return dir == TextDirection.rtl;
}

class _Flip<T extends DirectionalCaretMovementIntent> extends ContextAction<T> {
  _Flip(this.flip);
  final T Function(T) flip;

  @override
  bool get isActionEnabled => callingAction?.isActionEnabled ?? false;

  @override
  bool consumesKey(T intent) => callingAction?.consumesKey(intent) ?? false;

  @override
  Object? invoke(T intent, [BuildContext? context]) {
    final base = callingAction;
    if (base == null) return null;
    final next = _isRtl(context) ? flip(intent) : intent;
    return base is ContextAction<T>
        ? base.invoke(next, context)
        : base.invoke(next);
  }
}

import 'package:flutter/material.dart';

/// Shows a dialog with Pixora's soft entrance: the page behind dims while
/// the card rises and settles with a gentle spring.
Future<T?> showPixDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) => showGeneralDialog<T>(
  context: context,
  barrierDismissible: barrierDismissible,
  barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
  barrierColor: Colors.transparent,
  // Short and plain, as the platform's own dialogs: a quick fade with a
  // slight grow — no bounce, nothing arriving piece by piece.
  transitionDuration: const Duration(milliseconds: 200),
  pageBuilder: (context, _, _) => builder(context),
  transitionBuilder: (context, animation, _, child) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: FadeTransition(
              opacity: curved,
              child: const ColoredBox(color: Color(0x66000000)),
            ),
          ),
        ),
        FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween(begin: 0.94, end: 1.0).animate(curved),
            child: child,
          ),
        ),
      ],
    );
  },
);

/// The card of a Pixora dialog: an animated icon badge, title, message,
/// optional content and the actions (stacked full-width buttons).
class PixDialogCard extends StatelessWidget {
  const PixDialogCard({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.content,
    this.actions = const [],
    this.accent,
    this.maxWidth = 400,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? content;
  final List<Widget> actions;
  final Color? accent;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final a = accent ?? scheme.primary;
    return Dialog(
      elevation: 0,
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.dialogTheme.backgroundColor ?? scheme.surface,
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: a.withValues(alpha: 0.18),
                blurRadius: 40,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: Stack(
              children: [
                // A soft glow of the accent colour behind the badge.
                Positioned(
                  top: -90,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      width: 260,
                      height: 200,
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          colors: [
                            a.withValues(alpha: 0.16),
                            a.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 30, 24, 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: PixDialogBadge(icon: icon, color: a),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1.25,
                        ),
                      ),
                      if (message != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          message!,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.5,
                          ),
                        ),
                      ],
                      if (content != null) ...[
                        const SizedBox(height: 16),
                        content!,
                      ],
                      if (actions.isNotEmpty) ...[
                        const SizedBox(height: 22),
                        for (var i = 0; i < actions.length; i++) ...[
                          if (i > 0) const SizedBox(height: 10),
                          actions[i],
                        ],
                      ],
                    ],
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

/// A gradient circle with the dialog's icon.
class PixDialogBadge extends StatelessWidget {
  const PixDialogBadge({super.key, required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final hsl = HSLColor.fromColor(color);
    final light = hsl
        .withLightness((hsl.lightness + 0.14).clamp(0.0, 1.0))
        .toColor();
    return Container(
      width: 68,
      height: 68,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [light, color],
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.3),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Icon(icon, size: 32, color: Colors.white),
    );
  }
}

/// Full-width dialog buttons in three weights.
enum PixButtonKind { primary, danger, solidDanger, quiet }

class PixDialogButton extends StatelessWidget {
  const PixDialogButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.kind = PixButtonKind.primary,
    this.autofocus = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final PixButtonKind kind;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
    );
    const size = Size(0, 54);
    final text = Text(
      label,
      style: const TextStyle(fontWeight: FontWeight.w700),
    );
    return _button(scheme, shape, size, text);
  }

  Widget _button(
    ColorScheme scheme,
    OutlinedBorder shape,
    Size size,
    Widget text,
  ) {
    switch (kind) {
      case PixButtonKind.primary:
        return FilledButton.icon(
          autofocus: autofocus,
          style: FilledButton.styleFrom(minimumSize: size, shape: shape),
          onPressed: onPressed,
          icon: icon == null ? const SizedBox.shrink() : Icon(icon),
          label: text,
        );
      case PixButtonKind.danger:
        return FilledButton.icon(
          autofocus: autofocus,
          style: FilledButton.styleFrom(
            minimumSize: size,
            shape: shape,
            backgroundColor: scheme.error.withValues(alpha: 0.12),
            foregroundColor: scheme.error,
          ),
          onPressed: onPressed,
          icon: icon == null ? const SizedBox.shrink() : Icon(icon),
          label: text,
        );
      case PixButtonKind.solidDanger:
        return FilledButton(
          autofocus: autofocus,
          style: FilledButton.styleFrom(
            minimumSize: size,
            shape: shape,
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: onPressed,
          child: text,
        );
      case PixButtonKind.quiet:
        return TextButton(
          autofocus: autofocus,
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 48),
            shape: shape,
            foregroundColor: scheme.onSurfaceVariant,
          ),
          onPressed: onPressed,
          child: text,
        );
    }
  }
}

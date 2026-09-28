import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Shows a dialog with Pixora's soft entrance: the page behind blurs and
/// dims while the card rises and settles with a gentle spring.
Future<T?> showPixDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) => showGeneralDialog<T>(
  context: context,
  barrierDismissible: barrierDismissible,
  barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
  barrierColor: Colors.transparent,
  transitionDuration: const Duration(milliseconds: 420),
  pageBuilder: (context, _, _) => builder(context),
  transitionBuilder: (context, animation, _, child) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: const Cubic(0.18, 0.9, 0.22, 1.08),
      reverseCurve: Curves.easeInCubic,
    );
    final fade = CurvedAnimation(
      parent: animation,
      curve: const Interval(0, 0.6, curve: Curves.easeOut),
      reverseCurve: Curves.easeIn,
    );
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = fade.value;
        return Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 6 * t, sigmaY: 6 * t),
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.32 * t),
                  ),
                ),
              ),
            ),
            Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, 28 * (1 - curved.value)),
                child: Transform.scale(
                  scale: 0.9 + 0.1 * curved.value,
                  child: child,
                ),
              ),
            ),
          ],
        );
      },
      child: child,
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

/// A gradient circle with an icon that pops in and then breathes softly.
class PixDialogBadge extends StatefulWidget {
  const PixDialogBadge({super.key, required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  State<PixDialogBadge> createState() => _PixDialogBadgeState();
}

class _PixDialogBadgeState extends State<PixDialogBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _halo = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat();

  @override
  void dispose() {
    _halo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.color;
    final hsl = HSLColor.fromColor(c);
    final light = hsl
        .withLightness((hsl.lightness + 0.14).clamp(0.0, 1.0))
        .toColor();
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: Curves.elasticOut,
      builder: (context, v, child) => Transform.scale(scale: v, child: child),
      child: SizedBox(
        width: 92,
        height: 92,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // A ring that grows and fades, over and over.
            AnimatedBuilder(
              animation: _halo,
              builder: (context, _) {
                final t = Curves.easeOut.transform(_halo.value);
                return Container(
                  width: 68 + 24 * t,
                  height: 68 + 24 * t,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: c.withValues(alpha: 0.35 * (1 - t)),
                      width: 2,
                    ),
                  ),
                );
              },
            ),
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [light, c],
                ),
                boxShadow: [
                  BoxShadow(
                    color: c.withValues(alpha: 0.35),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(widget.icon, size: 32, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-width dialog buttons in three weights.
enum PixButtonKind { primary, danger, quiet }

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

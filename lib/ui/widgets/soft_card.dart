import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import 'pressable.dart';

/// Rounded, softly shadowed surface that shrinks a little when pressed.
class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.color,
    this.gradient,
  });
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? color;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final pix = PixColors.of(context);
    return Pressable(
      onTap: onTap,
      onLongPress: onLongPress,
      scale: 0.96,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: gradient == null
              ? (color ?? Theme.of(context).cardTheme.color)
              : null,
          gradient: gradient,
          borderRadius: BorderRadius.circular(PixTokens.radiusL),
          boxShadow: [
            BoxShadow(
              color: pix.softShadow,
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

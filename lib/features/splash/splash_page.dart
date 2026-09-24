import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/widgets/pixora_logo.dart';
import '../home/home_page.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..forward().whenComplete(_go);

  late final Animation<double> _logo = CurvedAnimation(
    parent: _c,
    curve: const Interval(0, 0.55, curve: Curves.easeOutBack),
  );
  late final Animation<double> _title = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.3, 0.8, curve: PixTokens.emphasized),
  );
  late final Animation<double> _tagline = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.45, 1, curve: PixTokens.emphasized),
  );

  void _go() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: PixTokens.slow,
        pageBuilder: (_, _, _) => const HomePage(),
        transitionsBuilder: (_, a, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: a, curve: PixTokens.curve),
          child: child,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final accent = theme.colorScheme.primary;
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.2),
            radius: 1.1,
            colors: [accent.withValues(alpha: 0.16), theme.colorScheme.surface],
          ),
        ),
        child: Center(
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.scale(
                  scale: 0.6 + 0.4 * _logo.value,
                  child: Opacity(
                    opacity: _logo.value.clamp(0.0, 1.0),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(34),
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(
                              alpha: 0.35 * _logo.value.clamp(0.0, 1.0),
                            ),
                            blurRadius: 40,
                            offset: const Offset(0, 16),
                          ),
                        ],
                      ),
                      child: const PixoraLogo(size: 112),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Opacity(
                  opacity: _title.value,
                  child: Transform.translate(
                    offset: Offset(0, 16 * (1 - _title.value)),
                    child: Text(
                      'Pixora',
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Opacity(
                  opacity: _tagline.value,
                  child: Transform.translate(
                    offset: Offset(0, 12 * (1 - _tagline.value)),
                    child: Text(
                      l.appTagline,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
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

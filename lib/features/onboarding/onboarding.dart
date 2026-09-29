import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/settings/app_settings.dart';
import '../../l10n/app_localizations.dart';
import '../home/home_page.dart';
import '../intro/intro_page.dart';

/// First launch: language → permissions (only where the platform asks for
/// one) → intro → home. Each step replaces the previous one.
abstract final class Onboarding {
  /// The first screen after the splash.
  static Future<Widget> firstPage(BuildContext context) async {
    final services = AppScope.of(context);
    final settings = services.settings;
    if (!settings.languageChosen) return const LanguagePage();
    return _afterLanguage(context);
  }

  static Future<Widget> _afterLanguage(BuildContext context) async {
    final services = AppScope.of(context);
    if (!services.settings.introSeen &&
        await services.platform.needsGalleryAccess()) {
      return const PermissionPage();
    }
    return services.settings.introSeen ? const HomePage() : const IntroPage();
  }

  static void _go(BuildContext context, Widget page) {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 520),
        pageBuilder: (_, _, _) => page,
        transitionsBuilder: (_, a, _, child) {
          final c = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
          return FadeTransition(
            opacity: c,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, 0.04),
                end: Offset.zero,
              ).animate(c),
              child: child,
            ),
          );
        },
      ),
    );
  }
}

/// A soft, slowly drifting two-colour backdrop for the onboarding pages.
class _Backdrop extends StatefulWidget {
  const _Backdrop({required this.child, required this.colors});
  final Widget child;
  final List<Color> colors;

  @override
  State<_Backdrop> createState() => _BackdropState();
}

class _BackdropState extends State<_Backdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                final a = _c.value * math.pi * 2;
                return DecoratedBox(
                  decoration: BoxDecoration(
                    color: surface,
                    gradient: RadialGradient(
                      center: Alignment(
                        0.6 * math.sin(a),
                        -0.7 + 0.15 * math.cos(a),
                      ),
                      radius: 1.3,
                      colors: [
                        widget.colors[0].withValues(alpha: 0.22),
                        widget.colors[1].withValues(alpha: 0.08),
                        surface,
                      ],
                      stops: const [0, 0.45, 1],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

/// Picks the app language; the page itself switches language as you tap.
class LanguagePage extends StatefulWidget {
  const LanguagePage({super.key});

  @override
  State<LanguagePage> createState() => _LanguagePageState();
}

class _LanguagePageState extends State<LanguagePage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..forward();

  /// A glyph and a greeting for each language's card.
  static const _look = {
    'ps': ('پ', 'سلام'),
    'fa': ('ف', 'سلام'),
    'ar': ('ع', 'مرحبًا'),
    'ur': ('ا', 'السلام علیکم'),
    'en': ('En', 'Hello'),
    'es': ('Es', 'Hola'),
    'fr': ('Fr', 'Bonjour'),
    'tr': ('Tr', 'Merhaba'),
  };

  static const _hues = [
    Color(0xFF3B82F6),
    Color(0xFF8B5CF6),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFFEC4899),
    Color(0xFFEF4444),
    Color(0xFF06B6D4),
    Color(0xFF6366F1),
  ];

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  Widget _rise(int i, Widget child) {
    final start = math.min(0.6, i * 0.06);
    final a = CurvedAnimation(
      parent: _in,
      curve: Interval(
        start,
        math.min(1, start + 0.4),
        curve: Curves.easeOutCubic,
      ),
    );
    return AnimatedBuilder(
      animation: a,
      builder: (context, child) => Opacity(
        opacity: a.value,
        child: Transform.translate(
          offset: Offset(0, 20 * (1 - a.value)),
          child: child,
        ),
      ),
      child: child,
    );
  }

  Future<void> _continue() async {
    final settings = AppScope.of(context).settings;
    // Keep what the device suggested unless the user picked something.
    settings.languageChosen = true;
    final next = await Onboarding._afterLanguage(context);
    if (mounted) Onboarding._go(context, next);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final settings = AppScope.of(context).settings;
    final current =
        settings.locale?.languageCode ??
        Localizations.localeOf(context).languageCode;
    return Scaffold(
      body: _Backdrop(
        colors: [scheme.primary, const Color(0xFFEC4899)],
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 28),
                  _rise(
                    0,
                    Center(
                      child: Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [scheme.primary, const Color(0xFF8B5CF6)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: scheme.primary.withValues(alpha: 0.35),
                              blurRadius: 26,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.translate_rounded,
                          color: Colors.white,
                          size: 36,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _rise(
                    1,
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      child: Text(
                        l.chooseLanguage,
                        key: ValueKey(l.chooseLanguage),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  _rise(
                    1,
                    Text(
                      l.chooseLanguageHint,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Expanded(
                    child: GridView.builder(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 260,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            mainAxisExtent: 84,
                          ),
                      itemCount: kLanguages.length,
                      itemBuilder: (context, i) {
                        final (code, name) = kLanguages[i];
                        final (glyph, hello) = _look[code] ?? ('', '');
                        return _rise(
                          2 + i,
                          _LanguageCard(
                            name: name,
                            glyph: glyph,
                            hello: hello,
                            color: _hues[i % _hues.length],
                            selected: code == current,
                            onTap: () => settings.locale = Locale(code),
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      onPressed: _continue,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            l.continueLabel,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward_rounded),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LanguageCard extends StatelessWidget {
  const _LanguageCard({
    required this.name,
    required this.glyph,
    required this.hello,
    required this.color,
    required this.selected,
    required this.onTap,
  });
  final String name, glyph, hello;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AnimatedScale(
      scale: selected ? 1 : 0.97,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutBack,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: selected
                  ? color.withValues(alpha: 0.14)
                  : scheme.surfaceContainerLow.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: selected ? color : scheme.outlineVariant,
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: selected ? 1 : 0.14),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Text(
                    glyph,
                    style: TextStyle(
                      color: selected ? Colors.white : color,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          name,
                          maxLines: 1,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        hello,
                        maxLines: 1,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  transitionBuilder: (c, a) =>
                      ScaleTransition(scale: a, child: c),
                  child: selected
                      ? Icon(
                          Icons.check_circle_rounded,
                          key: const ValueKey(true),
                          color: color,
                        )
                      : const SizedBox(key: ValueKey(false), width: 24),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks for the gallery permission, on platforms that need one, with a
/// plain explanation of what it is for.
class PermissionPage extends StatefulWidget {
  const PermissionPage({super.key});

  @override
  State<PermissionPage> createState() => _PermissionPageState();
}

class _PermissionPageState extends State<PermissionPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();
  bool _busy = false;
  bool _granted = false;

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _next() {
    final settings = AppScope.of(context).settings;
    Onboarding._go(
      context,
      settings.introSeen ? const HomePage() : const IntroPage(),
    );
  }

  Future<void> _allow() async {
    setState(() => _busy = true);
    final ok = await AppScope.of(context).platform.requestGalleryAccess();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _granted = ok;
    });
    await Future<void>.delayed(Duration(milliseconds: ok ? 700 : 0));
    if (mounted) _next();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const green = Color(0xFF10B981);
    return Scaffold(
      body: _Backdrop(
        colors: const [green, Color(0xFF3B82F6)],
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                child: Column(
                  children: [
                    const Spacer(),
                    SizedBox(
                      width: 190,
                      height: 190,
                      child: AnimatedBuilder(
                        animation: _pulse,
                        builder: (context, child) => CustomPaint(
                          painter: _RingsPainter(_pulse.value, green),
                          child: child,
                        ),
                        child: Center(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 320),
                            transitionBuilder: (c, a) =>
                                ScaleTransition(scale: a, child: c),
                            child: Container(
                              key: ValueKey(_granted),
                              width: 104,
                              height: 104,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const LinearGradient(
                                  colors: [green, Color(0xFF059669)],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: green.withValues(alpha: 0.35),
                                    blurRadius: 30,
                                    offset: const Offset(0, 12),
                                  ),
                                ],
                              ),
                              child: Icon(
                                _granted
                                    ? Icons.check_rounded
                                    : Icons.photo_library_rounded,
                                color: Colors.white,
                                size: 50,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 26),
                    Text(
                      _granted ? l.permGranted : l.permTitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l.permBody,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLow.withValues(
                          alpha: 0.9,
                        ),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.privacy_tip_rounded,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              l.permOpenPhotos,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                        backgroundColor: green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      onPressed: _busy || _granted ? null : _allow,
                      icon: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.lock_open_rounded),
                      label: Text(
                        l.permAllow,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _busy || _granted ? null : _next,
                      child: Text(l.permNotNow),
                    ),
                    Text(
                      l.permLater,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
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
}

/// Rings that grow and fade around the permission icon.
class _RingsPainter extends CustomPainter {
  _RingsPainter(this.t, this.color);
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    for (var i = 0; i < 3; i++) {
      final p = (t + i / 3) % 1;
      canvas.drawCircle(
        c,
        52 + 44 * p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color.withValues(alpha: 0.4 * (1 - p)),
      );
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) => old.t != t;
}

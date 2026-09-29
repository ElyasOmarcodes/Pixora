import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../document/model/blend.dart';
import '../../l10n/app_localizations.dart';
import '../editor/effects_catalog.dart';
import '../settings/settings_page.dart' show kAppVersion;

/// The developer's photo, shared by the settings tile and the page (a
/// Hero flies it between them).
const kDeveloperPhoto = AssetImage('assets/images/developer.jpg');
const kDeveloperHeroTag = 'developer-photo';

/// "Meet the developer": a soft, animated page with the developer's
/// photo in a turning colour ring, a few words, what they build for and
/// Pixora in numbers.
class DeveloperPage extends StatefulWidget {
  const DeveloperPage({super.key});

  @override
  State<DeveloperPage> createState() => _DeveloperPageState();
}

class _DeveloperPageState extends State<DeveloperPage>
    with TickerProviderStateMixin {
  /// Drifts the aurora behind the page and turns the photo's ring.
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 16),
  )..repeat();

  /// The staggered entrance of the blocks.
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..forward();

  @override
  void dispose() {
    _loop.dispose();
    _enter.dispose();
    super.dispose();
  }

  /// Block [i]'s entrance: fades and rises in after the previous one.
  Widget _rise(int i, Widget child) {
    final start = (i * 0.09).clamp(0.0, 0.7);
    final curve = CurvedAnimation(
      parent: _enter,
      curve: Interval(
        start,
        math.min(1, start + 0.45),
        curve: Curves.easeOutCubic,
      ),
    );
    return AnimatedBuilder(
      animation: curve,
      builder: (context, child) => Opacity(
        opacity: curve.value,
        child: Transform.translate(
          offset: Offset(0, 26 * (1 - curve.value)),
          child: child,
        ),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final latin = l.devName != 'M. Elyas Omar';
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(l.devMeet),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _AuroraPainter(
                  _loop,
                  base: scheme.surface,
                  colors: [
                    scheme.primary,
                    const Color(0xFFEC4899),
                    const Color(0xFF06B6D4),
                  ],
                  dark: dark,
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _rise(0, Center(child: _Avatar(loop: _loop))),
                        const SizedBox(height: 22),
                        _rise(
                          1,
                          Text(
                            l.devName,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              height: 1.2,
                            ),
                          ),
                        ),
                        if (latin)
                          _rise(
                            1,
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'M. Elyas Omar',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 14),
                        _rise(2, Center(child: _Pill(text: l.devRole))),
                        const SizedBox(height: 26),
                        _rise(3, _AboutCard(text: l.devAbout)),
                        const SizedBox(height: 28),
                        _rise(
                          4,
                          _Heading(
                            icon: Icons.devices_other_rounded,
                            text: l.devBuildsFor,
                            color: const Color(0xFF8B5CF6),
                          ),
                        ),
                        const SizedBox(height: 14),
                        _rise(5, const _Platforms()),
                        const SizedBox(height: 28),
                        _rise(
                          6,
                          _Heading(
                            icon: Icons.school_rounded,
                            text: l.devTeaches,
                            color: const Color(0xFFF59E0B),
                          ),
                        ),
                        const SizedBox(height: 14),
                        _rise(7, _TeachCard(text: l.devTeachesText)),
                        const SizedBox(height: 28),
                        _rise(
                          8,
                          _Heading(
                            icon: Icons.insights_rounded,
                            text: l.devInNumbers,
                            color: const Color(0xFF10B981),
                          ),
                        ),
                        const SizedBox(height: 14),
                        _rise(9, _Numbers(l: l)),
                        const SizedBox(height: 34),
                        _rise(
                          10,
                          Column(
                            children: [
                              const Icon(
                                Icons.favorite_rounded,
                                color: Color(0xFFEC4899),
                                size: 22,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                l.devMadeWith,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Pixora ${l.versionLabel(kAppVersion)}',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: scheme.onSurfaceVariant.withValues(
                                    alpha: 0.7,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Soft colour clouds drifting slowly behind the page.
class _AuroraPainter extends CustomPainter {
  _AuroraPainter(
    this.t, {
    required this.base,
    required this.colors,
    required this.dark,
  }) : super(repaint: t);
  final Animation<double> t;
  final Color base;
  final List<Color> colors;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = base);
    final a = t.value * math.pi * 2;
    final w = size.width, h = size.height;
    final spots = [
      (
        Offset(w * (0.2 + 0.1 * math.sin(a)), h * (0.1 + 0.05 * math.cos(a))),
        w * 0.75,
      ),
      (
        Offset(
          w * (0.85 + 0.08 * math.cos(a * 1.3)),
          h * (0.2 + 0.06 * math.sin(a)),
        ),
        w * 0.65,
      ),
      (
        Offset(
          w * (0.5 + 0.2 * math.sin(a * 0.7)),
          h * (0.55 + 0.05 * math.cos(a * 1.1)),
        ),
        w * 0.8,
      ),
    ];
    for (var i = 0; i < spots.length; i++) {
      final (c, r) = spots[i];
      final color = colors[i % colors.length];
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: dark ? 0.26 : 0.2),
              color.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }
  }

  @override
  bool shouldRepaint(_AuroraPainter old) =>
      old.base != base || old.dark != dark || old.colors != colors;
}

/// The photo inside a slowly turning rainbow ring, with a soft glow.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.loop});
  final Animation<double> loop;

  static const _ring = [
    Color(0xFFF59E0B),
    Color(0xFFEC4899),
    Color(0xFF8B5CF6),
    Color(0xFF3B82F6),
    Color(0xFF06B6D4),
    Color(0xFF22C55E),
    Color(0xFFF59E0B),
  ];

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    const size = 176.0;
    return SizedBox(
      width: size + 24,
      height: size + 24,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Glow.
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.35),
                  blurRadius: 40,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          AnimatedBuilder(
            animation: loop,
            builder: (context, child) =>
                Transform.rotate(angle: loop.value * math.pi * 2, child: child),
            child: Container(
              width: size,
              height: size,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(colors: _ring),
              ),
            ),
          ),
          Container(
            width: size - 10,
            height: size - 10,
            decoration: BoxDecoration(shape: BoxShape.circle, color: surface),
          ),
          const Hero(
            tag: kDeveloperHeroTag,
            child: ClipOval(
              child: Image(
                image: kDeveloperPhoto,
                width: size - 18,
                height: size - 18,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
              ),
            ),
          ),
          PositionedDirectional(
            end: 18,
            bottom: 18,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF8B5CF6), Color(0xFF3B82F6)],
                ),
                border: Border.all(color: surface, width: 3),
              ),
              child: const Icon(
                Icons.code_rounded,
                size: 18,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelLarge
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _AboutCard extends StatelessWidget {
  const _AboutCard({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.format_quote_rounded,
            size: 34,
            color: scheme.primary.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 4),
          Text(text, style: theme.textTheme.bodyLarge?.copyWith(height: 1.8)),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.icon, required this.text, required this.color});
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 20, color: color),
        ),
        const SizedBox(width: 12),
        Text(
          text,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            height: 1,
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}

class _Platforms extends StatelessWidget {
  const _Platforms();

  static const _items = [
    ('Android', Icons.android_rounded, Color(0xFF22C55E)),
    ('iOS', Icons.phone_iphone_rounded, Color(0xFF3B82F6)),
    ('Windows', Icons.desktop_windows_rounded, Color(0xFF06B6D4)),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < _items.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(child: _PlatformCard(item: _items[i])),
        ],
      ],
    );
  }
}

class _PlatformCard extends StatefulWidget {
  const _PlatformCard({required this.item});
  final (String, IconData, Color) item;

  @override
  State<_PlatformCard> createState() => _PlatformCardState();
}

class _PlatformCardState extends State<_PlatformCard> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final (name, icon, color) = widget.item;
    final theme = Theme.of(context);
    return Listener(
      onPointerDown: (_) => setState(() => _down = true),
      onPointerUp: (_) => setState(() => _down = false),
      onPointerCancel: (_) => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down ? 0.94 : 1,
        duration: Duration(milliseconds: _down ? 110 : 380),
        curve: _down ? Curves.easeOut : Curves.elasticOut,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 22),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: color.withValues(alpha: 0.4), width: 1.4),
          ),
          child: Column(
            children: [
              Icon(icon, size: 40, color: color),
              const SizedBox(height: 10),
              Text(
                name,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TeachCard extends StatelessWidget {
  const _TeachCard({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF59E0B), Color(0xFFEA580C)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFEA580C).withValues(alpha: 0.3),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.menu_book_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Numbers extends StatelessWidget {
  const _Numbers({required this.l});
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final items = [
      (8, l.devLanguages, Icons.translate_rounded, const Color(0xFF3B82F6)),
      (
        PixBlendMode.values.length,
        l.devBlendModes,
        Icons.layers_rounded,
        const Color(0xFF8B5CF6),
      ),
      (
        fxCatalog.length,
        l.devEffects,
        Icons.auto_awesome_rounded,
        const Color(0xFFEC4899),
      ),
      (6, l.devPlatforms, Icons.devices_rounded, const Color(0xFF10B981)),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final w = (c.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final (n, label, icon, color) in items)
              SizedBox(
                width: w,
                child: _Stat(value: n, label: label, icon: icon, color: color),
              ),
          ],
        );
      },
    );
  }
}

/// A number that counts up once when it appears.
class _Stat extends StatelessWidget {
  const _Stat({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });
  final int value;
  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: value.toDouble()),
                  duration: const Duration(milliseconds: 1400),
                  curve: Curves.easeOutCubic,
                  builder: (context, v, _) => Text(
                    '${v.round()}',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: color,
                      height: 1.1,
                    ),
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

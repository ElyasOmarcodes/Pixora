import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_scope.dart';
import '../../l10n/app_localizations.dart';
import '../home/home_page.dart';

/// First-launch introduction: four pages, each with a looping vector
/// animation and one line about what Pixora can do. Swipe or tap Next;
/// the background colour, illustration and dots all move with the finger.
class IntroPage extends StatefulWidget {
  const IntroPage({super.key, this.replay = false});

  /// Opened again from Settings: finishing just closes it.
  final bool replay;

  /// Opens the home screen once the intro is done (or skipped).
  static void finish(BuildContext context) {
    final replay =
        context.findAncestorWidgetOfExactType<IntroPage>()?.replay ?? false;
    if (replay) {
      Navigator.of(context).pop();
      return;
    }
    AppScope.of(context).settings.introSeen = true;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 650),
        pageBuilder: (_, _, _) => const HomePage(),
        transitionsBuilder: (_, a, _, child) {
          final c = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
          return FadeTransition(
            opacity: c,
            child: ScaleTransition(
              scale: Tween(begin: 1.04, end: 1.0).animate(c),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  State<IntroPage> createState() => _IntroPageState();
}

class _Slide {
  const _Slide(this.colors, this.painter, this.title, this.body);
  final List<Color> colors;
  final CustomPainter Function(Animation<double> t) painter;
  final String Function(AppLocalizations l) title;
  final String Function(AppLocalizations l) body;
}

class _IntroPageState extends State<IntroPage> with TickerProviderStateMixin {
  final PageController _pages = PageController();

  /// Drives every illustration (a slow endless loop).
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat();

  static final _slides = <_Slide>[
    _Slide(
      const [Color(0xFF3A5BFF), Color(0xFF7B5CFF)],
      (t) => _LayersPainter(t),
      (l) => l.introTitle1,
      (l) => l.introBody1,
    ),
    _Slide(
      const [Color(0xFFFF6B8B), Color(0xFFFF9A5C)],
      (t) => _TypePainter(t),
      (l) => l.introTitle2,
      (l) => l.introBody2,
    ),
    _Slide(
      const [Color(0xFF00B894), Color(0xFF00A3FF)],
      (t) => _EffectsPainter(t),
      (l) => l.introTitle3,
      (l) => l.introBody3,
    ),
    _Slide(
      const [Color(0xFF8E44FF), Color(0xFFFF4FA3)],
      (t) => _ExportPainter(t),
      (l) => l.introTitle4,
      (l) => l.introBody4,
    ),
  ];

  double _page = 0;

  @override
  void initState() {
    super.initState();
    _pages.addListener(() {
      final p = _pages.page ?? 0;
      if (p != _page) setState(() => _page = p);
    });
  }

  @override
  void dispose() {
    _pages.dispose();
    _loop.dispose();
    super.dispose();
  }

  List<Color> _colorsAt(double p) {
    final i = p.floor().clamp(0, _slides.length - 1);
    final j = (i + 1).clamp(0, _slides.length - 1);
    final f = (p - i).clamp(0.0, 1.0);
    final a = _slides[i].colors, b = _slides[j].colors;
    return [Color.lerp(a[0], b[0], f)!, Color.lerp(a[1], b[1], f)!];
  }

  void _next() {
    HapticFeedback.selectionClick();
    final i = _page.round();
    if (i >= _slides.length - 1) {
      IntroPage.finish(context);
      return;
    }
    _pages.animateToPage(
      i + 1,
      duration: const Duration(milliseconds: 620),
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = _colorsAt(_page);
    final last = _page.round() >= _slides.length - 1;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
          ),
          child: Stack(
            children: [
              // Soft floating bubbles behind everything.
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(painter: _BubblesPainter(_loop)),
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 250),
                        opacity: last ? 0 : 1,
                        child: TextButton(
                          onPressed: last
                              ? null
                              : () => IntroPage.finish(context),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                          ),
                          child: Text(l.skip),
                        ),
                      ),
                    ),
                    Expanded(
                      child: PageView.builder(
                        controller: _pages,
                        itemCount: _slides.length,
                        itemBuilder: (context, i) {
                          final s = _slides[i];
                          final d = (_page - i).clamp(-1.0, 1.0);
                          return _SlideView(
                            offset: d,
                            illustration: RepaintBoundary(
                              child: CustomPaint(
                                painter: s.painter(_loop),
                                size: Size.infinite,
                              ),
                            ),
                            title: s.title(l),
                            body: s.body(l),
                          );
                        },
                      ),
                    ),
                    _Dots(count: _slides.length, page: _page),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
                      child: SizedBox(
                        width: double.infinity,
                        height: 58,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: colors[0],
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            elevation: 0,
                          ),
                          onPressed: _next,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 250),
                            child: Row(
                              key: ValueKey(last),
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  last ? l.getStarted : l.next,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  last
                                      ? Icons.rocket_launch_rounded
                                      : Icons.arrow_forward_rounded,
                                  textDirection: Directionality.of(context),
                                ),
                              ],
                            ),
                          ),
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
    );
  }
}

/// One page: the illustration drifts and fades with the swipe ([offset]
/// −1…1), the text follows a little behind it (parallax).
class _SlideView extends StatelessWidget {
  const _SlideView({
    required this.offset,
    required this.illustration,
    required this.title,
    required this.body,
  });
  final double offset;
  final Widget illustration;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final a = 1 - offset.abs();
    final dir = Directionality.of(context) == TextDirection.rtl ? -1 : 1;
    return LayoutBuilder(
      builder: (context, box) => Column(
        children: [
          Expanded(
            flex: 6,
            child: Opacity(
              opacity: a.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(offset * box.maxWidth * 0.35 * dir, 0),
                child: Transform.scale(
                  scale: 0.85 + 0.15 * a,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: illustration,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Opacity(
              opacity: (a * a).clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(offset * box.maxWidth * 0.15 * dir, 0),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 30),
                  child: Column(
                    children: [
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 27,
                          fontWeight: FontWeight.w900,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        body,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.88),
                          fontSize: 16,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.page});
  final int count;
  final double page;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      for (var i = 0; i < count; i++)
        Builder(
          builder: (context) {
            final near = (1 - (page - i).abs()).clamp(0.0, 1.0);
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: 8 + 22 * near,
              height: 8,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.4 + 0.6 * near),
                borderRadius: BorderRadius.circular(4),
              ),
            );
          },
        ),
    ],
  );
}

// ------------------------------------------------------------ painting

double _wave(double t, [double phase = 0]) =>
    math.sin((t + phase) * 2 * math.pi);

/// Slow translucent bubbles drifting upwards.
class _BubblesPainter extends CustomPainter {
  _BubblesPainter(this.t) : super(repaint: t);
  final Animation<double> t;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.white.withValues(alpha: 0.07);
    for (var i = 0; i < 9; i++) {
      final seed = i * 0.137;
      final x = size.width * ((i * 0.23 + 0.1) % 1);
      final y =
          size.height * (1 - ((t.value * (0.3 + seed) + i * 0.19) % 1.2)) + 40;
      final r = 18.0 + (i % 4) * 22;
      canvas.drawCircle(Offset(x + 14 * _wave(t.value, seed), y), r, p);
    }
  }

  @override
  bool shouldRepaint(_BubblesPainter old) => false;
}

RRect _card(Offset c, double w, double h, [double r = 22]) =>
    RRect.fromRectAndRadius(
      Rect.fromCenter(center: c, width: w, height: h),
      Radius.circular(r),
    );

void _shadowed(Canvas canvas, RRect r, Paint fill, [double alpha = 1]) {
  canvas
    ..drawRRect(
      r.shift(const Offset(0, 10)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.18 * alpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    )
    ..drawRRect(r, fill);
}

/// Page 1 — layers: a photo, a text and a shape card that fan out and
/// stack back together, with sparkles.
class _LayersPainter extends CustomPainter {
  _LayersPainter(this.t) : super(repaint: t);
  final Animation<double> t;

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height) / 300;
    final c = size.center(Offset.zero);
    canvas
      ..save()
      ..translate(c.dx, c.dy)
      ..scale(s);
    // 0 → stacked, 1 → fanned out, eased back and forth.
    final fan = 0.5 - 0.5 * math.cos(t.value * 2 * math.pi);
    final e = Curves.easeInOutCubic.transform(fan);
    final white = Paint()..color = Colors.white;

    // Back: shape card.
    canvas
      ..save()
      ..translate(-70 * e, -46 * e)
      ..rotate(-0.16 * e);
    final back = _card(Offset.zero, 170, 130);
    _shadowed(canvas, back, white);
    canvas
      ..drawCircle(
        const Offset(-30, 0),
        30,
        Paint()..color = const Color(0xFFFFC857),
      )
      ..drawPath(
        _star(const Offset(38, 4), 30, 14),
        Paint()..color = const Color(0xFF7B5CFF),
      )
      ..restore();

    // Middle: text card.
    canvas
      ..save()
      ..translate(64 * e, -18 * e)
      ..rotate(0.12 * e);
    final mid = _card(Offset.zero, 170, 130);
    _shadowed(canvas, mid, white);
    final bar = Paint()..color = const Color(0xFF3A5BFF);
    final grey = Paint()..color = const Color(0xFFD6DBF5);
    canvas.drawRRect(_card(const Offset(0, -34), 120, 18, 9), bar);
    for (var i = 0; i < 3; i++) {
      final w = 130.0 - i * 26;
      canvas.drawRRect(_card(Offset(0, -2 + i * 22.0), w, 10, 5), grey);
    }
    canvas.restore();

    // Front: photo card with mountains and a rising sun.
    canvas
      ..save()
      ..translate(0, 52 * e)
      ..rotate(-0.04 * e);
    final front = _card(Offset.zero, 190, 140);
    _shadowed(canvas, front, white);
    canvas
      ..save()
      ..clipRRect(front.deflate(10));
    canvas.drawRect(
      const Rect.fromLTRB(-95, -70, 95, 70),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF9BD7FF), Color(0xFFE8F4FF)],
        ).createShader(const Rect.fromLTRB(-95, -70, 95, 70)),
    );
    canvas.drawCircle(
      Offset(40, 6 - 22 * e),
      18,
      Paint()..color = const Color(0xFFFFB547),
    );
    final hills = Path()
      ..moveTo(-95, 70)
      ..lineTo(-40, 0)
      ..lineTo(0, 40)
      ..lineTo(40, 10)
      ..lineTo(95, 70)
      ..close();
    canvas
      ..drawPath(hills, Paint()..color = const Color(0xFF2EC4A0))
      ..restore()
      ..restore();

    // Sparkles.
    for (var i = 0; i < 4; i++) {
      final a = (0.5 + 0.5 * _wave(t.value * 2, i * 0.25)).clamp(0.0, 1.0);
      final p = Offset(
        const [-120.0, 118.0, 100.0, -110.0][i],
        const [-100.0, -96.0, 104.0, 96.0][i],
      );
      canvas.drawPath(
        _star(p, 10 * a + 2, 3 * a + 1, points: 4),
        Paint()..color = Colors.white.withValues(alpha: a),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LayersPainter old) => false;
}

Path _star(Offset c, double outer, double inner, {int points = 5}) {
  final p = Path();
  for (var i = 0; i < points * 2; i++) {
    final r = i.isEven ? outer : inner;
    final a = -math.pi / 2 + i * math.pi / points;
    final o = c + Offset(math.cos(a) * r, math.sin(a) * r);
    i == 0 ? p.moveTo(o.dx, o.dy) : p.lineTo(o.dx, o.dy);
  }
  return p..close();
}

/// Page 2 — typography: a shimmering "اب Aa", justified lines whose word
/// gaps breathe, and a blinking caret.
class _TypePainter extends CustomPainter {
  _TypePainter(this.t) : super(repaint: t);
  final Animation<double> t;

  static final _glyphs = TextPainter(
    text: const TextSpan(
      text: 'اب Aa',
      style: TextStyle(
        fontFamily: 'Vazirmatn',
        fontSize: 66,
        fontWeight: FontWeight.w900,
        color: Colors.white,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height) / 300;
    final c = size.center(Offset.zero);
    canvas
      ..save()
      ..translate(c.dx, c.dy)
      ..scale(s);
    final page = _card(const Offset(0, 10), 230, 250, 26);
    _shadowed(canvas, page, Paint()..color = Colors.white);

    // Shimmering gradient over the glyphs.
    final g = _glyphs;
    final gw = g.width, gh = g.height;
    final shift = (t.value * 2 % 1) * (gw + 160) - 80;
    canvas.saveLayer(Rect.fromLTWH(-gw / 2, -118, gw, gh), Paint());
    g.paint(canvas, Offset(-gw / 2, -118));
    canvas
      ..drawRect(
        Rect.fromLTWH(-gw / 2, -118, gw, gh),
        Paint()
          ..blendMode = BlendMode.srcIn
          ..shader = const LinearGradient(
            colors: [Color(0xFFFF6B8B), Color(0xFFFFC36B), Color(0xFFFF6B8B)],
            stops: [0, 0.5, 1],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ).createShader(Rect.fromLTWH(-gw / 2 + shift - 80, 0, 160, 1)),
      )
      ..restore();

    // Justified lines: words widen and narrow, edges stay put.
    final breathe = 0.5 + 0.5 * _wave(t.value * 1.5);
    final word = Paint()..color = const Color(0xFFFFD2DB);
    for (var row = 0; row < 4; row++) {
      final y = 20.0 + row * 24;
      final last = row == 3;
      final words = [3, 4, 3, 2][row];
      const left = -90.0, right = 90.0;
      final base = [0.28, 0.22, 0.3, 0.26][row];
      final gap = last ? 8.0 : 8 + 10 * breathe;
      final total = last ? 120.0 : right - left;
      final ww = (total - gap * (words - 1)) / words;
      // Right-to-left: the first word starts at the right edge.
      var x = right;
      for (var k = 0; k < words; k++) {
        final w = ww * (1 + (k.isEven ? base : -base) * 0.4);
        final clamped = k == words - 1 && !last ? x - left : w;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(x - clamped, y - 5, x, y + 5),
            const Radius.circular(5),
          ),
          word,
        );
        x -= clamped + gap;
      }
    }
    // Caret.
    if ((t.value * 6).floor().isEven) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(-34, 84, 3, 22),
          const Radius.circular(2),
        ),
        Paint()..color = const Color(0xFFFF6B8B),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TypePainter old) => false;
}

/// Page 3 — effects: a glowing star that turns and changes colour, orbiting
/// light dots and sliders that glide.
class _EffectsPainter extends CustomPainter {
  _EffectsPainter(this.t) : super(repaint: t);
  final Animation<double> t;

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height) / 300;
    final c = size.center(Offset.zero);
    canvas
      ..save()
      ..translate(c.dx, c.dy)
      ..scale(s);
    final v = t.value;
    final pulse = 0.5 + 0.5 * _wave(v * 2);
    // Glow.
    canvas.drawCircle(
      const Offset(0, -30),
      90 + 14 * pulse,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.18 + 0.12 * pulse)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30),
    );
    // Rotating star with a turning gradient.
    canvas
      ..save()
      ..translate(0, -30)
      ..rotate(v * 2 * math.pi / 3);
    final star = _star(Offset.zero, 78, 38, points: 6);
    canvas
      ..drawPath(
        star.shift(const Offset(0, 8)),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.18)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
      )
      ..drawPath(
        star,
        Paint()
          ..shader = SweepGradient(
            colors: const [
              Color(0xFFFFFFFF),
              Color(0xFFB8FFF0),
              Color(0xFF9AD7FF),
              Color(0xFFFFFFFF),
            ],
            transform: GradientRotation(v * 2 * math.pi),
          ).createShader(const Rect.fromLTRB(-78, -78, 78, 78)),
      )
      ..restore();
    // Orbiting dots.
    for (var i = 0; i < 5; i++) {
      final a = v * 2 * math.pi + i * 2 * math.pi / 5;
      final o = Offset(math.cos(a) * 118, -30 + math.sin(a) * 50);
      canvas.drawCircle(
        o,
        6 + 3 * math.sin(a),
        Paint()..color = Colors.white.withValues(alpha: 0.85),
      );
    }
    // Sliders.
    for (var i = 0; i < 2; i++) {
      final y = 92.0 + i * 30;
      canvas.drawRRect(
        _card(Offset(0, y), 200, 8, 4),
        Paint()..color = Colors.white.withValues(alpha: 0.35),
      );
      final k = 0.5 + 0.45 * _wave(v * (i == 0 ? 1 : 2), i * 0.3);
      final x = -100 + 200 * k;
      canvas
        ..drawRRect(
          RRect.fromLTRBR(-100, y - 4, x, y + 4, const Radius.circular(4)),
          Paint()..color = Colors.white,
        )
        ..drawCircle(Offset(x, y), 11, Paint()..color = Colors.white)
        ..drawCircle(Offset(x, y), 5, Paint()..color = const Color(0xFF00B894));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_EffectsPainter old) => false;
}

/// Page 4 — create and share: layers slide together into a finished
/// poster, a check pops, and the poster flies out (export).
class _ExportPainter extends CustomPainter {
  _ExportPainter(this.t) : super(repaint: t);
  final Animation<double> t;

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height) / 300;
    final c = size.center(Offset.zero);
    canvas
      ..save()
      ..translate(c.dx, c.dy)
      ..scale(s);
    final v = t.value;
    // 0–0.45 merge, 0.45–0.75 check, 0.75–1 fly out and come back.
    final merge = Curves.easeInOutCubic.transform((v / 0.45).clamp(0.0, 1.0));
    final check = Curves.elasticOut.transform(
      ((v - 0.45) / 0.3).clamp(0.0, 1.0),
    );
    final fly = Curves.easeInCubic.transform(((v - 0.8) / 0.2).clamp(0.0, 1.0));

    canvas.translate(0, -40 * fly);
    final alpha = 1 - fly;
    final colors = [
      const Color(0xFFFFE08A),
      const Color(0xFFFF9EC7),
      const Color(0xFF9EC5FF),
    ];
    for (var i = 2; i >= 0; i--) {
      final spread = (1 - merge) * (i - 1) * 46;
      final r = _card(Offset(spread, spread * 0.6 - 10), 170, 210, 24);
      _shadowed(
        canvas,
        r,
        Paint()
          ..color = Color.lerp(
            colors[i],
            Colors.white,
            merge,
          )!.withValues(alpha: alpha),
        alpha / 3,
      );
    }
    // The finished poster.
    if (merge > 0) {
      final poster = _card(const Offset(0, -10), 170, 210, 24);
      canvas
        ..save()
        ..clipRRect(poster);
      canvas.drawRect(
        poster.outerRect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF8E44FF), Color(0xFFFF4FA3)],
          ).createShader(poster.outerRect)
          ..color = Colors.white.withValues(alpha: merge * alpha),
      );
      canvas
        ..drawCircle(
          const Offset(0, -40),
          34,
          Paint()..color = Colors.white.withValues(alpha: 0.9 * merge * alpha),
        )
        ..drawRRect(
          _card(const Offset(0, 30), 110, 14, 7),
          Paint()..color = Colors.white.withValues(alpha: 0.9 * merge * alpha),
        )
        ..drawRRect(
          _card(const Offset(0, 56), 76, 10, 5),
          Paint()..color = Colors.white.withValues(alpha: 0.6 * merge * alpha),
        )
        ..restore();
    }
    // Check badge.
    if (check > 0) {
      canvas
        ..save()
        ..translate(70, 80)
        ..scale(check);
      canvas.drawCircle(
        Offset.zero,
        26,
        Paint()..color = Colors.white.withValues(alpha: alpha),
      );
      final tick = Path()
        ..moveTo(-11, 0)
        ..lineTo(-3, 8)
        ..lineTo(12, -8);
      canvas
        ..drawPath(
          tick,
          Paint()
            ..color = const Color(0xFF2EC4A0).withValues(alpha: alpha)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        )
        ..restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ExportPainter old) => false;
}

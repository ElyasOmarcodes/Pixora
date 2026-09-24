import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Design tokens. Every radius, duration and spacing in the app comes from
/// here so the look stays consistent and can be tuned in one place.
abstract final class PixTokens {
  static const double radiusS = 12;
  static const double radiusM = 18;
  static const double radiusL = 26;
  static const double radiusXL = 34;

  static const double gap = 12;

  static const Duration fast = Duration(milliseconds: 160);
  static const Duration medium = Duration(milliseconds: 280);
  static const Duration slow = Duration(milliseconds: 460);

  /// Soft, springy curve used for most motion.
  static const Curve curve = Curves.easeOutCubic;
  static const Curve emphasized = Cubic(0.2, 0.0, 0.0, 1.0);

  static const String fontFamily = 'Vazirmatn';
}

/// Extra colors the Material scheme doesn't cover.
@immutable
class PixColors extends ThemeExtension<PixColors> {
  const PixColors({
    required this.canvasBackdrop,
    required this.checkerA,
    required this.checkerB,
    required this.selection,
    required this.guide,
    required this.softShadow,
  });

  final Color canvasBackdrop;
  final Color checkerA;
  final Color checkerB;
  final Color selection;
  final Color guide;
  final Color softShadow;

  static PixColors of(BuildContext context) =>
      Theme.of(context).extension<PixColors>()!;

  @override
  PixColors copyWith({
    Color? canvasBackdrop,
    Color? checkerA,
    Color? checkerB,
    Color? selection,
    Color? guide,
    Color? softShadow,
  }) => PixColors(
    canvasBackdrop: canvasBackdrop ?? this.canvasBackdrop,
    checkerA: checkerA ?? this.checkerA,
    checkerB: checkerB ?? this.checkerB,
    selection: selection ?? this.selection,
    guide: guide ?? this.guide,
    softShadow: softShadow ?? this.softShadow,
  );

  @override
  PixColors lerp(PixColors? other, double t) {
    if (other == null) return this;
    return PixColors(
      canvasBackdrop: Color.lerp(canvasBackdrop, other.canvasBackdrop, t)!,
      checkerA: Color.lerp(checkerA, other.checkerA, t)!,
      checkerB: Color.lerp(checkerB, other.checkerB, t)!,
      selection: Color.lerp(selection, other.selection, t)!,
      guide: Color.lerp(guide, other.guide, t)!,
      softShadow: Color.lerp(softShadow, other.softShadow, t)!,
    );
  }
}

abstract final class AppTheme {
  static ThemeData light(Color accent) => _build(accent, Brightness.light);
  static ThemeData dark(Color accent) => _build(accent, Brightness.dark);

  static ThemeData _build(Color accent, Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: accent,
          brightness: brightness,
          dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
        ).copyWith(
          primary: dark ? null : accent,
          surface: dark ? const Color(0xFF111318) : const Color(0xFFF7F8FC),
        );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      fontFamily: PixTokens.fontFamily,
      scaffoldBackgroundColor: scheme.surface,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
    );

    final rounded = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(PixTokens.radiusM),
    );

    return base.copyWith(
      extensions: [
        PixColors(
          canvasBackdrop: dark
              ? const Color(0xFF0B0C10)
              : const Color(0xFFECEEF4),
          checkerA: dark ? const Color(0xFF2A2D35) : const Color(0xFFFFFFFF),
          checkerB: dark ? const Color(0xFF1F2128) : const Color(0xFFE3E6EE),
          selection: accent,
          guide: const Color(0xFFFF4FA3),
          softShadow: dark ? const Color(0x66000000) : const Color(0x1A1B2A4E),
        ),
      ],
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: dark ? const Color(0xFF1A1C23) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PixTokens.radiusL),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 50),
          shape: rounded,
          textStyle: const TextStyle(
            fontFamily: PixTokens.fontFamily,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 50),
          shape: rounded,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: rounded),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xFF1F2129) : const Color(0xFFEFF1F7),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PixTokens.radiusM),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: dark ? const Color(0xFF16181E) : Colors.white,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(PixTokens.radiusXL),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: dark ? const Color(0xFF1A1C23) : Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PixTokens.radiusXL),
        ),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 4,
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
        thumbShape: const RoundSliderThumbShape(
          enabledThumbRadius: 9,
          elevation: 2,
        ),
        inactiveTrackColor: scheme.primary.withValues(alpha: 0.15),
        showValueIndicator: ShowValueIndicator.never,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: rounded,
        contentTextStyle: const TextStyle(fontFamily: PixTokens.fontFamily),
      ),
      listTileTheme: ListTileThemeData(shape: rounded),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 500),
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(PixTokens.radiusS),
        ),
        textStyle: TextStyle(
          color: scheme.onInverseSurface,
          fontFamily: PixTokens.fontFamily,
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _SoftPageTransitions(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: _SoftPageTransitions(),
          TargetPlatform.windows: _SoftPageTransitions(),
          TargetPlatform.linux: _SoftPageTransitions(),
        },
      ),
    );
  }
}

/// Fade + gentle scale-up used for route changes on non-iOS platforms.
class _SoftPageTransitions extends PageTransitionsBuilder {
  const _SoftPageTransitions();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: PixTokens.emphasized,
    );
    final outgoing = CurvedAnimation(
      parent: secondaryAnimation,
      curve: PixTokens.curve,
    );
    return FadeTransition(
      opacity: Tween(begin: 1.0, end: 0.92).animate(outgoing),
      child: FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween(begin: 0.965, end: 1.0).animate(curved),
          child: child,
        ),
      ),
    );
  }
}

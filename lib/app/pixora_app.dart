import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../features/splash/splash_page.dart';
import '../l10n/app_localizations.dart';
import 'app_scope.dart';
import 'theme/app_theme.dart';

class PixoraApp extends StatelessWidget {
  const PixoraApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => MaterialApp(
        title: 'Pixora',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(settings.accent),
        darkTheme: AppTheme.dark(settings.accent),
        themeMode: settings.themeMode,
        themeAnimationDuration: PixTokens.medium,
        themeAnimationCurve: PixTokens.curve,
        locale: settings.locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          _CupertinoFallbackDelegate(),
        ],
        localeResolutionCallback: (device, supported) {
          if (device == null) return const Locale('en');
          for (final l in supported) {
            if (l.languageCode == device.languageCode) return l;
          }
          return const Locale('en');
        },
        home: const SplashPage(),
      ),
    );
  }
}

/// Flutter ships no Cupertino strings for Pashto; borrow the closest
/// supported RTL language so iOS-style widgets still work.
class _CupertinoFallbackDelegate
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const _CupertinoFallbackDelegate();

  static const _fallbacks = {'ps': Locale('fa')};

  @override
  bool isSupported(Locale locale) =>
      _fallbacks.containsKey(locale.languageCode);

  @override
  Future<CupertinoLocalizations> load(Locale locale) =>
      GlobalCupertinoLocalizations.delegate.load(
        _fallbacks[locale.languageCode]!,
      );

  @override
  bool shouldReload(_CupertinoFallbackDelegate old) => false;
}

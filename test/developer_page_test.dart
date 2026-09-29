import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixora/features/about/developer_page.dart';
import 'package:pixora/l10n/app_localizations.dart';

void main() {
  for (final locale in const [Locale('en'), Locale('fa')]) {
    testWidgets('developer page renders in ${locale.languageCode}', (t) async {
      await t.pumpWidget(
        MaterialApp(
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const DeveloperPage(),
        ),
      );
      await t.pump(const Duration(seconds: 2));
      final l = AppLocalizations.of(t.element(find.byType(DeveloperPage)));
      expect(find.text(l.devName), findsOneWidget);
      expect(find.text('Android'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
}

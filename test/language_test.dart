import 'package:anisched/src/services/catalogue_reader.dart';
import 'package:anisched/src/services/device_settings.dart';
import 'package:anisched/src/ui/app.dart';
import 'package:anisched/src/ui/shell.dart';
import 'package:anisched/src/ui/text/strings.dart';
import 'package:anisched/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sample_catalogue.dart';

final now = DateTime(2026, 11, 27, 14);

void main() {
  tearDown(() {
    languageSetting.value = LanguageChoice.device;
    appLang.value = Lang.ko;
  });

  test('every word has all five languages and the same placeholders', () {
    final mark = RegExp(r'\{\w+\}');
    for (final s in S.values) {
      final keys = {for (final m in mark.allMatches(s.en)) m[0]};
      for (final l in Lang.values) {
        final text = s.of(l);
        expect(text, isNotEmpty, reason: '${s.name} ${l.name}');
        expect(
          {for (final m in mark.allMatches(text)) m[0]},
          keys,
          reason: '${s.name} ${l.name}',
        );
      }
    }
  });

  test('the device language picks a shipped one, else English', () {
    expect(Lang.forLocales(const [Locale('de'), Locale('ja')]), Lang.ja);
    expect(Lang.forLocales(const [Locale('zh', 'TW')]), Lang.zhHans);
    expect(Lang.forLocales(const [Locale('de')]), Lang.en);
    expect(resolveLang(LanguageChoice.fr, const [Locale('ja')]), Lang.fr);
  });

  testWidgets('the language row relabels the whole app', (t) async {
    t.view.physicalSize = const Size(1440, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(const AnischedApp());
    await t.tap(find.text('설정'));
    await t.pump();
    await t.tap(find.byKey(const Key('lang-en')));
    await t.pump();
    expect(find.text('Settings'), findsWidgets);
    expect(find.text('Language'), findsOneWidget);
    await t.tap(find.byKey(const Key('lang-ja')));
    await t.pump();
    expect(find.text('設定'), findsWidgets);
    expect(find.text('言語'), findsOneWidget);
    final app = t.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.locale, const Locale('ja'));
  });

  // Overflow risk grows with word length and shrinks with width: French
  // and English are the longest tables, phones the narrowest (and
  // shortest) screens. Korean is laid out by every other widget test;
  // Japanese and Chinese words are shorter.
  for (final lang in const [Lang.en, Lang.fr]) {
    for (final size in const [Size(390, 844), Size(844, 390)]) {
      testWidgets('${lang.name} lays out every view at $size', (t) async {
        appLang.value = lang;
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final store = sampleCatalogue(now);
        for (final view in AppView.values) {
          await t.pumpWidget(
            MaterialApp(
              key: ValueKey(view),
              locale: lang.locale,
              supportedLocales: [for (final l in Lang.values) l.locale],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              theme: AppTheme.light(),
              home: AppShell(
                initialView: view,
                reader: SyncCatalogueReader(store),
                store: store,
                clock: () => now,
              ),
            ),
          );
          await t.pump();
          expect(t.takeException(), isNull, reason: view.name);
        }
      });
    }
  }
}

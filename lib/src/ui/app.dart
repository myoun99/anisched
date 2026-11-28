import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../services/catalogue_reader.dart';
import '../services/catalogue_store.dart';
import '../services/document_session.dart';
import '../services/work_timer.dart';
import 'shell.dart';
import 'text/strings.dart';
import 'theme.dart';

class AnischedApp extends StatefulWidget {
  const AnischedApp({
    super.key,
    this.reader,
    this.store,
    this.timer,
    this.session,
    this.remote,
  });

  /// Reads the user's catalogue; null shows empty views (widget tests).
  final CatalogueReader? reader;

  /// Writes (status changes); null keeps the app read-only.
  final CatalogueStore? store;

  /// The work timer's store.
  final WorkTimerStore? timer;

  /// The open document; null hides the file menu.
  final DocumentSessionBase? session;

  /// The last resume check.
  final ValueListenable<RemoteCheck?>? remote;

  @override
  State<AnischedApp> createState() => _AnischedAppState();
}

class _AnischedAppState extends State<AnischedApp> with WidgetsBindingObserver {
  final _settings = Listenable.merge([themeModeSetting, appLang]);

  @override
  void initState() {
    super.initState();
    appLang.addListener(_relabel);
    languageSetting.addListener(_resolve);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    languageSetting.removeListener(_resolve);
    appLang.removeListener(_relabel);
    super.dispose();
  }

  void _resolve() => appLang.value = resolveLang(
    languageSetting.value,
    WidgetsBinding.instance.platformDispatcher.locales,
  );

  /// The device language changed: follow it unless one is fixed.
  @override
  void didChangeLocales(List<Locale>? locales) => _resolve();

  /// Words are read in build methods, some of them under const widgets:
  /// on a language change every element builds again (state is kept).
  void _relabel() {
    void mark(Element e) {
      e.markNeedsBuild();
      e.visitChildren(mark);
    }

    (context as Element).visitChildren(mark);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _settings,
      builder: (context, _) => MaterialApp(
        themeMode: themeModeSetting.value,
        themeAnimationDuration: Duration.zero,
        title: 'Anisched',
        debugShowCheckedModeBanner: false,
        locale: appLang.value.locale,
        supportedLocales: [for (final l in Lang.values) l.locale],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: AppTheme.light(appLang.value),
        darkTheme: AppTheme.dark(appLang.value),
        scrollBehavior: const AlwaysScrollbarBehavior(),
        home: AppShell(
          reader: widget.reader,
          store: widget.store,
          timer: widget.timer,
          session: widget.session,
          remote: widget.remote,
        ),
      ),
    );
  }
}

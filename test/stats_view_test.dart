import 'package:anisched/src/models/stats.dart';
import 'package:anisched/src/services/catalogue_reader.dart';
import 'package:anisched/src/ui/shell.dart';
import 'package:anisched/src/ui/text/strings.dart';
import 'package:anisched/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sample_catalogue.dart';

final now = DateTime(2026, 11, 27, 14);

class CountingReader extends SyncCatalogueReader {
  CountingReader(super.store);

  final asked = <StatsBucket>[];
  final askedWorks = <int?>[];

  @override
  Future<Stats> stats({
    required DateTime from,
    required DateTime to,
    StatsBucket bucket = StatsBucket.week,
    int? clientId,
    int? workId,
  }) {
    asked.add(bucket);
    askedWorks.add(workId);
    return super.stats(
      from: from,
      to: to,
      bucket: bucket,
      clientId: clientId,
      workId: workId,
    );
  }
}

Future<CountingReader> pumpStats(
  WidgetTester t,
  Size size, {
  AppView view = AppView.stats,
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final store = sampleCatalogue(now);
  final reader = CountingReader(store);
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: AppShell(
        initialView: view,
        reader: reader,
        store: store,
        clock: () => now,
      ),
    ),
  );
  await t.pump();
  await t.pump();
  return reader;
}

void main() {
  tearDown(() => appLang.value = Lang.ko);

  for (final lang in [Lang.ko, Lang.en, Lang.fr]) {
    for (final size in const [
      Size(390, 844),
      Size(844, 390),
      Size(800, 1280),
      Size(1440, 900),
    ]) {
      testWidgets('${lang.name} stats lay out at $size', (t) async {
        appLang.value = lang;
        await pumpStats(t, size);
        expect(t.takeException(), isNull);
        expect(find.text(S.kWorked.t), findsOneWidget);
        expect(find.text(S.kFirstDue.t), findsOneWidget);
      });
    }
  }

  testWidgets('nothing loads until the tab is shown', (t) async {
    final reader = await pumpStats(
      t,
      const Size(1440, 900),
      view: AppView.list,
    );
    expect(reader.asked, isEmpty);
    await t.tap(find.byKey(const Key('view-tab-stats')));
    await t.pump();
    await t.pump();
    expect(reader.asked, isNotEmpty);
  });

  testWidgets('bucket and range reload', (t) async {
    final reader = await pumpStats(t, const Size(1440, 900));
    await t.tap(find.byKey(const Key('stats-bucket-month')));
    await t.pump();
    expect(reader.asked.last, StatsBucket.month);
    final before = reader.asked.length;
    await t.tap(find.byKey(const Key('stats-range')));
    await t.pump();
    await t.tap(find.byKey(const Key('stats-range-months12')));
    await t.pump();
    await t.pump();
    expect(reader.asked.length, before + 1);
    expect(find.text('12달'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('the shared filter narrows the statistics', (t) async {
    final reader = await pumpStats(t, const Size(1440, 900));
    final work = reader.store.partGroups().first;
    await t.tap(find.byKey(const Key('filter-button')));
    await t.pump();
    await t.tap(find.text(work.workTitle).last);
    await t.pump();
    await t.pump();
    expect(reader.askedWorks.last, work.workId);
  });
}

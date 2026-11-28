import 'package:anisched/src/models/progress.dart';
import 'package:anisched/src/services/catalogue_reader.dart';
import 'package:anisched/src/ui/shell.dart';
import 'package:anisched/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'date_span_test.dart' show now, open, pumpAt;
import 'support/sample_catalogue.dart';

DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Taps [key] and reads the day the picker opened on (its month shown,
/// that day marked), then closes it.
Future<DateTime?> openedOn(WidgetTester t, String key) async {
  await t.tap(find.byKey(Key(key)));
  await t.pump();
  final picker = t.widget<DatePickerDialog>(find.byType(DatePickerDialog));
  await t.tapAt(const Offset(2, 2));
  await t.pump();
  return picker.initialDate;
}

void main() {
  // The picker opens on the date there is; else on the paired one (a
  // start's deadline, a deadline's start; the estimate's other end); else
  // on today (유저 2026-11-28).
  PartGroup pick(Iterable<PartGroup> gs) => gs.firstWhere(
    (g) =>
        g.kind == GroupKind.part &&
        g.kickoffAt != null &&
        g.dueAt != null &&
        g.dueAt!.isAfter(now) &&
        g.planStartAt == null &&
        g.planEndAt == null,
  );

  testWidgets('a date that is set: the picker opens on it', (t) async {
    final store = await pumpAt(t, AppView.list);
    final g = pick(store.partGroups());
    await open(t, AppView.list, g);
    expect(await openedOn(t, 'details-due-${g.key}'), day(g.dueAt!));
  });

  testWidgets('an empty start: the picker opens on the deadline', (t) async {
    t.view.physicalSize = const Size(1280, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final store = sampleCatalogue(now);
    final g = pick(store.partGroups());
    store.setPartKickoff(g.partId!, g.stageId, null);
    final h = store.partGroups().firstWhere((x) => x.key == g.key);
    expect(h.kickoffAt, isNull);
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AppShell(
          initialView: AppView.list,
          reader: SyncCatalogueReader(store),
          store: store,
          clock: () => now,
        ),
      ),
    );
    await t.pump();
    await open(t, AppView.list, h);
    expect(await openedOn(t, 'details-kickoff-${h.key}'), day(h.dueAt!));
  });

  testWidgets('nothing on either end: the picker opens on today', (t) async {
    final store = await pumpAt(t, AppView.list);
    final g = pick(store.partGroups());
    await open(t, AppView.list, g);
    expect(
      await openedOn(t, 'details-plan-start-${g.key}'),
      day(DateTime.now()),
    );
  });
}

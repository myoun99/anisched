import 'package:anisched/src/services/catalogue_reader.dart';
import 'package:anisched/src/services/catalogue_store.dart';
import 'package:anisched/src/services/database.dart';
import 'package:anisched/src/ui/shell.dart';
import 'package:anisched/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<CatalogueStore> pumpEmpty(
  WidgetTester t, {
  void Function(CatalogueStore)? onSample,
}) async {
  final store = CatalogueStore(openAppDatabase(':memory:'));
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: AppShell(
        reader: SyncCatalogueReader(store),
        store: store,
        onSample: onSample,
      ),
    ),
  );
  await t.pump();
  return store;
}

void main() {
  testWidgets('an empty document offers 등록, and the sample where given', (
    t,
  ) async {
    await pumpEmpty(t);
    expect(find.byKey(const Key('empty-register')), findsOneWidget);
    expect(find.byKey(const Key('empty-sample')), findsNothing);
    await t.tap(find.byKey(const Key('empty-register')));
    await t.pump();
    expect(find.byKey(const Key('pick-work')), findsOneWidget);
  });

  testWidgets('the sample fills the document and the list shows it', (t) async {
    await pumpEmpty(
      t,
      onSample: (s) {
        final w = s.createWork('예시 작품');
        final e = s.addEpisode(w, '1');
        final stage = s.stages(w).first.id;
        s.addTask(stage, cutId: s.addCut(e, '1'));
      },
    );
    await t.tap(find.byKey(const Key('empty-sample')));
    await t.pump();
    await t.pump();
    expect(find.byKey(const Key('empty-sample')), findsNothing);
    expect(find.textContaining('예시 작품'), findsWidgets);
  });
}

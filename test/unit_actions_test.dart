import 'package:anisched/src/controllers/unit_actions.dart';
import 'package:anisched/src/models/progress.dart';
import 'package:anisched/src/services/catalogue_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sample_catalogue.dart';

final now = DateTime(2026, 11, 27, 14);

PartGroup openPart(CatalogueStore s) => s.partGroups().firstWhere(
  (g) =>
      g.kind == GroupKind.part &&
      g.tasks.where((t) => t.status.isOpen).length > 1,
);

PartGroup again(CatalogueStore s, PartGroup g) =>
    s.partGroups(includeHandedOff: true).firstWhere((x) => x.key == g.key);

void main() {
  group('dueTargets', () {
    test('a part has one deadline; loose cuts and storyboards their own', () {
      final s = sampleCatalogue(now);
      final groups = s.partGroups();
      final part = groups.firstWhere((g) => g.kind == GroupKind.part);
      expect(dueTargets(part), [DueTarget.part(part.partId!, part.stageId)]);
      for (final g in groups.where((g) => g.kind != GroupKind.part)) {
        expect(dueTargets(g), [for (final t in g.tasks) DueTarget.task(t.id)]);
      }
    });
  });

  group('HoldPlan', () {
    test('a whole part waits as a part, so later cuts follow', () {
      final s = sampleCatalogue(now);
      final g = openPart(s);
      final plan = HoldPlan.of(s.partGroups(), g.tasks);
      expect(plan.release, isFalse);
      expect(plan.parts.single.partId, g.partId);
      expect(plan.loose, isEmpty);
      plan.apply(s, reason: 'LO', until: now);
      final after = again(s, g);
      expect(after.partWaiting, isTrue);
      expect(
        after.tasks
            .where((t) => t.status.isOpen)
            .every((t) => t.waitingFromPart),
        isTrue,
      );
      expect(after.tasks.first.waitReason, 'LO');
    });

    test('some cuts of a part wait on their own', () {
      final s = sampleCatalogue(now);
      final g = openPart(s);
      final one = g.tasks.firstWhere((t) => t.status.isOpen);
      final plan = HoldPlan.of(s.partGroups(), [one]);
      expect(plan.parts, isEmpty);
      expect(plan.loose, {one.id});
      plan.apply(s);
      final after = again(s, g);
      expect(after.partWaiting, isFalse);
      expect(after.waiting, 1);
    });

    test('when every picked open task waits, the plan releases', () {
      final s = sampleCatalogue(now);
      final g = openPart(s);
      HoldPlan.of(s.partGroups(), g.tasks).apply(s, reason: 'x');
      final held = again(s, g);
      final plan = HoldPlan.of(s.partGroups(), held.tasks);
      expect(plan.release, isTrue);
      plan.apply(s, reason: 'ignored');
      final after = again(s, g);
      expect(after.waiting, 0);
      expect(after.partWaiting, isFalse);
    });

    test('done work is never held', () {
      final s = sampleCatalogue(now);
      final done = s
          .partGroups(includeDone: true)
          .expand((g) => g.tasks)
          .where((t) => !t.status.isOpen)
          .toList();
      expect(done, isNotEmpty);
      expect(HoldPlan.of(s.partGroups(), done).isEmpty, isTrue);
    });
  });

  group('planHandOff', () {
    test('pulls what is still there; brings back when all are pulled', () {
      final s = sampleCatalogue(now);
      final g = openPart(s);
      final first = planHandOff(g.tasks);
      expect(first.back, isFalse);
      expect(first.ids, [for (final t in g.tasks) t.id]);
      s.handOff([g.tasks.first.id]);
      final mixed = planHandOff(again(s, g).tasks);
      expect(mixed.back, isFalse);
      expect(mixed.ids, isNot(contains(g.tasks.first.id)));
      s.handOff(mixed.ids);
      final all = planHandOff(again(s, g).tasks);
      expect(all.back, isTrue);
      expect(all.ids, hasLength(g.tasks.length));
    });
  });
}

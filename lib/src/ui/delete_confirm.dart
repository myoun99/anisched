import 'package:flutter/material.dart';

import '../models/catalogue.dart';
import 'format.dart';
import 'instant.dart';
import 'text/strings.dart';
import 'theme.dart';

/// Asks before deleting for good (완전 삭제): what goes — the cuts, the
/// episodes and titles left empty, the timer time on them — and that it
/// cannot be undone. True to delete.
Future<bool?> confirmDelete(BuildContext context, DeletionSummary sum) =>
    showInstantDialog<bool>(
      context: context,
      builder: (context) {
        final c = AppColors.of(context);
        final danger = Theme.of(context).colorScheme.error;
        final what = [
          S.deleteCuts.f({'n': sum.cuts}),
          if (sum.episodes > 0) S.deleteEpisodes.f({'n': sum.episodes}),
          if (sum.works > 0) S.deleteWorks.f({'n': sum.works}),
        ].join(' · ');
        return AlertDialog(
          key: const Key('delete-confirm'),
          scrollable: true,
          icon: Icon(Icons.delete_outline, color: danger),
          title: Text(S.deleteAsk.t),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [
              Text(
                what,
                key: const Key('delete-what'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if (sum.timerMinutes > 0)
                Text(
                  S.deleteTime.f({
                    't': formatWorked(Duration(minutes: sum.timerMinutes)),
                  }),
                  key: const Key('delete-time'),
                ),
              Text(S.deleteFinal.t, style: TextStyle(color: c.muted)),
            ],
          ),
          actions: [
            TextButton(
              key: const Key('delete-cancel'),
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(S.cancel.t),
            ),
            FilledButton(
              key: const Key('delete-ok'),
              style: FilledButton.styleFrom(backgroundColor: danger),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(S.deleteForever.t),
            ),
          ],
        );
      },
    );

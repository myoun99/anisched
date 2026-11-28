import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/document_files.dart';
import '../services/document_rows.dart';
import '../services/document_session.dart';
import '../services/schema.dart';
import 'instant.dart';
import 'text/strings.dart';
import 'widgets.dart';
import 'notice.dart';

/// What went wrong with a document, as the user can act on it.
enum DocumentTroubleKind {
  unreachable(Icons.cloud_off),
  empty(Icons.hourglass_empty),
  notDocument(Icons.block),
  newer(Icons.system_update),
  damaged(Icons.broken_image_outlined),
  unfinished(Icons.sync_problem),
  other(Icons.error_outline);

  const DocumentTroubleKind(this.icon);

  final IconData icon;

  String get text => switch (this) {
    unreachable => S.troubleUnreachable.t,
    empty => S.troubleEmpty.t,
    notDocument => S.troubleNotDocument.t,
    newer => S.troubleNewer.t,
    damaged => S.troubleDamaged.t,
    unfinished => S.troubleUnfinished.t,
    other => S.troubleOther.t,
  };
}

/// A document error: its kind (one line in the user's language) and the
/// error as it came (to copy and send on).
class DocumentTrouble {
  const DocumentTrouble(this.kind, this.diagnosis, {this.restorable = false});

  final DocumentTroubleKind kind;
  final String diagnosis;

  /// This device's last good write may put the file right (an empty, cut
  /// short or damaged file).
  final bool restorable;

  static DocumentTrouble of(Object error) {
    final e = error is RemoteUnreachable ? error.error : error;
    return DocumentTrouble(
      switch (e) {
        DocumentUnreachableException() ||
        RemoteMissing() => DocumentTroubleKind.unreachable,
        SchemaTooNewException() => DocumentTroubleKind.newer,
        DocumentWriteMismatchException() => DocumentTroubleKind.unfinished,
        NotADocumentException(:final kind) => switch (kind) {
          NotADocumentKind.empty => DocumentTroubleKind.empty,
          NotADocumentKind.notSqlite ||
          NotADocumentKind.foreignApp => DocumentTroubleKind.notDocument,
          NotADocumentKind.damaged ||
          NotADocumentKind.tablesDiffer ||
          NotADocumentKind.migrateFailed => DocumentTroubleKind.damaged,
        },
        _ => DocumentTroubleKind.other,
      },
      '$e',
      restorable: switch (e) {
        NotADocumentException(:final kind) => const {
          NotADocumentKind.empty,
          NotADocumentKind.notSqlite,
          NotADocumentKind.damaged,
        }.contains(kind),
        _ => false,
      },
    );
  }
}

/// What the dialog was closed with.
enum _TroubleAnswer { retry, restore }

/// Shows [error] as a small dialog: an icon and one line, 「자세히」 opens
/// the error as it came with a copy button, 「다시 시도」 runs [retry]
/// (when given) after closing, and — for a file an interrupted save left
/// empty or broken — 「이 기기의 마지막 저장본으로 복구」 runs [restore]
/// (false: this device has no copy, said in a snackbar).
Future<void> showDocumentTrouble(
  BuildContext context,
  Object error, {
  Future<void> Function()? retry,
  Future<bool> Function()? restore,
}) async {
  final trouble = DocumentTrouble.of(error);
  final answer = await showInstantDialog<_TroubleAnswer>(
    context: context,
    builder: (_) => DocumentTroubleDialog(
      trouble: trouble,
      canRetry: retry != null,
      canRestore: restore != null && trouble.restorable,
    ),
  );
  switch (answer) {
    case _TroubleAnswer.retry:
      await retry?.call();
    case _TroubleAnswer.restore:
      if (await restore!() || !context.mounted) return;
      showNotice(
        context,
        S.troubleNoCopy.t,
        key: const Key('doc-restore-none'),
      );
    case null:
      break;
  }
}

class DocumentTroubleDialog extends StatefulWidget {
  const DocumentTroubleDialog({
    super.key,
    required this.trouble,
    this.canRetry = false,
    this.canRestore = false,
  });

  final DocumentTrouble trouble;
  final bool canRetry;
  final bool canRestore;

  @override
  State<DocumentTroubleDialog> createState() => _DocumentTroubleDialogState();
}

class _DocumentTroubleDialogState extends State<DocumentTroubleDialog> {
  bool _open = false;
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.trouble;
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      key: const Key('doc-trouble'),
      title: DialogTitle(
        t.kind.icon,
        t.kind.text,
        key: const Key('doc-trouble-text'),
        color: scheme.error,
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            TextButton.icon(
              key: const Key('doc-trouble-details'),
              onPressed: () => setState(() => _open = !_open),
              icon: Icon(_open ? Icons.expand_less : Icons.expand_more),
              label: Text(S.troubleDetails.t),
            ),
            if (_open)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: SelectableText(
                          t.diagnosis,
                          key: const Key('doc-trouble-diagnosis'),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      IconButton(
                        key: const Key('doc-trouble-copy'),
                        tooltip: _copied ? S.troubleCopied.t : S.troubleCopy.t,
                        icon: Icon(
                          _copied ? Icons.check : Icons.copy,
                          size: 18,
                        ),
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: t.diagnosis),
                          );
                          if (mounted) setState(() => _copied = true);
                        },
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        if (widget.canRestore)
          TextButton.icon(
            key: const Key('doc-trouble-restore'),
            onPressed: () => Navigator.pop(context, _TroubleAnswer.restore),
            icon: const Icon(Icons.settings_backup_restore, size: 18),
            label: Text(S.troubleRestore.t),
          ),
        if (widget.canRetry)
          TextButton(
            key: const Key('doc-trouble-retry'),
            onPressed: () => Navigator.pop(context, _TroubleAnswer.retry),
            child: Text(S.troubleRetry.t),
          ),
        FilledButton(
          key: const Key('doc-trouble-ok'),
          onPressed: () => Navigator.pop(context),
          child: Text(S.ok.t),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/document_files.dart';
import '../services/document_rows.dart';
import '../services/document_session.dart';
import '../services/schema.dart';
import 'instant.dart';
import 'text/strings.dart';

/// What went wrong with a document, as the user can act on it.
enum DocumentTroubleKind {
  unreachable(Icons.cloud_off),
  empty(Icons.hourglass_empty),
  notDocument(Icons.block),
  newer(Icons.system_update),
  damaged(Icons.broken_image_outlined),
  other(Icons.error_outline);

  const DocumentTroubleKind(this.icon);

  final IconData icon;

  String get text => switch (this) {
    unreachable => S.troubleUnreachable.t,
    empty => S.troubleEmpty.t,
    notDocument => S.troubleNotDocument.t,
    newer => S.troubleNewer.t,
    damaged => S.troubleDamaged.t,
    other => S.troubleOther.t,
  };
}

/// A document error: its kind (one line in the user's language) and the
/// error as it came (to copy and send on).
class DocumentTrouble {
  const DocumentTrouble(this.kind, this.diagnosis);

  final DocumentTroubleKind kind;
  final String diagnosis;

  static DocumentTrouble of(Object error) {
    final e = error is RemoteUnreachable ? error.error : error;
    return DocumentTrouble(switch (e) {
      DocumentUnreachableException() ||
      RemoteMissing() => DocumentTroubleKind.unreachable,
      SchemaTooNewException() => DocumentTroubleKind.newer,
      NotADocumentException() => DocumentTroubleKind.notDocument,
      _ => DocumentTroubleKind.other,
    }, '$e');
  }
}

/// Shows [error] as a small dialog: an icon and one line, 「자세히」 opens
/// the error as it came with a copy button, and 「다시 시도」 runs [retry]
/// (when given) after closing.
Future<void> showDocumentTrouble(
  BuildContext context,
  Object error, {
  Future<void> Function()? retry,
}) async {
  final again = await showInstantDialog<bool>(
    context: context,
    builder: (_) => DocumentTroubleDialog(
      trouble: DocumentTrouble.of(error),
      canRetry: retry != null,
    ),
  );
  if (again == true) await retry?.call();
}

class DocumentTroubleDialog extends StatefulWidget {
  const DocumentTroubleDialog({
    super.key,
    required this.trouble,
    this.canRetry = false,
  });

  final DocumentTrouble trouble;
  final bool canRetry;

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
      icon: Icon(t.kind.icon, color: scheme.error),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            Text(t.kind.text, key: const Key('doc-trouble-text')),
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
        if (widget.canRetry)
          TextButton(
            key: const Key('doc-trouble-retry'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(S.troubleRetry.t),
          ),
        FilledButton(
          key: const Key('doc-trouble-ok'),
          onPressed: () => Navigator.pop(context, false),
          child: Text(S.ok.t),
        ),
      ],
    );
  }
}

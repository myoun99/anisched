import 'dart:async';

import 'package:flutter/material.dart';

import 'instant.dart';

import '../models/document.dart';
import '../platform/documents.dart';
import '../services/document_session.dart';
import 'pick_field.dart';
import 'theme.dart';

/// Where the user picks a document to open, and where Save As puts it.
abstract interface class DocumentPicker {
  Future<DocumentRef?> pickOpen(BuildContext context);

  /// Saves [session]'s document under a new place; false if backed out.
  Future<bool> saveAs(
    BuildContext context,
    DocumentSession session,
    String suggestedName,
  );
}

/// The platform's own pickers (file dialogs on desktop, the document
/// picker on iOS and macOS, SAF on Android).
class PlatformPicker implements DocumentPicker {
  const PlatformPicker();

  @override
  Future<DocumentRef?> pickOpen(BuildContext context) => pickDocument();

  @override
  Future<bool> saveAs(
    BuildContext context,
    DocumentSession session,
    String suggestedName,
  ) => session.saveAsPlaced(placeNewDocument, name: suggestedName);
}

/// Test stand-in: a typed file path.
class PathPromptPicker implements DocumentPicker {
  const PathPromptPicker();

  static DocumentRef? _ref(String? path) {
    final p = path?.trim() ?? '';
    if (p.isEmpty) return null;
    final full = p.endsWith('.anisched') ? p : '$p.anisched';
    final name = full.split(RegExp(r'[/\\]')).last;
    return DocumentRef(location: full, name: name);
  }

  @override
  Future<DocumentRef?> pickOpen(BuildContext context) async =>
      _ref(await askName(context, title: '열기'));

  @override
  Future<bool> saveAs(
    BuildContext context,
    DocumentSession session,
    String suggestedName,
  ) async {
    final ref = _ref(
      await askName(context, title: '저장', initial: suggestedName),
    );
    if (ref == null) return false;
    await session.saveAs(ref);
    return true;
  }
}

/// The document's name in the top bar (「무제」 before it is saved
/// somewhere), a small save-state icon in a fixed slot, and the file
/// menu: 새로 · 열기 · 다른 이름으로 저장 · recent files.
class DocumentMenu extends StatelessWidget {
  const DocumentMenu({
    super.key,
    required this.session,
    required this.picker,
    this.remote,
  });

  final DocumentSession session;
  final DocumentPicker picker;

  /// The last [DocumentSession.resume] answer, for the state icon.
  final RemoteCheck? remote;

  static String displayName(DocumentRef? ref) {
    if (ref == null) return '무제';
    final n = ref.name;
    return n.endsWith('.anisched') ? n.substring(0, n.length - 9) : n;
  }

  Future<void> _run(BuildContext context, Future<void> Function() job) async {
    try {
      await job();
    } on Object catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _saveAs(BuildContext context) => _run(
    context,
    () => picker.saveAs(
      context,
      session,
      '${displayName(session.document)}.anisched',
    ),
  );

  Future<void> _open(BuildContext context, DocumentRef? known) async {
    final ref = known ?? await picker.pickOpen(context);
    if (ref == null || !context.mounted) return;
    await _run(context, () => session.openDocument(ref));
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final doc = session.document;
    final recents = [
      for (final r in session.recents)
        if (r.ref.location != doc?.location) r.ref,
    ];
    return PopupMenuButton<void Function()>(
      key: const Key('file-menu'),
      tooltip: '',
      popUpAnimationStyle: instant,
      onSelected: (f) => f(),
      itemBuilder: (_) => [
        PopupMenuItem(
          key: const Key('file-new'),
          value: () => unawaited(_run(context, session.startUntitled)),
          child: const Text('새로'),
        ),
        PopupMenuItem(
          key: const Key('file-open'),
          value: () => unawaited(_open(context, null)),
          child: const Text('열기'),
        ),
        PopupMenuItem(
          key: const Key('file-save-as'),
          value: () => unawaited(_saveAs(context)),
          child: Text(doc == null ? '저장' : '다른 이름으로 저장'),
        ),
        if (recents.isNotEmpty) const PopupMenuDivider(),
        for (final r in recents)
          PopupMenuItem(
            value: () => unawaited(_open(context, r)),
            child: Text(displayName(r)),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Text(
                displayName(doc),
                key: const Key('file-name'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: doc == null ? c.muted : null),
              ),
            ),
            SizedBox(width: 18, child: _stateIcon(context)),
          ],
        ),
      ),
    );
  }

  /// One icon in a reserved slot: saved, waiting to save, not saved
  /// anywhere yet, or a problem (red).
  Widget _stateIcon(BuildContext context) {
    final c = AppColors.of(context);
    final red = Theme.of(context).colorScheme.error;
    final err = session.lastSaveError;
    final (icon, color, tip) = switch (remote) {
      _ when err != null => (Icons.error_outline, red, '$err'),
      RemoteMissing() => (Icons.error_outline, red, '파일 없음'),
      RemoteUnreachable(:final error) => (Icons.cloud_off, red, '$error'),
      _ when session.document == null => (Icons.cloud_off, c.faint, ''),
      _ when session.dirty => (Icons.cloud_upload_outlined, c.muted, ''),
      _ => (Icons.cloud_done_outlined, c.muted, ''),
    };
    final i = Icon(icon, key: const Key('file-state'), size: 16, color: color);
    return tip.isEmpty ? i : Tooltip(message: tip, child: i);
  }
}

import 'dart:async';

import 'package:flutter/material.dart';

import 'instant.dart';

import '../models/document.dart';
import '../platform/documents.dart';
import '../services/document_session.dart';
import 'pick_field.dart';
import 'theme.dart';
import 'text/strings.dart';

/// Where the user picks a document to open, and where Save As puts it.
abstract interface class DocumentPicker {
  Future<DocumentRef?> pickOpen(BuildContext context);

  /// Saves [session]'s document under a new place; false if backed out.
  Future<bool> saveAs(
    BuildContext context,
    DocumentSessionBase session,
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
    DocumentSessionBase session,
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
      _ref(await askName(context, title: S.fileOpen.t));

  @override
  Future<bool> saveAs(
    BuildContext context,
    DocumentSessionBase session,
    String suggestedName,
  ) async {
    final ref = _ref(
      await askName(context, title: S.fileSave.t, initial: suggestedName),
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

  final DocumentSessionBase session;
  final DocumentPicker picker;

  /// The last [DocumentSession.resume] answer, for the state icon.
  final RemoteCheck? remote;

  static String displayName(DocumentRef? ref) {
    if (ref == null) return S.untitled.t;
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
          child: _MenuLine(icon: Icons.note_add_outlined, label: S.fileNew.t),
        ),
        PopupMenuItem(
          key: const Key('file-open'),
          value: () => unawaited(_open(context, null)),
          child: _MenuLine(
            icon: Icons.folder_open_outlined,
            label: S.fileOpen.t,
          ),
        ),
        PopupMenuItem(
          key: const Key('file-save-as'),
          value: () => unawaited(_saveAs(context)),
          child: _MenuLine(
            icon: doc == null ? Icons.save_outlined : Icons.save_as_outlined,
            label: doc == null ? S.fileSave.t : S.fileSaveAs.t,
          ),
        ),
        if (recents.isNotEmpty) const PopupMenuDivider(),
        for (final r in recents)
          PopupMenuItem(
            value: () => unawaited(_open(context, r)),
            child: _MenuLine(icon: Icons.history, label: displayName(r)),
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
    final st = SaveState.of(context, session, remote);
    final i = Icon(
      st.icon,
      key: const Key('file-state'),
      size: 16,
      color: st.color,
    );
    return Tooltip(message: st.detail ?? st.word, child: i);
  }
}

/// Where the document stands, as one icon and one word (and the error,
/// when there is one).
class SaveState {
  const SaveState(this.icon, this.color, this.word, [this.detail]);

  final IconData icon;
  final Color color;
  final String word;
  final String? detail;

  static SaveState of(
    BuildContext context,
    DocumentSessionBase session,
    RemoteCheck? remote,
  ) {
    final c = AppColors.of(context);
    final red = Theme.of(context).colorScheme.error;
    final err = session.lastSaveError;
    return switch (remote) {
      _ when err != null => SaveState(
        Icons.error_outline,
        red,
        S.notSaved.t,
        '$err',
      ),
      RemoteMissing() => SaveState(Icons.error_outline, red, S.fileMissing.t),
      RemoteUnreachable(:final error) => SaveState(
        Icons.cloud_off,
        red,
        S.notSaved.t,
        '$error',
      ),
      _ when session.document == null => SaveState(
        Icons.cloud_off,
        c.faint,
        S.notSaved.t,
      ),
      _ when session.dirty => SaveState(
        Icons.cloud_upload_outlined,
        c.muted,
        S.saving.t,
      ),
      _ => SaveState(Icons.cloud_done_outlined, c.muted, S.saved.t),
    };
  }
}

/// A file menu line: an icon, then its word.
class _MenuLine extends StatelessWidget {
  const _MenuLine({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    spacing: 10,
    children: [
      Icon(icon, size: 18, color: AppColors.of(context).muted),
      Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
    ],
  );
}

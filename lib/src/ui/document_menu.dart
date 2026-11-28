import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable, kIsWeb;
import 'package:flutter/material.dart';

import 'instant.dart';

import '../models/document.dart';
import '../platform/documents.dart';
import '../services/document_session.dart';
import 'document_trouble.dart';
import 'pick_field.dart';
import 'theme.dart';
import 'widgets.dart';
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

/// A name typed for Save As, as the file is to be called (before its
/// extension): trimmed, a typed 「.anisched」 taken off.
String saveAsName(String typed) => documentDisplayName(typed.trim()).trim();

/// The document's name in the top bar (「무제」 before it is saved
/// somewhere), a small save-state icon in a fixed slot, and the file
/// menu: 새로 · 열기 · 다른 이름으로 저장 · recent files.
class DocumentMenu extends StatelessWidget {
  const DocumentMenu({
    super.key,
    required this.session,
    required this.picker,
    this.remote,
    this.recheck,
    this.browser = kIsWeb,
  });

  /// Checks the file again (a red state icon's 「다시 시도」).
  final Future<void> Function()? recheck;

  /// In a browser the document lives in the page: saving is exporting a
  /// file, opening is bringing one in (the words say so).
  final bool browser;

  final DocumentSessionBase session;
  final DocumentPicker picker;

  /// The last [DocumentSession.resume] answer, for the state icon.
  final RemoteCheck? remote;

  static String displayName(DocumentRef? ref) =>
      ref == null ? S.untitled.t : documentDisplayName(ref.name);

  /// Runs [job]; a failure shows its dialog, which can try again or put
  /// [ref] back from this device's last save.
  Future<void> _run(
    BuildContext context,
    Future<void> Function() job, {
    DocumentRef? ref,
  }) async {
    try {
      await job();
    } on Object catch (e) {
      if (!context.mounted) return;
      await showDocumentTrouble(
        context,
        e,
        retry: () => _run(context, job, ref: ref),
        // Offered only when this device holds a copy to put back.
        restore: ref == null || !session.hasLastWritten(ref)
            ? null
            : () => session.restoreLastWritten(ref),
      );
    }
  }

  /// 「다른 이름으로 저장」: the name first, in the app's own small window
  /// (the name alone; 「.anisched」 shown faint, never typed), then the
  /// platform's place.
  Future<void> _saveAs(BuildContext context) async {
    final typed = await askName(
      context,
      title: S.fileSave.t,
      initial: displayName(session.document),
      suffix: '.$documentExtension',
      icon: Icons.save_as_outlined,
    );
    final name = typed == null ? '' : saveAsName(typed);
    if (name.isEmpty || !context.mounted) return;
    await _run(
      context,
      () => picker.saveAs(context, session, withDocumentExtension(name)),
    );
  }

  Future<void> _open(BuildContext context, DocumentRef? known) async {
    final ref = known ?? await picker.pickOpen(context);
    if (ref == null || !context.mounted) return;
    await _run(context, () => session.openDocument(ref), ref: ref);
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
          child: MenuLine(icon: Icons.note_add_outlined, label: S.fileNew.t),
        ),
        PopupMenuItem(
          key: const Key('file-open'),
          value: () => unawaited(_open(context, null)),
          child: MenuLine(
            icon: browser
                ? Icons.upload_file_outlined
                : Icons.folder_open_outlined,
            label: browser ? S.fileImport.t : S.fileOpen.t,
          ),
        ),
        PopupMenuItem(
          key: const Key('file-save-as'),
          value: () => unawaited(_saveAs(context)),
          child: browser
              ? MenuLine(icon: Icons.download_outlined, label: S.fileExport.t)
              : MenuLine(
                  icon: doc == null
                      ? Icons.save_outlined
                      : Icons.save_as_outlined,
                  label: doc == null ? S.fileSave.t : S.fileSaveAs.t,
                ),
        ),
        if (recents.isNotEmpty) const PopupMenuDivider(),
        for (final r in recents)
          PopupMenuItem(
            value: () => unawaited(_open(context, r)),
            child: MenuLine(icon: Icons.history, label: displayName(r)),
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
    final tip = Tooltip(message: st.detail ?? st.word, child: i);
    if (st.error == null) return tip;
    return GestureDetector(
      key: const Key('file-trouble'),
      behavior: HitTestBehavior.opaque,
      onTap: () => st.show(context, session, recheck),
      child: tip,
    );
  }
}

/// Where the document stands, as one icon and one word (and the error,
/// when there is one: one line in the user's language, the whole of it in
/// [show]).
class SaveState {
  const SaveState(
    this.icon,
    this.color,
    this.word, [
    this.error,
    this.fromSave = false,
  ]);

  final IconData icon;
  final Color color;
  final String word;
  final Object? error;

  /// The error came from saving (trying again saves).
  final bool fromSave;

  String? get detail => switch (error) {
    final e? => DocumentTrouble.of(e).kind.text,
    null => null,
  };

  /// The error's dialog; 「다시 시도」 saves again, or checks the file
  /// again through [recheck].
  Future<void> show(
    BuildContext context,
    DocumentSessionBase session,
    Future<void> Function()? recheck,
  ) => showDocumentTrouble(
    context,
    error!,
    retry: fromSave ? session.save : recheck,
    restore: switch (session.document) {
      final ref? when session.hasLastWritten(ref) =>
        () => session.restoreLastWritten(ref),
      _ => null,
    },
  );

  /// Checks the document again and hands the answer to [remote] (when it
  /// can be set).
  static Future<void> Function()? recheckOf(
    DocumentSessionBase session,
    ValueListenable<RemoteCheck?>? remote,
  ) => switch (remote) {
    final ValueNotifier<RemoteCheck?> n =>
      () async => n.value = await session.resume(),
    _ => null,
  };

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
        err,
        true,
      ),
      RemoteMissing() => SaveState(Icons.error_outline, red, S.fileMissing.t),
      RemoteUnreachable(:final error) => SaveState(
        Icons.cloud_off,
        red,
        S.notSaved.t,
        error,
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

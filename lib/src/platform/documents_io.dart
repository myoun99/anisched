import 'dart:io';

import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/document.dart';
import '../services/document_files.dart';
import '../services/document_session.dart';

/// The platform half of the document file (docs/storage.md): the runner's
/// `anisched/documents` channel on iOS, macOS and Android, the
/// file_selector dialogs and real paths on Windows and Linux.
///
/// One answer shape for every method, from every runner:
/// `{status: granted | cancelled | missing | unavailable, location?, name?,
/// bookmark?, size?, modifiedMs?, message?}`.
const MethodChannel documentsChannel = MethodChannel('anisched/documents');

/// Whether this platform reaches documents through the runner's channel.
bool get documentsUseChannel =>
    Platform.isIOS || Platform.isMacOS || Platform.isAndroid;

/// The [DocumentFiles] for this platform.
DocumentFiles platformDocumentFiles() => documentsUseChannel
    ? const ChannelDocumentFiles()
    : const PathDocumentFiles();

/// Asks the user for a document to open; null when they backed out.
Future<DocumentRef?> pickDocument() async {
  if (documentsUseChannel) {
    final answer = await _call('pick', const {});
    return answer.status == 'cancelled' ? null : answer.ref(null);
  }
  final file = await file_selector.openFile(acceptedTypeGroups: [_group]);
  if (file == null) return null;
  return DocumentRef(location: file.path, name: _baseName(file.path));
}

/// The placer for [DocumentSession.saveAsPlaced] on this platform: asks
/// where, puts the staged document there, answers the place.
Future<DocumentRef?> placeNewDocument(
  String stagedPath,
  String fileName,
) async {
  if (documentsUseChannel) {
    final answer = await _call('saveAs', {
      'sourcePath': stagedPath,
      'name': fileName,
    });
    return answer.status == 'cancelled' ? null : answer.ref(null);
  }
  final where = await file_selector.getSaveLocation(
    acceptedTypeGroups: [_group],
    suggestedName: fileName,
  );
  if (where == null) return null;
  var path = where.path;
  if (!path.toLowerCase().endsWith('.$documentExtension')) {
    path = '$path.$documentExtension';
  }
  final ref = DocumentRef(location: path, name: _baseName(path));
  await const PathDocumentFiles().replaceFrom(stagedPath, ref);
  return ref;
}

const _group = file_selector.XTypeGroup(
  label: 'Anisched',
  extensions: [documentExtension],
  uniformTypeIdentifiers: ['com.myoun.anisched.document'],
);

String _baseName(String path) => path.split(RegExp(r'[/\\]')).last;

/// [DocumentFiles] through the runner (Apple: security-scoped bookmarks and
/// NSFileCoordinator; Android: SAF URIs with a persistable permission).
class ChannelDocumentFiles implements DocumentFiles {
  const ChannelDocumentFiles();

  /// Apple: a coordinated `.forReplacing` swap. Android: a SAF stream
  /// over the one granted document — not atomic.
  @override
  bool get replacesAtomically => !Platform.isAndroid;

  @override
  Future<DocumentRef> reopen(DocumentRef ref) async {
    final answer = await _call('reopen', {
      'location': ref.location,
      'bookmark': ref.bookmark,
    });
    return answer.ref(ref);
  }

  @override
  Future<DocumentStat?> stat(DocumentRef ref) async {
    final answer = await _call('stat', {'location': ref.location});
    if (answer.status == 'missing') return null;
    answer.ref(ref); // throws unless granted
    final size = answer.map['size'];
    final modified = answer.map['modifiedMs'];
    if (size is! int) {
      throw DocumentUnreachableException(ref, 'no size');
    }
    return (size: size, modifiedMs: modified is int ? modified : null);
  }

  @override
  Future<void> readInto(DocumentRef ref, String localPath) async {
    (await _call('readInto', {
      'location': ref.location,
      'destinationPath': localPath,
    })).ref(ref);
  }

  @override
  Future<void> replaceFrom(String localPath, DocumentRef ref) async {
    (await _call('replaceFrom', {
      'location': ref.location,
      'sourcePath': localPath,
    })).ref(ref);
  }
}

@visibleForTesting
class ChannelAnswer {
  ChannelAnswer(this.map);

  final Map<Object?, Object?> map;

  String get status => map['status'] as String? ?? 'unavailable';

  /// The ref the answer names (falling back to [known]'s fields); throws
  /// [DocumentUnreachableException] unless granted.
  DocumentRef ref(DocumentRef? known) {
    final location = map['location'] as String? ?? known?.location;
    if (status != 'granted' || location == null) {
      throw DocumentUnreachableException(
        known ?? DocumentRef(location: location ?? '', name: ''),
        map['message'] ?? status,
      );
    }
    return DocumentRef(
      location: location,
      name: map['name'] as String? ?? known?.name ?? _baseName(location),
      bookmark: map.containsKey('bookmark')
          ? map['bookmark'] as String?
          : known?.bookmark,
    );
  }
}

Future<ChannelAnswer> _call(String method, Map<String, Object?> args) async {
  try {
    final answer = await documentsChannel.invokeMethod<Map<Object?, Object?>>(
      method,
      args,
    );
    return ChannelAnswer(answer ?? const {'status': 'unavailable'});
  } on PlatformException catch (e) {
    return ChannelAnswer({'status': 'unavailable', 'message': e.message});
  } on MissingPluginException {
    return ChannelAnswer(const {
      'status': 'unavailable',
      'message': 'no documents channel in this build',
    });
  }
}

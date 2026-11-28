/// The `.anisched` document: one file the user keeps wherever they like
/// (a local folder, iCloud Drive, Google Drive …) and opens from any device.
///
/// See docs/storage.md. The app never works on the document in place: the
/// working database lives in the app container, and the document is written
/// whole and read whole.
library;

/// File extension of a document, without the dot.
const String documentExtension = 'anisched';

/// SQLite `application_id` stamped on every document the app writes
/// ('ANSC'), so a stray SQLite file is refused instead of imported.
const int documentApplicationId = 0x414E5343;

/// Where a document lives.
///
/// [location] is a filesystem path on Windows/Linux (and on Apple, resolved
/// from [bookmark]), or a `content://` URI on Android. [bookmark] is the
/// platform token that reopens the location after a relaunch (Apple
/// security-scoped bookmark, base64); null where a path simply works or the
/// grant is held by the OS (Android persistable URI permission).
class DocumentRef {
  const DocumentRef({
    required this.location,
    required this.name,
    this.bookmark,
  });

  final String location;

  /// Display name (the file name the user sees), as the platform gave it.
  final String name;

  final String? bookmark;

  Map<String, Object?> toJson() => {
    'location': location,
    'name': name,
    if (bookmark != null) 'bookmark': bookmark,
  };

  static DocumentRef? fromJson(Object? json) {
    if (json is! Map) return null;
    final location = json['location'];
    final name = json['name'];
    if (location is! String || name is! String) return null;
    final bookmark = json['bookmark'];
    return DocumentRef(
      location: location,
      name: name,
      bookmark: bookmark is String ? bookmark : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DocumentRef && other.location == location;

  @override
  int get hashCode => location.hashCode;

  @override
  String toString() => 'DocumentRef($location)';
}

/// What the platform says about a document without reading it.
typedef DocumentStat = ({int size, int? modifiedMs});

/// The document as this device last wrote or read it — the answer to
/// "did another device change the file since?".
///
/// [size] and [modifiedMs] are the cheap check; [hash] (FNV-1a 64 over the
/// bytes) settles it when they differ, because a sync client can touch the
/// time or re-download identical bytes.
class DocumentFingerprint {
  const DocumentFingerprint({
    required this.size,
    required this.hash,
    this.modifiedMs,
  });

  final int size;
  final int? modifiedMs;
  final int hash;

  /// Whether [stat] certainly shows the same file, without reading it.
  /// A missing modification time never proves sameness.
  bool sameStat(DocumentStat stat) =>
      stat.size == size && modifiedMs != null && stat.modifiedMs == modifiedMs;

  DocumentFingerprint withModified(int? modifiedMs) =>
      DocumentFingerprint(size: size, hash: hash, modifiedMs: modifiedMs);

  Map<String, Object?> toJson() => {
    'size': size,
    'hash': hash,
    if (modifiedMs != null) 'modifiedMs': modifiedMs,
  };

  static DocumentFingerprint? fromJson(Object? json) {
    if (json is! Map) return null;
    final size = json['size'];
    final hash = json['hash'];
    if (size is! int || hash is! int) return null;
    final modified = json['modifiedMs'];
    return DocumentFingerprint(
      size: size,
      hash: hash,
      modifiedMs: modified is int ? modified : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DocumentFingerprint &&
      other.size == size &&
      other.hash == hash &&
      other.modifiedMs == modifiedMs;

  @override
  int get hashCode => Object.hash(size, hash, modifiedMs);
}

/// One row of the recent-files list.
typedef RecentDocument = ({DocumentRef ref, DateTime openedAt});

/// How many recent documents are remembered.
const int maxRecentDocuments = 10;

/// [recents] with [ref] moved to the front at [at], trimmed to
/// [maxRecentDocuments]. A newer bookmark for the same location wins.
List<RecentDocument> touchRecent(
  List<RecentDocument> recents,
  DocumentRef ref,
  DateTime at,
) => [
  (ref: ref, openedAt: at),
  for (final r in recents)
    if (r.ref != ref) r,
].take(maxRecentDocuments).toList();

/// FNV-1a 64-bit over [bytes], continuing from [hash] (default: the seed).
/// Devices only — the web build's integers are 53-bit, and it never
/// fingerprints a document.
int fnv1a64(List<int> bytes, [int? hash]) {
  var h = hash ?? fnv1a64Seed;
  for (final b in bytes) {
    h ^= b;
    h *= 0x100000001b3; // wraps modulo 2^64 on the VM
  }
  return h;
}

/// The FNV-1a 64-bit offset basis, 0xcbf29ce484222325 (parsed at run time:
/// a 64-bit literal does not compile for the web).
final int fnv1a64Seed = int.parse('-3750763034362895579');

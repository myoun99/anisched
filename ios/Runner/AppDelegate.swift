import Flutter
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let documents = Documents()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AnischedDocuments")
    else { return }
    let channel = FlutterMethodChannel(
      name: "anisched/documents", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { [documents] call, result in
      documents.handle(call, result: result)
    }
  }
}

/// The `anisched/documents` channel (docs/storage.md), iOS half.
///
/// Every answer is `{status, location?, name?, bookmark?, size?,
/// modifiedMs?, message?}`. Reads and writes go through NSFileCoordinator —
/// the only way a File Provider (iCloud Drive, Google Drive …) is asked for
/// its current version and told about a new one. Ported from Anicel's
/// `qa_storage` runner (UNVERIFIED ON DEVICE here as there).
///
/// Kept in this file: the Xcode project lists its sources explicitly, so a
/// new .swift file would not be compiled without a project edit.
final class Documents: NSObject, UIDocumentPickerDelegate {
  /// Items whose security scope this run holds, by path. Holding the URL
  /// keeps the scope alive for the process.
  private var scoped: [String: URL] = [:]
  private var pending: FlutterResult?

  private static let type: UTType =
    UTType("com.myoun.anisched.document") ?? UTType(filenameExtension: "anisched") ?? .data

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    let location = args["location"] as? String
    switch call.method {
    case "pick":
      let picker = UIDocumentPickerViewController(
        forOpeningContentTypes: [Documents.type], asCopy: false)
      present(picker, result: result)
    case "saveAs":
      guard let source = args["sourcePath"] as? String else {
        return result(Documents.unavailable("no source"))
      }
      // iOS has no save panel: the finished file is MOVED to where the
      // user puts it, and the answer says where that was.
      let picker = UIDocumentPickerViewController(
        forExporting: [URL(fileURLWithPath: source)], asCopy: false)
      present(picker, result: result)
    case "reopen":
      reopen(location: location, bookmark: args["bookmark"] as? String, result: result)
    case "stat":
      guard let url = url(for: location) else { return result(Documents.unavailable("no location")) }
      Documents.background(result) { DocumentIO.stat(url) }
    case "readInto":
      guard let url = url(for: location), let dest = args["destinationPath"] as? String else {
        return result(Documents.unavailable("bad arguments"))
      }
      Documents.background(result) {
        try DocumentIO.read(url, into: URL(fileURLWithPath: dest))
        return ["status": "granted"]
      }
    case "replaceFrom":
      guard let url = url(for: location), let source = args["sourcePath"] as? String else {
        return result(Documents.unavailable("bad arguments"))
      }
      Documents.background(result) {
        try DocumentIO.replace(url, from: URL(fileURLWithPath: source))
        return ["status": "granted"]
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func url(for location: String?) -> URL? {
    guard let location else { return nil }
    return scoped[location] ?? URL(fileURLWithPath: location)
  }

  private func reopen(location: String?, bookmark: String?, result: FlutterResult) {
    if let location, scoped[location] != nil {
      return result(["status": "granted", "location": location, "bookmark": bookmark as Any])
    }
    guard let bookmark, let data = Data(base64Encoded: bookmark) else {
      // A path inside the app container needs no grant.
      return result(["status": "granted"])
    }
    var stale = false
    do {
      let url = try URL(
        resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
      result(grant(url, requiringScope: true))
    } catch {
      result(Documents.unavailable(error.localizedDescription))
    }
  }

  /// Opens the item's scope, keeps it, and mints a fresh bookmark.
  private func grant(_ url: URL, requiringScope: Bool = false) -> [String: Any] {
    let opened = url.startAccessingSecurityScopedResource()
    if requiringScope && !opened {
      return Documents.unavailable("the grant is gone")
    }
    scoped[url.path] = url
    let bookmark = try? url.bookmarkData(
      options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil
    ).base64EncodedString()
    return [
      "status": "granted", "location": url.path, "name": url.lastPathComponent,
      "bookmark": bookmark as Any,
    ]
  }

  // MARK: picker

  private func present(_ picker: UIDocumentPickerViewController, result: @escaping FlutterResult) {
    // One picker at a time: replacing the waiter would orphan the first.
    if pending != nil { return result(["status": "cancelled"]) }
    pending = result
    picker.delegate = self
    picker.allowsMultipleSelection = false
    guard let presenter = Documents.topViewController() else {
      return finish(Documents.unavailable("nothing to present on"))
    }
    presenter.present(picker, animated: true) { [weak self, weak picker] in
      // A presentation that never took must answer, not hang.
      guard let self, picker?.presentingViewController == nil else { return }
      self.finish(Documents.unavailable("the picker did not appear"))
    }
  }

  private func finish(_ payload: [String: Any]) {
    let waiting = pending
    pending = nil
    waiting?(payload)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let url = urls.first else { return finish(["status": "cancelled"]) }
    finish(grant(url))
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finish(["status": "cancelled"])
  }

  private static func topViewController() -> UIViewController? {
    var root: UIViewController?
    for scene in UIApplication.shared.connectedScenes {
      guard let windowScene = scene as? UIWindowScene else { continue }
      for window in windowScene.windows where window.isKeyWindow {
        root = window.rootViewController
      }
    }
    while let presented = root?.presentedViewController { root = presented }
    return root
  }

  // MARK: helpers

  static func unavailable(_ message: String) -> [String: Any] {
    ["status": "unavailable", "message": message]
  }

  /// Runs [work] off the main thread (coordination blocks until a provider
  /// yields) and answers on the main thread.
  static func background(_ result: @escaping FlutterResult, _ work: @escaping () throws -> [String: Any]) {
    DispatchQueue.global(qos: .userInitiated).async {
      let answer: [String: Any]
      do { answer = try work() } catch { answer = unavailable(error.localizedDescription) }
      DispatchQueue.main.async { result(answer) }
    }
  }
}

/// Coordinated whole-file reads and writes, shared in shape with macOS.
enum DocumentIO {
  /// Size and modification time; `missing` when there is no such item.
  static func stat(_ url: URL) -> [String: Any] {
    var answer: [String: Any] = Documents.unavailable("not read")
    var failure: NSError?
    NSFileCoordinator(filePresenter: nil).coordinate(
      readingItemAt: url, options: .immediatelyAvailableMetadataOnly, error: &failure
    ) { item in
      do {
        let values = try item.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        var map: [String: Any] = ["status": "granted", "size": values.fileSize ?? 0]
        if let date = values.contentModificationDate {
          map["modifiedMs"] = Int64((date.timeIntervalSince1970 * 1000).rounded())
        }
        answer = map
      } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
        answer = ["status": "missing"]
      } catch {
        answer = Documents.unavailable(error.localizedDescription)
      }
    }
    if let failure {
      if failure.domain == NSCocoaErrorDomain && failure.code == NSFileReadNoSuchFileError {
        return ["status": "missing"]
      }
      return Documents.unavailable(failure.localizedDescription)
    }
    return answer
  }

  /// Copies the item's CURRENT content to [destination]. The coordinated
  /// read is what makes a provider download it first.
  static func read(_ url: URL, into destination: URL) throws {
    var failure: NSError?
    var copyError: Error?
    NSFileCoordinator(filePresenter: nil).coordinate(
      readingItemAt: url, options: .withoutChanges, error: &failure
    ) { item in
      do {
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: item, to: destination)
      } catch {
        copyError = error
      }
    }
    if let error = failure ?? (copyError as NSError?) { throw error }
  }

  /// Replaces the item with [source] whole: source MOVING, destination
  /// REPLACING — "the same item, new content" to a provider.
  static func replace(_ url: URL, from source: URL) throws {
    var failure: NSError?
    var writeError: Error?
    NSFileCoordinator(filePresenter: nil).coordinate(
      writingItemAt: source, options: .forMoving,
      writingItemAt: url, options: .forReplacing,
      error: &failure
    ) { from, to in
      do {
        if FileManager.default.fileExists(atPath: to.path) {
          _ = try FileManager.default.replaceItemAt(to, withItemAt: from)
        } else {
          try FileManager.default.moveItem(at: from, to: to)
        }
      } catch {
        // A provider (or the sandbox) that refuses the swap may still take
        // the bytes: atomically where a temp beside is allowed, else in place.
        do {
          let data = try Data(contentsOf: from, options: .mappedIfSafe)
          do {
            try data.write(to: to, options: .atomic)
          } catch {
            try data.write(to: to)
          }
        } catch {
          writeError = error
        }
      }
    }
    if let error = failure ?? (writeError as NSError?) { throw error }
  }
}

import Cocoa
import FlutterMacOS
import UniformTypeIdentifiers

class MainFlutterWindow: NSWindow {
  private let documents = Documents()
  private let splash = Splash()

  override func awakeFromNib() {
    splash.show()
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let channel = FlutterMethodChannel(
      name: "anisched/documents",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    documents.window = self
    channel.setMethodCallHandler { [documents] call, result in
      documents.handle(call, result: result)
    }

    // The app says when its first frame is up; the start screen goes.
    let splashChannel = FlutterMethodChannel(
      name: "anisched/splash",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    splashChannel.setMethodCallHandler { [splash] call, result in
      if call.method == "close" { splash.close() }
      result(nil)
    }

    super.awakeFromNib()
  }
}

/// The start screen (Anicel's way): the mark and the name, no ground, in a
/// transparent borderless window half the screen's short side tall, until
/// the app's first frame (`anisched/splash` `close`) — or ten seconds, at
/// the latest. The picture is the app's own asset (assets/app_art/
/// splash.png, drawn by tool/app_art).
///
/// Kept in this file: the Xcode project lists its sources explicitly.
final class Splash {
  private var window: NSWindow?

  func show() {
    let assets = Bundle.main.bundleURL.appendingPathComponent(
      "Contents/Frameworks/App.framework/Resources/flutter_assets/assets/app_art/splash.png")
    guard let image = NSImage(contentsOf: assets),
      let screen = NSScreen.main
    else { return }
    let area = screen.visibleFrame
    let height = min(area.width, area.height) / 2
    let width = image.size.width * height / max(image.size.height, 1)
    let frame = NSRect(
      x: area.midX - width / 2, y: area.midY - height / 2, width: width, height: height)
    let w = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
    w.isOpaque = false
    w.backgroundColor = .clear
    w.hasShadow = false
    w.level = .floating
    w.ignoresMouseEvents = true
    let view = NSImageView(frame: NSRect(origin: .zero, size: frame.size))
    view.image = image
    view.imageScaling = .scaleProportionallyUpOrDown
    w.contentView = view
    w.orderFrontRegardless()
    window = w
    DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.close() }
  }

  func close() {
    window?.orderOut(nil)
    window = nil
  }
}

/// The `anisched/documents` channel (docs/storage.md), macOS half.
///
/// Same answers as the iOS runner. The sandbox grants the one file a panel
/// returned — nothing beside it — so every write is a coordinated replace
/// from the app container, and the grant outlives a relaunch through an
/// app-scoped security bookmark. Ported from Anicel's runner (UNVERIFIED ON
/// DEVICE here as there).
///
/// Kept in this file: the Xcode project lists its sources explicitly.
final class Documents {
  weak var window: NSWindow?

  /// Items whose security scope this run holds, by path.
  private var scoped: [String: URL] = [:]
  private var busy = false

  private static let type: UTType =
    UTType("com.myoun.anisched.document") ?? UTType(filenameExtension: "anisched") ?? .data

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    let location = args["location"] as? String
    switch call.method {
    case "pick":
      pick(result: result)
    case "saveAs":
      guard let source = args["sourcePath"] as? String else {
        return result(Documents.unavailable("no source"))
      }
      saveAs(source: URL(fileURLWithPath: source), name: args["name"] as? String, result: result)
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

  private func pick(result: @escaping FlutterResult) {
    if busy { return result(["status": "cancelled"]) }
    busy = true
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [Documents.type]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    // Lets iCloud items that are not downloaded yet be picked.
    panel.canDownloadUbiquitousContents = true
    run(panel) { [weak self] ok in
      guard let self else { return }
      self.busy = false
      guard ok, let url = panel.url else { return result(["status": "cancelled"]) }
      result(self.grant(url))
    }
  }

  private func saveAs(source: URL, name: String?, result: @escaping FlutterResult) {
    if busy { return result(["status": "cancelled"]) }
    busy = true
    let panel = NSSavePanel()
    panel.allowedContentTypes = [Documents.type]
    panel.nameFieldStringValue = name ?? source.lastPathComponent
    run(panel) { [weak self] ok in
      guard let self else { return }
      self.busy = false
      guard ok, let url = panel.url else { return result(["status": "cancelled"]) }
      // The bookmark needs the file to exist: write first, then grant.
      Documents.background(result) {
        try DocumentIO.replace(url, from: source)
        var answer: [String: Any] = [:]
        DispatchQueue.main.sync { answer = self.grant(url) }
        return answer
      }
    }
  }

  private func run(_ panel: NSSavePanel, then: @escaping (Bool) -> Void) {
    if let window {
      panel.beginSheetModal(for: window) { then($0 == .OK) }
    } else {
      panel.begin { then($0 == .OK) }
    }
  }

  private func reopen(location: String?, bookmark: String?, result: FlutterResult) {
    if let location, scoped[location] != nil {
      return result(["status": "granted", "location": location, "bookmark": bookmark as Any])
    }
    guard let bookmark, let data = Data(base64Encoded: bookmark) else {
      return result(["status": "granted"])
    }
    var stale = false
    do {
      let url = try URL(
        resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil,
        bookmarkDataIsStale: &stale)
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
      options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil
    ).base64EncodedString()
    return [
      "status": "granted", "location": url.path, "name": url.lastPathComponent,
      "bookmark": bookmark as Any,
    ]
  }

  static func unavailable(_ message: String) -> [String: Any] {
    ["status": "unavailable", "message": message]
  }

  static func background(_ result: @escaping FlutterResult, _ work: @escaping () throws -> [String: Any]) {
    DispatchQueue.global(qos: .userInitiated).async {
      let answer: [String: Any]
      do { answer = try work() } catch { answer = unavailable(error.localizedDescription) }
      DispatchQueue.main.async { result(answer) }
    }
  }
}

/// Coordinated whole-file reads and writes — the same as the iOS runner's.
enum DocumentIO {
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

import Foundation

public enum WidgetSnapshotFallbackReason: String, Equatable, Sendable {
  case missingFile
  case expiredDay
  case unreadableFile
  case invalidJSON
  case unsupportedVersion
}

public struct WidgetSnapshotFallback: Equatable, Sendable {
  public let reason: WidgetSnapshotFallbackReason
  public let detail: String

  public init(reason: WidgetSnapshotFallbackReason, detail: String) {
    self.reason = reason
    self.detail = detail
  }
}

public enum WidgetSnapshotLoadResult: Equatable, Sendable {
  case snapshot(WidgetSnapshot)
  case fallback(WidgetSnapshotFallback)

  public var snapshot: WidgetSnapshot? {
    guard case .snapshot(let snapshot) = self else { return nil }
    return snapshot
  }
}

public struct WidgetSnapshotLoader {
  private static let defaultSnapshotDirectory = "Lorvex"
  public static let defaultSnapshotFileName = "widget_snapshot_v3.json"

  /// Upper bound on the snapshot file's byte length, enforced before the bytes
  /// are trusted (mirrors `LorvexImportLimits.readBoundedFile`'s
  /// size-before-materialize pattern). A widget/complication process runs under
  /// a tight jetsam budget, so a co-tenant or compromised host writing a huge
  /// `widget_snapshot_v3.json` would OOM-kill every refresh on a retry loop. A
  /// legitimate snapshot is a few KB; this bounds a hostile file far below the
  /// memory limit while never rejecting a real one.
  static let maxSnapshotBytes = 4 * 1024 * 1024

  /// Upper bound on the total number of decoded row elements across every
  /// snapshot array. A file within `maxSnapshotBytes` can still carry more rows
  /// than any widget renders; reject rather than trust and lay them all out.
  static let maxDecodedElements = 20_000

  private let fileManager: FileManager
  private let decoder: JSONDecoder

  public init(fileManager: FileManager = .default, decoder: JSONDecoder = JSONDecoder()) {
    self.fileManager = fileManager
    self.decoder = decoder
  }

  public func snapshotURL(
    inAppGroupContainer containerURL: URL,
    fileName: String = WidgetSnapshotLoader.defaultSnapshotFileName
  ) -> URL {
    containerURL
      .appendingPathComponent(WidgetSnapshotLoader.defaultSnapshotDirectory, isDirectory: true)
      .appendingPathComponent(fileName, isDirectory: false)
  }

  public func defaultSnapshotURL(
    appGroupID: String,
    fileName: String = WidgetSnapshotLoader.defaultSnapshotFileName
  ) -> URL? {
    guard let containerURL = fileManager.containerURL(
      forSecurityApplicationGroupIdentifier: appGroupID
    ) else {
      return nil
    }
    return snapshotURL(inAppGroupContainer: containerURL, fileName: fileName)
  }

  public func loadSnapshot(at url: URL) -> WidgetSnapshotLoadResult {
    // No `fileExists` pre-check: it races a concurrent host-process write/delete
    // (TOCTOU). Let the read throw and classify a genuinely-absent file as
    // `.missingFile` from the error itself, so the widget shows "open Lorvex to
    // refresh" rather than the generic "snapshot unavailable".
    do {
      // Reject an oversized file from filesystem metadata before mapping it, so a
      // huge snapshot never reaches the decoder. `try?` keeps this TOCTOU-safe:
      // a genuinely-absent file yields `nil` here and is classified from the read
      // error below, not misreported as oversized.
      if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
        size > Self.maxSnapshotBytes
      {
        return .fallback(
          .init(
            reason: .unreadableFile,
            detail: "Snapshot file is \(size) bytes, over the \(Self.maxSnapshotBytes)-byte cap"
          )
        )
      }
      let data = try Data(contentsOf: url, options: [.mappedIfSafe])
      // Defense in depth: the metadata size read can race a writer or resolve a
      // symlink; bound the materialized bytes too before decoding.
      guard data.count <= Self.maxSnapshotBytes else {
        return .fallback(
          .init(
            reason: .unreadableFile,
            detail: "Snapshot file is \(data.count) bytes, over the \(Self.maxSnapshotBytes)-byte cap"
          )
        )
      }
      let snapshot = try decoder.decode(WidgetSnapshot.self, from: data)
      guard snapshot.version == WidgetSnapshot.supportedVersion else {
        return .fallback(
          .init(
            reason: .unsupportedVersion,
            detail: "Unsupported snapshot version \(snapshot.version)"
          )
        )
      }
      let elementCount =
        snapshot.focusTasks.count + snapshot.habits.count + snapshot.todayTasks.count
        + snapshot.lists.count + snapshot.listStats.count
      guard elementCount <= Self.maxDecodedElements else {
        return .fallback(
          .init(
            reason: .unreadableFile,
            detail: "Snapshot has \(elementCount) rows, over the \(Self.maxDecodedElements)-element cap"
          )
        )
      }
      return .snapshot(snapshot)
    } catch let error as DecodingError {
      return .fallback(.init(reason: .invalidJSON, detail: "Snapshot JSON decode failed: \(error)"))
    } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
      return .fallback(.init(reason: .missingFile, detail: "Snapshot file not found at \(url.path)"))
    } catch {
      return .fallback(
        .init(
          reason: .unreadableFile,
          detail: "Snapshot file could not be read: \(error.localizedDescription)"
        )
      )
    }
  }
}

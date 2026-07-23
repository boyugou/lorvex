import Foundation
import LorvexCore
import LorvexWidgetKitSupport

final class LorvexWatchFileManagerBox: @unchecked Sendable {
  let value: FileManager

  init(_ value: FileManager) {
    self.value = value
  }
}

enum LorvexWatchReplicaStoreError: LocalizedError, Equatable {
  case appGroupUnavailable
  case baselineUnavailable
  case invalidSnapshot

  var errorDescription: String? {
    switch self {
    case .appGroupUnavailable:
      return "The Watch App Group container is unavailable."
    case .baselineUnavailable:
      return "Open Lorvex on iPhone to establish this watch's workspace."
    case .invalidSnapshot:
      return "The phone sent an invalid Watch snapshot."
    }
  }
}

/// Strict synchronous codec used by both the foreground store and complication
/// reader. The on-disk unit is the complete replica envelope, so the embedded
/// snapshot and workspace baseline become visible in one atomic file replace.
enum LorvexWatchReplicaFile {
  static let maximumEnvelopeBytes = 4 * 1024 * 1024
  static let maximumSnapshotElements = 20_000

  static func decode(_ wireData: Data) throws -> (
    envelope: LorvexWatchReplicaEnvelope,
    snapshot: WidgetSnapshot
  ) {
    guard wireData.count <= maximumEnvelopeBytes else {
      throw LorvexWatchReplicaStoreError.invalidSnapshot
    }
    let envelope = try LorvexWatchReplicaEnvelope.decodeWireData(wireData)
    let snapshot: WidgetSnapshot
    do {
      snapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: envelope.snapshotData)
    } catch {
      throw LorvexWatchReplicaStoreError.invalidSnapshot
    }
    guard snapshot.version == WidgetSnapshot.supportedVersion else {
      throw LorvexWatchWireError.unsupportedProtocolVersion(snapshot.version)
    }
    guard snapshot.workspaceInstanceID == envelope.workspaceInstanceID else {
      throw LorvexWatchReplicaStoreError.invalidSnapshot
    }
    let elementCount =
      snapshot.focusTasks.count + snapshot.habits.count
      + snapshot.todayTasks.count + snapshot.lists.count + snapshot.listStats.count
    guard elementCount <= maximumSnapshotElements else {
      throw LorvexWatchReplicaStoreError.invalidSnapshot
    }
    return (envelope, snapshot)
  }

  static func load(at url: URL) -> WidgetSnapshotLoadResult {
    do {
      if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
        size > maximumEnvelopeBytes
      {
        return .fallback(.init(reason: .unreadableFile, detail: "Replica envelope is oversized"))
      }
      let data = try Data(contentsOf: url, options: [.mappedIfSafe])
      return .snapshot(try decode(data).snapshot)
    } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
      return .fallback(.init(reason: .missingFile, detail: "Watch replica file not found"))
    } catch LorvexWatchWireError.unsupportedProtocolVersion(let version) {
      return .fallback(
        .init(reason: .unsupportedVersion, detail: "Unsupported Watch replica version \(version)"))
    } catch let error as CocoaError {
      return .fallback(
        .init(
          reason: .unreadableFile, detail: "Watch replica could not be read: \(error.code.rawValue)"
        ))
    } catch {
      return .fallback(.init(reason: .invalidJSON, detail: "Watch replica validation failed"))
    }
  }
}

/// Serializes phone replica acceptance and provides the authoritative workspace
/// fence used when journaling and sending Watch commands.
public actor LorvexWatchReplicaStore {
  private let appGroupID: String
  private let snapshotFileName: String
  private let fileManagerBox: LorvexWatchFileManagerBox
  /// Process-local callback order assigned synchronously by the WCSession
  /// delegate. Actor-task scheduling may invert two callbacks; once a newer
  /// callback is observed, an older task must never replace its workspace.
  private var highestObservedIngressSequence: UInt64?

  public init(
    appGroupID: String = LorvexProductMetadata.appGroupIdentifier,
    snapshotFileName: String = LorvexWatchReplicaStore.defaultReplicaFileName
  ) {
    self.appGroupID = appGroupID
    self.snapshotFileName = snapshotFileName
    self.fileManagerBox = LorvexWatchFileManagerBox(.default)
  }

  init(
    appGroupID: String,
    snapshotFileName: String = LorvexWatchReplicaStore.defaultReplicaFileName,
    fileManagerBox: LorvexWatchFileManagerBox
  ) {
    self.appGroupID = appGroupID
    self.snapshotFileName = snapshotFileName
    self.fileManagerBox = fileManagerBox
  }

  /// Accepts one fully validated replica. Storage generation is compared first,
  /// so a delayed pre-reset phone payload cannot resurrect erased titles on the
  /// watch. Within one generation, older snapshots are dropped only in the same
  /// workspace; a replacement workspace remains intentionally incomparable.
  @discardableResult
  func accept(
    _ wireData: Data,
    ingressSequence: UInt64? = nil,
    containerURL override: URL? = nil
  ) throws -> Bool {
    if let ingressSequence {
      if let highestObservedIngressSequence,
        ingressSequence <= highestObservedIngressSequence
      {
        return false
      }
      // Consume the callback order before decoding or I/O. If the latest
      // payload is corrupt or unwritable, retaining the prior disk value is
      // safer than allowing an older callback to become current afterward.
      highestObservedIngressSequence = ingressSequence
    }
    let incoming = try LorvexWatchReplicaFile.decode(wireData)
    let url = try replicaURL(containerURL: override)

    if let existingData = try? Data(contentsOf: url, options: [.mappedIfSafe]),
      let existing = try? LorvexWatchReplicaFile.decode(existingData),
      WidgetSnapshotOrdering.isStrictlyOlder(incoming.snapshot, than: existing.snapshot)
    {
      return false
    }

    try fileManagerBox.value.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true)
    try wireData.write(to: url, options: [.atomic])
    return true
  }

  func currentWorkspaceInstanceID() throws -> String {
    let url = try replicaURL(containerURL: nil)
    do {
      let data = try Data(contentsOf: url, options: [.mappedIfSafe])
      return try LorvexWatchReplicaFile.decode(data).envelope.workspaceInstanceID
    } catch {
      throw LorvexWatchReplicaStoreError.baselineUnavailable
    }
  }

  func replicaURL(containerURL override: URL?) throws -> URL {
    let container: URL
    if let override {
      container = override
    } else {
      guard
        let resolved = fileManagerBox.value.containerURL(
          forSecurityApplicationGroupIdentifier: appGroupID
        )
      else {
        throw LorvexWatchReplicaStoreError.appGroupUnavailable
      }
      container = resolved
    }
    return
      container
      .appendingPathComponent("Lorvex", isDirectory: true)
      .appendingPathComponent(snapshotFileName, isDirectory: false)
  }

  public static let defaultReplicaFileName = "watch_replica_v1.json"
}

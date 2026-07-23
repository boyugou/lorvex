import Foundation
import LorvexCore
import LorvexWidgetKitSupport

/// Watch-side endpoint for strict phone replica envelopes.
///
/// The receiver delegates persistence to `LorvexWatchReplicaStore`, whose one
/// atomic file contains both the workspace fence and embedded snapshot. It is
/// intentionally not a `WCSessionDelegate`; the connectivity forwarder owns the
/// single delegate slot and routes replica payloads here.
public final class LorvexWatchSnapshotReceiver: NSObject, @unchecked Sendable {
  private let replicaStore: LorvexWatchReplicaStore
  private let reloadAllTimelines: @Sendable () -> Void
  private let onSnapshotWritten: @Sendable () -> Void

  public init(
    replicaStore: LorvexWatchReplicaStore? = nil,
    appGroupID: String = LorvexProductMetadata.appGroupIdentifier,
    snapshotFileName: String = LorvexWatchReplicaStore.defaultReplicaFileName,
    fileManager: FileManager = .default,
    onSnapshotWritten: @escaping @Sendable () -> Void = {},
    reloadAllTimelines: @escaping @Sendable () -> Void = {
      GlanceSurfaceReloader.live.reloadAll()
    }
  ) {
    self.replicaStore =
      replicaStore
      ?? LorvexWatchReplicaStore(
        appGroupID: appGroupID,
        snapshotFileName: snapshotFileName,
        fileManagerBox: LorvexWatchFileManagerBox(fileManager))
    self.onSnapshotWritten = onSnapshotWritten
    self.reloadAllTimelines = reloadAllTimelines
    super.init()
  }

  /// Test seam for a supplied container. The exact replica envelope bytes are
  /// committed atomically; a same-workspace older snapshot is dropped.
  @discardableResult
  func writeReplicaEnvelope(_ data: Data, to containerURL: URL) async throws -> Bool {
    try await replicaStore.accept(data, containerURL: containerURL)
  }

  /// Persists and then refreshes both complication and foreground surfaces.
  @discardableResult
  func applyReplicaData(
    _ data: Data,
    ingressSequence: UInt64? = nil,
    to containerURL: URL? = nil
  ) async throws -> Bool {
    guard
      try await replicaStore.accept(
        data, ingressSequence: ingressSequence, containerURL: containerURL)
    else { return false }
    reloadAllTimelines()
    onSnapshotWritten()
    return true
  }

  /// Strictly consumes only `replicaEnvelopeV1: Data`. Invalid, corrupt, or
  /// unwritable payloads return false and never update either the snapshot or
  /// workspace baseline.
  @discardableResult
  public func handle(
    applicationContext: [String: Any],
    ingressSequence: UInt64? = nil
  ) async -> Bool {
    guard
      let data = applicationContext[LorvexWatchConnectivityKey.replicaEnvelopeV1] as? Data
    else { return false }
    do {
      return try await applyReplicaData(data, ingressSequence: ingressSequence)
    } catch {
      return false
    }
  }
}

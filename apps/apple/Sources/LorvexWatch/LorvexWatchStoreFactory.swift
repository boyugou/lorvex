import Foundation
import LorvexCore
import LorvexWidgetKitSupport

public struct LorvexWatchStoreFactory {
  public typealias SnapshotURLProvider = (String) -> URL?

  private let appGroupID: String
  private let snapshotURLProvider: SnapshotURLProvider
  private let now: @Sendable () -> Date
  private let mutationForwarder: (any LorvexWatchMutationForwarding)?

  public init(
    appGroupID: String = LorvexProductMetadata.appGroupIdentifier,
    snapshotURLProvider: @escaping SnapshotURLProvider = Self.defaultSnapshotURL,
    now: @escaping @Sendable () -> Date = Date.init,
    mutationForwarder: (any LorvexWatchMutationForwarding)? = nil
  ) {
    self.appGroupID = appGroupID
    self.snapshotURLProvider = snapshotURLProvider
    self.now = now
    self.mutationForwarder = mutationForwarder
  }

  @MainActor
  public func makeStore() -> LorvexWatchStore {
    if let snapshotURL = snapshotURLProvider(appGroupID) {
      return LorvexWatchStore(
        snapshotURL: snapshotURL,
        now: now,
        mutationForwarder: mutationForwarder
      )
    }
    return LorvexWatchStore(
      snapshotUnavailable: .init(reason: .missingFile, detail: "app_group_unavailable"),
      now: now,
      mutationForwarder: mutationForwarder
    )
  }

  public static func defaultSnapshotURL(appGroupID: String) -> URL? {
    guard let containerURL = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: appGroupID
    ) else { return nil }
    return containerURL
      .appendingPathComponent("Lorvex", isDirectory: true)
      .appendingPathComponent(LorvexWatchReplicaStore.defaultReplicaFileName)
  }
}

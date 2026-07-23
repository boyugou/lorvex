import Foundation
import LorvexCore

/// Rebuilds the App-Group widget snapshot from one atomic core source read.
///
/// This lives below individual App Intent modules so both interactive widget
/// intents and the system Focus-filter extension use the same background-safe
/// projection/write/reload path without app-process injection.
public struct WidgetSnapshotLiveRefresher: Sendable {
  private let configuration: LorvexWidgetConfiguration
  private let projector: WidgetSnapshotProjector
  private let focusFilterStore: FocusFilterStore?
  private let managedDatabasePath: String?
  private let reloadTimelines: @Sendable () -> Void
  /// Optional deterministic day override for tests. Shipping construction
  /// leaves this nil so SQLite captures the product-timezone day atomically.
  private let todayString: @Sendable () -> String?

  public init(
    configuration: LorvexWidgetConfiguration = LorvexWidgetConfiguration(),
    projector: WidgetSnapshotProjector = WidgetSnapshotProjector(),
    focusFilterStore: FocusFilterStore? = nil,
    managedDatabasePath: String? = nil,
    reloadTimelines: @escaping @Sendable () -> Void = {
      GlanceSurfaceReloader.live.reloadAll()
    },
    todayString: @escaping @Sendable () -> String? = { nil }
  ) {
    self.configuration = configuration
    self.projector = projector
    self.focusFilterStore = focusFilterStore
    self.managedDatabasePath = managedDatabasePath
    self.reloadTimelines = reloadTimelines
    self.todayString = todayString
  }

  public static func live(
    configuration: LorvexWidgetConfiguration = LorvexWidgetConfiguration()
  ) -> WidgetSnapshotLiveRefresher {
    let managedDatabasePath = try? SwiftLorvexCoreService.managedDatabasePath()
    let store = managedDatabasePath.map(FocusFilterStore.init(managedDatabasePath:))
    return WidgetSnapshotLiveRefresher(
      configuration: configuration,
      focusFilterStore: store,
      managedDatabasePath: managedDatabasePath)
  }

  @discardableResult
  public func refresh(core: any LorvexCoreServicing) async throws -> WidgetSnapshot {
    try await refresh(core: core, snapshotURL: configuration.resolvedSnapshotURL())
  }

  @discardableResult
  public func refresh(
    core: any LorvexCoreServicing,
    snapshotURL: URL?
  ) async throws -> WidgetSnapshot {
    let publisher = WidgetSnapshotPublisher(
      destination: WidgetSnapshotPublisher.Destination(
        snapshotURL: snapshotURL,
        managedDatabasePath: managedDatabasePath,
        focusFilterStore: focusFilterStore,
        reload: reloadTimelines,
        mirror: nil
      ),
      projector: projector)
    return try await publisher.refresh(core: core, today: todayString())
  }
}

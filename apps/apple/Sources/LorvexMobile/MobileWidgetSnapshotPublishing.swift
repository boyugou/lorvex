import Foundation
import LorvexCore
import LorvexWidgetKitSupport

public protocol MobileWidgetSnapshotPublishing: Sendable {
  /// Publishes one transactionally captured source. Shipping adapters override
  /// this requirement so the managed-storage generation cannot be dropped by a
  /// new adapter or test double.
  @MainActor
  func publish(source: WidgetSnapshotSource) async throws -> WidgetSnapshot

  @MainActor
  func publish(
    today: TodaySnapshot,
    currentFocus: CurrentFocusPlan?,
    habitCatalog: HabitCatalogSnapshot?,
    lists: ListCatalogSnapshot?
  ) async throws -> WidgetSnapshot

  /// Publishes with the uncapped canonical `statsSource` threaded into the
  /// projection so the widget's numeric stats reflect the whole workload. The
  /// default implementation ignores `statsSource` and forwards to the four-arg
  /// form; the file-backed publisher overrides it to pass the source through.
  @MainActor
  func publish(
    today: TodaySnapshot,
    currentFocus: CurrentFocusPlan?,
    habitCatalog: HabitCatalogSnapshot?,
    lists: ListCatalogSnapshot?,
    statsSource: WidgetStatsSource?
  ) async throws -> WidgetSnapshot
}

extension MobileWidgetSnapshotPublishing {
  @MainActor
  public func publish(
    today: TodaySnapshot,
    currentFocus: CurrentFocusPlan?,
    habitCatalog: HabitCatalogSnapshot?,
    lists: ListCatalogSnapshot?,
    statsSource: WidgetStatsSource?
  ) async throws -> WidgetSnapshot {
    try await publish(
      today: today, currentFocus: currentFocus, habitCatalog: habitCatalog, lists: lists)
  }
}

/// The no-op mobile publisher used when no App Group is configured: an engine
/// with a nil `snapshotURL` (no write), a no-op reload, and no watch mirror. It
/// still returns the projected snapshot so callers observe the same value they
/// would from a real publish.
public struct NoopMobileWidgetSnapshotPublisher: MobileWidgetSnapshotPublishing {
  public init() {}

  public func publish(source: WidgetSnapshotSource) async throws -> WidgetSnapshot {
    try await WidgetSnapshotPublisher(
      destination: WidgetSnapshotPublisher.Destination(snapshotURL: nil, reload: {})
    ).publish(source: source)
  }

  public func publish(
    today: TodaySnapshot,
    currentFocus: CurrentFocusPlan?,
    habitCatalog: HabitCatalogSnapshot?,
    lists: ListCatalogSnapshot?
  ) async throws -> WidgetSnapshot {
    try await publish(
      today: today, currentFocus: currentFocus, habitCatalog: habitCatalog, lists: lists,
      statsSource: nil)
  }

  public func publish(
    today: TodaySnapshot,
    currentFocus: CurrentFocusPlan?,
    habitCatalog: HabitCatalogSnapshot?,
    lists: ListCatalogSnapshot?,
    statsSource: WidgetStatsSource?
  ) async throws -> WidgetSnapshot {
    try await WidgetSnapshotPublisher(
      destination: WidgetSnapshotPublisher.Destination(snapshotURL: nil, reload: {})
    ).publish(
      today: today,
      currentFocus: currentFocus,
      habitCatalog: habitCatalog,
      lists: lists,
      statsSource: statsSource
    )
  }
}

public struct MobileWidgetReloadTrigger: Sendable {
  let reload: @Sendable () -> Void

  public init(reload: @escaping @Sendable () -> Void) {
    self.reload = reload
  }

  func callAsFunction() {
    reload()
  }

  public static let glanceSurfaces = MobileWidgetReloadTrigger(reload: {
    GlanceSurfaceReloader.live.reloadAll()
  })
}

/// iOS / iPadOS / visionOS host adapter over the shared `WidgetSnapshotPublisher`
/// engine.
///
/// Fills the engine `Destination` from the App-Group container (URL +
/// focus-filter store) and reloads via `MobileWidgetReloadTrigger`. On iPhone the
/// factory attaches a `mirror` that forwards the
/// projected snapshot value to a Watch-specific mirror. That mirror derives a
/// bounded replica containing only the focus, habit, briefing, and aggregate
/// fields consumed by the Watch; widget-only task/list catalogs stay local.
public struct MobileFileWidgetSnapshotPublisher: MobileWidgetSnapshotPublishing {
  private let snapshotURL: URL
  private let managedDatabasePath: String?
  private let projector: WidgetSnapshotProjector
  private let focusFilterStore: FocusFilterStore?
  private let reloadTrigger: MobileWidgetReloadTrigger
  private let mirror: (@Sendable (WidgetSnapshot) async -> Void)?

  public init(
    snapshotURL: URL,
    managedDatabasePath: String? = nil,
    projector: WidgetSnapshotProjector = WidgetSnapshotProjector(),
    focusFilterStore: FocusFilterStore? = nil,
    reloadTrigger: MobileWidgetReloadTrigger = .glanceSurfaces,
    mirror: (@Sendable (WidgetSnapshot) async -> Void)? = nil
  ) {
    self.snapshotURL = snapshotURL
    self.managedDatabasePath = managedDatabasePath
    self.projector = projector
    self.focusFilterStore = focusFilterStore
    self.reloadTrigger = reloadTrigger
    self.mirror = mirror
  }

  /// Returns a copy that forwards each published snapshot value to `mirror` (the
  /// paired watch on iPhone). `nil` leaves the publisher un-mirrored.
  public func mirroring(
    to mirror: (@Sendable (WidgetSnapshot) async -> Void)?
  ) -> MobileFileWidgetSnapshotPublisher {
    MobileFileWidgetSnapshotPublisher(
      snapshotURL: snapshotURL,
      managedDatabasePath: managedDatabasePath,
      projector: projector,
      focusFilterStore: focusFilterStore,
      reloadTrigger: reloadTrigger,
      mirror: mirror
    )
  }

  public func publish(
    today: TodaySnapshot,
    currentFocus: CurrentFocusPlan?,
    habitCatalog: HabitCatalogSnapshot?,
    lists: ListCatalogSnapshot?
  ) async throws -> WidgetSnapshot {
    try await publish(
      today: today, currentFocus: currentFocus, habitCatalog: habitCatalog, lists: lists,
      statsSource: nil)
  }

  public func publish(source: WidgetSnapshotSource) async throws -> WidgetSnapshot {
    try await makePublisher().publish(source: source)
  }

  private func makePublisher() -> WidgetSnapshotPublisher {
    WidgetSnapshotPublisher(
      destination: WidgetSnapshotPublisher.Destination(
        snapshotURL: snapshotURL,
        managedDatabasePath: managedDatabasePath,
        focusFilterStore: focusFilterStore,
        reload: reloadTrigger.reload,
        mirror: mirror
      ),
      projector: projector
    )
  }

  public func publish(
    today: TodaySnapshot,
    currentFocus: CurrentFocusPlan?,
    habitCatalog: HabitCatalogSnapshot?,
    lists: ListCatalogSnapshot?,
    statsSource: WidgetStatsSource?
  ) async throws -> WidgetSnapshot {
    let publisher = WidgetSnapshotPublisher(
      destination: WidgetSnapshotPublisher.Destination(
        snapshotURL: snapshotURL,
        managedDatabasePath: managedDatabasePath,
        focusFilterStore: focusFilterStore,
        reload: reloadTrigger.reload,
        mirror: mirror
      ),
      projector: projector
    )
    return try await publisher.publish(
      today: today,
      currentFocus: currentFocus,
      habitCatalog: habitCatalog,
      lists: lists,
      statsSource: statsSource
    )
  }

  public static func configuredFromEnvironment(
    _ environment: [String: String] = ProcessInfo.processInfo.environment,
    mirror: (@Sendable (WidgetSnapshot) async -> Void)? = nil
  ) -> (any MobileWidgetSnapshotPublishing)? {
    if let rawPath = environment["LORVEX_WIDGET_SNAPSHOT_PATH"], !rawPath.isEmpty {
      return MobileFileWidgetSnapshotPublisher(snapshotURL: URL(fileURLWithPath: rawPath))
        .mirroring(to: mirror)
    }

    guard let appGroupID = configuredAppGroupID(environment) else {
      return nil
    }
    guard
      let containerURL = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: appGroupID
      )
    else {
      return nil
    }
    let snapshotURL = WidgetSnapshotLoader().snapshotURL(inAppGroupContainer: containerURL)
    let managedDatabasePath = try? SwiftLorvexCoreService.managedDatabasePath()
    let store = managedDatabasePath.map(FocusFilterStore.init(managedDatabasePath:))
    return MobileFileWidgetSnapshotPublisher(
      snapshotURL: snapshotURL,
      managedDatabasePath: managedDatabasePath,
      focusFilterStore: store
    )
    .mirroring(to: mirror)
  }

  public static func configuredAppGroupID(
    _ environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> String? {
    if let appGroupID = environment["LORVEX_WIDGET_APP_GROUP_ID"], !appGroupID.isEmpty {
      return appGroupID
    }
    return LorvexProductMetadata.appGroupIdentifier
  }
}

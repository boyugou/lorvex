import Foundation
import LorvexCore
import LorvexWidgetKitSupport

protocol WidgetSnapshotPublishing {
  /// Non-nil only for the canonical managed App-Group destination. Explicit
  /// environment paths are developer-owned and are never erased by the app.
  var factoryResetTarget: WidgetSnapshotFactoryResetTarget? { get }

  /// Publishes one transactionally captured source, so the projection never
  /// mixes Today, habit, list, and stats revisions and the managed-storage
  /// generation orders the write.
  @MainActor
  func publish(source: WidgetSnapshotSource) async throws -> WidgetSnapshot
}

extension WidgetSnapshotPublishing {
  var factoryResetTarget: WidgetSnapshotFactoryResetTarget? { nil }
}

/// The no-op host publisher used on unsigned/unentitled local builds: an
/// engine with a nil `snapshotURL` (no write, no App-Group permission prompt), a
/// no-op reload, and no watch mirror. It still returns the projected snapshot so
/// the caller's `lastPublishedWidgetSnapshot` stays populated.
struct NoopWidgetSnapshotPublisher: WidgetSnapshotPublishing {
  func publish(source: WidgetSnapshotSource) async throws -> WidgetSnapshot {
    try await WidgetSnapshotPublisher(
      destination: WidgetSnapshotPublisher.Destination(snapshotURL: nil, reload: {})
    ).publish(source: source)
  }
}

/// Reloads every glance surface after a fresh snapshot has been written.
///
/// Injected so the file write can be unit-tested over a temp directory without
/// invoking the real `WidgetCenter`, which is unavailable outside a host app.
struct WidgetReloadTrigger: Sendable {
  let reload: @Sendable () -> Void

  func callAsFunction() { reload() }

  static let glanceSurfaces = WidgetReloadTrigger(reload: {
    GlanceSurfaceReloader.live.reloadAll()
  })
}

/// macOS host adapter over the shared `WidgetSnapshotPublisher` engine.
///
/// Fills the engine `Destination` from `AppGroupAccess` (URL + focus-filter
/// store), redacts titles per `hideTitles`, reloads every glance surface, and does
/// not mirror to a watch (the watch pairs with the iPhone, not the Mac). The
/// App-Group nil-gate lives in `configuredFromEnvironment`: on an unsigned local
/// build `AppGroupAccess.containerURL` is nil, so no publisher is built and the
/// host falls back to the engine-backed no-op — no write, no permission prompt.
struct FileWidgetSnapshotPublisher: WidgetSnapshotPublishing {
  private let snapshotURL: URL
  private let managedDatabasePath: String?
  private let hideTitles: Bool
  private let projector: WidgetSnapshotProjector
  private let focusFilterStore: FocusFilterStore?
  private let reloadTrigger: WidgetReloadTrigger

  init(
    snapshotURL: URL,
    managedDatabasePath: String? = nil,
    hideTitles: Bool = false,
    projector: WidgetSnapshotProjector = WidgetSnapshotProjector(),
    focusFilterStore: FocusFilterStore? = nil,
    reloadTrigger: WidgetReloadTrigger = .glanceSurfaces
  ) {
    self.snapshotURL = snapshotURL
    self.managedDatabasePath = managedDatabasePath
    self.hideTitles = hideTitles
    self.projector = projector
    self.focusFilterStore = focusFilterStore
    self.reloadTrigger = reloadTrigger
  }

  var factoryResetTarget: WidgetSnapshotFactoryResetTarget? {
    managedDatabasePath.map {
      WidgetSnapshotFactoryResetTarget(
        snapshotURL: snapshotURL,
        managedDatabasePath: $0,
        reload: reloadTrigger.reload)
    }
  }

  func publish(source: WidgetSnapshotSource) async throws -> WidgetSnapshot {
    try await makePublisher().publish(source: source)
  }

  private func makePublisher() -> WidgetSnapshotPublisher {
    WidgetSnapshotPublisher(
      destination: WidgetSnapshotPublisher.Destination(
        snapshotURL: snapshotURL,
        managedDatabasePath: managedDatabasePath,
        focusFilterStore: focusFilterStore,
        hideTitles: hideTitles,
        reload: reloadTrigger.reload,
        mirror: nil
      ),
      projector: projector
    )
  }

  static func configuredFromEnvironment(
    _ environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> (any WidgetSnapshotPublishing)? {
    if let rawPath = environment["LORVEX_WIDGET_SNAPSHOT_PATH"], !rawPath.isEmpty {
      return FileWidgetSnapshotPublisher(snapshotURL: URL(fileURLWithPath: rawPath))
    }

    guard let appGroupID = configuredAppGroupID(environment) else {
      return nil
    }
    guard let containerURL = AppGroupAccess.containerURL(for: appGroupID) else {
      return nil
    }
    let snapshotURL = WidgetSnapshotLoader().snapshotURL(inAppGroupContainer: containerURL)
    let managedDatabasePath = try? SwiftLorvexCoreService.managedDatabasePath()
    let store = managedDatabasePath.map(FocusFilterStore.init(managedDatabasePath:))
    return FileWidgetSnapshotPublisher(
      snapshotURL: snapshotURL,
      managedDatabasePath: managedDatabasePath,
      focusFilterStore: store)
  }

  static func configuredAppGroupID(
    _ environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> String? {
    if let appGroupID = environment["LORVEX_WIDGET_APP_GROUP_ID"], !appGroupID.isEmpty {
      return appGroupID
    }
    return LorvexProductMetadata.appGroupIdentifier
  }
}

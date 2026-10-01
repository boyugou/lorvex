@preconcurrency import CloudKit
import Foundation

/// The parts of `CKSyncEngine` that ``CloudSyncController`` drives.
///
/// Production wraps a real engine in ``LiveCloudSyncEngine``. Tests supply a
/// fake that records pending changes and fetch/send calls, and feed the
/// controller simulated events directly, because real CloudKit is unavailable
/// to unit tests.
public protocol CloudSyncEngineDriving: AnyObject, Sendable {
  var pendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange] { get }
  var pendingDatabaseChanges: [CKSyncEngine.PendingDatabaseChange] { get }
  func add(pendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange])
  func remove(pendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange])
  func add(pendingDatabaseChanges: [CKSyncEngine.PendingDatabaseChange])
  func fetchChanges(_ options: CKSyncEngine.FetchChangesOptions) async throws
  func sendChanges(_ options: CKSyncEngine.SendChangesOptions) async throws
  func cancelOperations() async
  /// Every zone in the private database, read directly from CloudKit.
  func allZoneIDs() async throws -> [CKRecordZone.ID]
  /// Deletes database subscriptions by ID. IDs that do not exist are ignored.
  func deleteSubscriptions(_ ids: [CKSubscription.ID]) async throws
  /// Whether `engine` is the instance this driver wraps. The controller ignores
  /// delegate callbacks from an engine it has already replaced.
  func wraps(_ engine: CKSyncEngine) -> Bool
}

/// Builds an engine for a persisted state (nil starts from scratch) that
/// reports to `delegate`. With `automaticallySync` false the engine fetches and
/// sends only when asked, which a short-lived engine needs so it does nothing
/// beyond the one job it was built for.
public typealias CloudSyncEngineFactory =
  @Sendable (
    _ stateSerialization: Data?, _ automaticallySync: Bool, _ delegate: any CKSyncEngineDelegate
  ) -> any CloudSyncEngineDriving

/// A real `CKSyncEngine` on the private database of one container.
public final class LiveCloudSyncEngine: CloudSyncEngineDriving, @unchecked Sendable {
  let engine: CKSyncEngine
  private let database: CKDatabase

  /// `stateSerialization` is the JSON encoding of
  /// `CKSyncEngine.State.Serialization`. An unreadable value starts from
  /// scratch, which costs one full fetch and loses nothing.
  public init(
    containerIdentifier: String, stateSerialization: Data?, automaticallySync: Bool,
    delegate: any CKSyncEngineDelegate
  ) {
    let state = stateSerialization.flatMap {
      try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0)
    }
    database = CKContainer(identifier: containerIdentifier).privateCloudDatabase
    var configuration = CKSyncEngine.Configuration(
      database: database,
      stateSerialization: state,
      delegate: delegate)
    configuration.automaticallySync = automaticallySync
    configuration.subscriptionID = CloudSyncController.engineSubscriptionID
    engine = CKSyncEngine(configuration)
  }

  public static func factory(containerIdentifier: String) -> CloudSyncEngineFactory {
    { state, automaticallySync, delegate in
      LiveCloudSyncEngine(
        containerIdentifier: containerIdentifier, stateSerialization: state,
        automaticallySync: automaticallySync, delegate: delegate)
    }
  }

  public var pendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange] {
    engine.state.pendingRecordZoneChanges
  }

  public var pendingDatabaseChanges: [CKSyncEngine.PendingDatabaseChange] {
    engine.state.pendingDatabaseChanges
  }

  public func add(pendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange]) {
    engine.state.add(pendingRecordZoneChanges: pendingRecordZoneChanges)
  }

  public func remove(pendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange]) {
    engine.state.remove(pendingRecordZoneChanges: pendingRecordZoneChanges)
  }

  public func add(pendingDatabaseChanges: [CKSyncEngine.PendingDatabaseChange]) {
    engine.state.add(pendingDatabaseChanges: pendingDatabaseChanges)
  }

  public func fetchChanges(_ options: CKSyncEngine.FetchChangesOptions) async throws {
    try await engine.fetchChanges(options)
  }

  public func sendChanges(_ options: CKSyncEngine.SendChangesOptions) async throws {
    try await engine.sendChanges(options)
  }

  public func cancelOperations() async {
    await engine.cancelOperations()
  }

  public func allZoneIDs() async throws -> [CKRecordZone.ID] {
    try await database.allRecordZones().map(\.zoneID)
  }

  public func deleteSubscriptions(_ ids: [CKSubscription.ID]) async throws {
    _ = try await database.modifySubscriptions(saving: [], deleting: ids)
  }

  public func wraps(_ engine: CKSyncEngine) -> Bool { self.engine === engine }
}

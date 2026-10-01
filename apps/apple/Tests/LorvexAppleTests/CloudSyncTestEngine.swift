import CloudKit
import Foundation
import LorvexCore
import Testing

@testable import LorvexCloudSync

// MARK: - Fake engine

/// Records pending changes and fetch/send calls. `onFetch`/`onSend` let a test
/// deliver simulated events while an explicit sync is in progress, the way the
/// real engine delivers them before `fetchChanges`/`sendChanges` return.
final class FakeCloudSyncEngine: CloudSyncEngineDriving, @unchecked Sendable {
  let lock = NSLock()
  private var recordChanges: [CKSyncEngine.PendingRecordZoneChange] = []
  private var databaseChanges: [CKSyncEngine.PendingDatabaseChange] = []
  var zones: [CKRecordZone.ID] = []
  var fetchCount = 0
  var sendCount = 0
  var cancelled = false
  var onFetch: (@Sendable () async throws -> Void)?
  var onSend: (@Sendable () async throws -> Void)?
  let initialState: Data?
  let automaticallySync: Bool

  init(initialState: Data?, automaticallySync: Bool = true) {
    self.initialState = initialState
    self.automaticallySync = automaticallySync
  }

  var pendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange] {
    lock.withLock { recordChanges }
  }
  var pendingDatabaseChanges: [CKSyncEngine.PendingDatabaseChange] {
    lock.withLock { databaseChanges }
  }
  func add(pendingRecordZoneChanges changes: [CKSyncEngine.PendingRecordZoneChange]) {
    lock.withLock {
      for change in changes where !recordChanges.contains(change) { recordChanges.append(change) }
    }
  }
  func remove(pendingRecordZoneChanges changes: [CKSyncEngine.PendingRecordZoneChange]) {
    lock.withLock { recordChanges.removeAll { changes.contains($0) } }
  }
  func add(pendingDatabaseChanges changes: [CKSyncEngine.PendingDatabaseChange]) {
    lock.withLock { databaseChanges.append(contentsOf: changes) }
  }
  func fetchChanges(_ options: CKSyncEngine.FetchChangesOptions) async throws {
    lock.withLock { fetchCount += 1 }
    try await onFetch?()
  }
  func sendChanges(_ options: CKSyncEngine.SendChangesOptions) async throws {
    lock.withLock { sendCount += 1 }
    try await onSend?()
  }
  func cancelOperations() async { lock.withLock { cancelled = true } }
  func allZoneIDs() async throws -> [CKRecordZone.ID] { zones }
  var deletedSubscriptions: [CKSubscription.ID] = []
  func deleteSubscriptions(_ ids: [CKSubscription.ID]) async throws {
    lock.withLock { deletedSubscriptions += ids }
  }
  func wraps(_ engine: CKSyncEngine) -> Bool { false }

  var pendingSaveNames: Set<String> {
    Set(
      pendingRecordZoneChanges.compactMap {
        if case .saveRecord(let id) = $0 { return id.recordName }
        return nil
      })
  }

  var queuesZoneSave: Bool {
    pendingDatabaseChanges.contains {
      if case .saveZone(let zone) = $0 { return zone.zoneID.zoneName == CloudSyncController.zoneName }
      return false
    }
  }

  func queuedZoneDeletes() -> [String] {
    pendingDatabaseChanges.compactMap {
      if case .deleteZone(let id) = $0 { return id.zoneName }
      return nil
    }
  }
}

final class FakeCloudSyncEngineBox: @unchecked Sendable {
  let lock = NSLock()
  var engines: [FakeCloudSyncEngine] = []
  /// Applied to every engine the factory builds, before the controller sees it.
  var configure: (@Sendable (FakeCloudSyncEngine) -> Void)?
  var latest: FakeCloudSyncEngine? { lock.withLock { engines.last } }

  var factory: CloudSyncEngineFactory {
    { state, automaticallySync, _ in
      let engine = FakeCloudSyncEngine(initialState: state, automaticallySync: automaticallySync)
      self.lock.withLock { self.engines.append(engine) }
      self.configure?(engine)
      return engine
    }
  }
}

// MARK: - Controller for store tests

/// A `CloudSyncController` over `store` whose engines are fakes, for tests of
/// the stores that own one. The account checker defaults to "available" and
/// the account to `account-a`.
struct TestCloudSync {
  let controller: CloudSyncController
  let engines = FakeCloudSyncEngineBox()
  let identities = InMemoryCloudSyncAccountIdentityStore()
  let pause = InMemoryCloudSyncPauseStateStore()
  let fields = InMemoryCloudSyncRecordSystemFieldsStore()
  let account: MutableAccountIdentifier

  init(
    store: any CloudSyncEngineStore,
    accountChecker: any CloudKitAccountStatusChecking = StubAccountStatusChecker(),
    account: String? = "account-a"
  ) {
    self.account = MutableAccountIdentifier(account)
    controller = CloudSyncController(
      store: store,
      accountChecker: accountChecker,
      accountIdentifier: self.account,
      accountIdentityStore: identities,
      pauseStore: pause,
      systemFieldsStore: fields,
      makeEngine: engines.factory)
  }

  var engine: FakeCloudSyncEngine {
    get throws { try #require(engines.latest) }
  }

  static let lorvexZone = CKRecordZone.ID(
    zoneName: CloudSyncController.zoneName, ownerName: CKCurrentUserDefaultName)

  /// Makes every engine this controller builds, the current one included,
  /// list `zones` and confirm deleting them when it sends — the server side of
  /// a successful "Delete iCloud Data". `beforeSend` runs first on each send.
  func confirmZoneDeletions(
    zones: [CKRecordZone.ID] = [TestCloudSync.lorvexZone],
    beforeSend: (@Sendable () async -> Void)? = nil
  ) {
    let controller = self.controller
    let configure: @Sendable (FakeCloudSyncEngine) -> Void = { engine in
      engine.zones = zones
      engine.onSend = {
        await beforeSend?()
        let deletes = engine.queuedZoneDeletes()
        await controller.handleSentDatabaseChanges(
          savedZoneIDs: [], failedZoneSaves: [],
          deletedZoneIDs: zones.filter { deletes.contains($0.zoneName) },
          failedZoneDeletes: [:])
      }
    }
    engines.configure = configure
    if let latest = engines.latest { configure(latest) }
  }

  /// Starts the controller, then delivers `records` on its engine's first
  /// fetch only, the way the real engine delivers a fetched batch before
  /// `fetchChanges` returns.
  func deliverOnFirstFetch(_ records: [CKRecord]) async throws {
    if await controller.state != .running { _ = await controller.start() }
    let controller = self.controller
    let delivered = OnceFlag()
    try engine.onFetch = {
      guard delivered.claim() else { return }
      await controller.handleFetchedRecords(records)
    }
  }

  /// Records a peer device would upload after `write` ran on its database,
  /// with what `write` returned.
  static func peerRecords<Value: Sendable>(
    _ write: sending (SwiftLorvexCoreService) async throws -> Value
  ) async throws -> (value: Value, records: [CKRecord]) {
    let peer = try SwiftLorvexCoreService.inMemory()
    let value = try await write(peer)
    let sync = TestCloudSync(store: peer)
    _ = await sync.controller.start()
    return (value, await sync.controller.nextBatch(scope: .all))
  }
}

final class OnceFlag: @unchecked Sendable {
  private let lock = NSLock()
  private var claimed = false

  /// True the first time only.
  func claim() -> Bool {
    lock.withLock {
      defer { claimed = true }
      return !claimed
    }
  }
}

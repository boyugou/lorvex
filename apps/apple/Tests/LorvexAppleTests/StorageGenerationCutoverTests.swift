import Foundation
import GRDB
import LorvexDomain
import LorvexRuntime
import LorvexStore
import LorvexSync
import Testing

@testable import LorvexCore

/// The factory-reset storage-generation protocol through
/// `SwiftLorvexCoreService`: the reset cutover bumps the durable generation
/// marker and deletes the managed database under the exclusive migration
/// flock, and every open store — including one standing in for a concurrent
/// second process such as the MCP helper — detects the changed generation at
/// its next operation and reopens the recreated file. No post-reset write may
/// land in the deleted inode, and no handle may keep serving the pre-reset
/// data (split brain).
struct StorageGenerationCutoverTests {

  @Test
  func resetReopensLiveServicesAndStrandsNoWriteInTheDeletedInode() async throws {
    let fm = FileManager.default
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("lorvex-generation-cutover-\(UUID().uuidString)", isDirectory: true)
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    let dataDir = root.appendingPathComponent("AppSupport").path
    let dbPath = dataDir + "/Lorvex/db.sqlite"
    // Managed local storage without App Group modeling (platform data dir):
    // the generation protocol applies to every managed resolution.
    let env = InMemoryDbLocatorEnv(dataDir: dataDir, homeDir: root.path, platform: .current)

    try await SwiftLorvexCoreService.$dbLocatorEnvironmentOverride.withValue(env) {
      // Two independently-opened handles over the same managed file, standing
      // in for the app's service and the MCP helper in another process.
      let appService = SwiftLorvexCoreService(databasePath: nil)
      let helperService = SwiftLorvexCoreService(databasePath: nil, surface: .mcp)
      _ = try await appService.setPreference(key: "theme", value: "system")
      let themeSeenByHelper = try await helperService.getPreference(key: "theme")
      #expect(themeSeenByHelper == "\"system\"")

      // The pre-reset device identity, written to the (about-to-be-deleted) file
      // by the first write above.
      let preResetDeviceId = try deviceId(at: dbPath)
      #expect(preResetDeviceId != nil)

      // Keep the pre-reset inode inspectable after the reset unlinks it.
      let oldInodePath = root.appendingPathComponent("old-inode.sqlite").path
      try fm.linkItem(atPath: dbPath, toPath: oldInodePath)

      try SwiftLorvexCoreService.resetManagedStorage(at: URL(fileURLWithPath: dbPath))
      #expect(ManagedStorageGeneration.read(forDatabase: dbPath) == 1)
      #expect(!fm.fileExists(atPath: dbPath))

      // Both live handles must detect the bumped generation on their next
      // operation and reopen the recreated file.
      _ = try await appService.setPreference(key: "language", value: "en")
      let themeAfterReset = try await helperService.getPreference(key: "theme")
      #expect(themeAfterReset == nil, "a stale handle kept serving pre-reset data (split brain)")
      let postSeenByHelper = try await helperService.getPreference(key: "language")
      #expect(postSeenByHelper == "\"en\"")
      #expect(fm.fileExists(atPath: dbPath))

      // H5: the FIRST write after the reset must resolve the device identity
      // from the recreated database, not reuse the identity cached from the
      // deleted one. A fresh, non-nil device id distinct from the pre-reset id
      // proves `writeState()` observed the cutover before consulting its cache.
      let postResetDeviceId = try deviceId(at: dbPath)
      #expect(
        postResetDeviceId != nil, "the first post-reset write left sync_checkpoints.device_id unset"
      )
      #expect(
        postResetDeviceId != preResetDeviceId,
        "the first post-reset write stamped the fresh database with the pre-reset device identity")

      // The post-reset write landed in the recreated file, not the deleted
      // inode. Synchronous so GRDB's sync `read` overload applies. The
      // pre-reset inode may have carried all content in its (now unlinked)
      // WAL, so a missing `preferences` table also counts as "no write here".
      func postResetValue(at path: String) throws -> String? {
        let queue = try DatabaseQueue(path: path)
        return try queue.read { db in
          let hasTable =
            try Bool.fetchOne(
              db,
              sql: "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE name = 'preferences')")
            ?? false
          guard hasTable else { return nil }
          return try String.fetchOne(
            db, sql: "SELECT value FROM preferences WHERE key = 'language'")
        }
      }
      // A fresh reader over the recreated path sees it…
      #expect(try postResetValue(at: dbPath) != nil)
      // …and the pre-reset inode (alive via the hard link) does not.
      #expect(try postResetValue(at: oldInodePath) == nil, "a write landed in the deleted inode")
    }
  }

  /// H4 defense-in-depth: a factory reset bumps the generation marker *before*
  /// deleting the database file, so an open that landed in that window records
  /// the bumped generation and, comparing generations alone, would keep serving
  /// the deleted inode. The open store therefore also tracks the database file's
  /// inode and reopens when it moves underneath an unchanged marker signature.
  @Test
  func staleHandleReopensWhenFileReplacedUnderUnchangedMarker() async throws {
    let fm = FileManager.default
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("lorvex-generation-inode-\(UUID().uuidString)", isDirectory: true)
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    let dataDir = root.appendingPathComponent("AppSupport").path
    let dbPath = dataDir + "/Lorvex/db.sqlite"
    let env = InMemoryDbLocatorEnv(dataDir: dataDir, homeDir: root.path, platform: .current)

    try await SwiftLorvexCoreService.$dbLocatorEnvironmentOverride.withValue(env) {
      let appService = SwiftLorvexCoreService(databasePath: nil)
      _ = try await appService.setPreference(key: "theme", value: "system")
      #expect(try await appService.getPreference(key: "theme") == "\"system\"")

      // Replace the managed file out-of-band with a fresh inode, leaving the
      // generation marker untouched (no marker exists for platform-data-dir
      // storage, so its signature is unchanged either way). This models an open
      // stranded on the reset's pre-delete inode: only the inode betrays it.
      try fm.removeItem(atPath: dbPath)
      try? fm.removeItem(atPath: dbPath + "-wal")
      try? fm.removeItem(atPath: dbPath + "-shm")
      let replacement = SwiftLorvexCoreService(databasePath: nil)
      _ = try await replacement.setPreference(key: "language", value: "en")

      // The still-cached handle must detect the changed inode and reopen onto the
      // recreated file rather than serve the deleted (still-open) inode.
      let staleValue = try await appService.getPreference(key: "theme")
      #expect(staleValue == nil, "a stale handle kept serving the replaced inode")
      let newValue = try await appService.getPreference(key: "language")
      #expect(newValue == "\"en\"")
    }
  }

  @Test
  func repeatedResetsKeepAdvancingTheGeneration() async throws {
    let fm = FileManager.default
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("lorvex-generation-repeat-\(UUID().uuidString)", isDirectory: true)
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    let dataDir = root.appendingPathComponent("AppSupport").path
    let dbPath = dataDir + "/Lorvex/db.sqlite"
    let env = InMemoryDbLocatorEnv(dataDir: dataDir, homeDir: root.path, platform: .current)

    try await SwiftLorvexCoreService.$dbLocatorEnvironmentOverride.withValue(env) {
      let service = SwiftLorvexCoreService(databasePath: nil)
      for round in 1...3 {
        _ = try await service.setPreference(key: "setup_summary", value: "round-\(round)")
        try SwiftLorvexCoreService.resetManagedStorage(at: URL(fileURLWithPath: dbPath))
        #expect(ManagedStorageGeneration.read(forDatabase: dbPath) == round)
        let value = try await service.getPreference(key: "setup_summary")
        #expect(value == nil)
      }
    }
  }

  // MARK: - CK-3: reset landing in the identity-resolution → transaction window

  /// A cross-process factory reset fires ONCE inside the window between
  /// `writeState()` resolving the device identity and the write's transaction
  /// committing. The storage-cutover guard must detect the redirected database
  /// inside the transaction, abort before minting, and the bounded retry must
  /// re-resolve a fresh identity against the recreated database — so no write
  /// ever commits under, or phantoms, the erased database's identity.
  @Test
  func resetInTheWriteStateWindowStrandsNoPhantomIdentity() async throws {
    try await withManagedFixture { service, dbPath in
      // Mint the pre-reset identity (D0) with a first write.
      _ = try await service.setPreference(key: "theme", value: "system")
      let d0 = try #require(try deviceId(at: dbPath))

      // The one-shot reset makes the SECOND write's first attempt resolve D0
      // against the pre-reset db, then redirects its transaction onto a fresh db;
      // the guard aborts and the retry re-resolves against the recreated db.
      let barrier = WriteStateWindowReset(dbPath: dbPath, resetEveryTime: false)
      try await SwiftLorvexCoreService.$afterWriteStateBarrierForTesting.withValue(barrier.fire) {
        _ = try await service.setPreference(key: "language", value: "en")
      }
      #expect(barrier.fireCount == 1)

      // The fresh db carries a fresh, non-nil identity — never the phantom D0
      // that an unguarded write would have committed under.
      let postId = try deviceId(at: dbPath)
      #expect(postId != nil, "the post-reset write left sync_checkpoints.device_id unset")
      #expect(postId != d0, "the post-reset write stamped the fresh db with the pre-reset identity")
      // The write ultimately succeeded, under the fresh identity.
      #expect(try await service.getPreference(key: "language") == "\"en\"")
      // No row anywhere carries the erased identity.
      #expect(try rowsStamped(withDeviceId: d0, at: dbPath) == 0)
    }
  }

  /// When the reset fires on EVERY attempt, no attempt's resolved identity can
  /// ever match its (freshly-reset) committing db: the guard aborts each time and
  /// the bounded retry is exhausted, surfacing `StorageCutoverDuringWrite`. The
  /// failure is clean — the fresh db still carries no phantom of the erased
  /// identity.
  @Test
  func resetOnEveryAttemptFailsCleanlyWithoutPhantomIdentity() async throws {
    try await withManagedFixture { service, dbPath in
      _ = try await service.setPreference(key: "theme", value: "system")
      let d0 = try #require(try deviceId(at: dbPath))

      let barrier = WriteStateWindowReset(dbPath: dbPath, resetEveryTime: true)
      await #expect(throws: StorageCutoverDuringWrite.self) {
        try await SwiftLorvexCoreService.$afterWriteStateBarrierForTesting.withValue(barrier.fire) {
          _ = try await service.setPreference(key: "language", value: "fr")
        }
      }
      // Fired once per attempt: the initial attempt plus the bounded retries.
      #expect(barrier.fireCount == SwiftLorvexCoreService.maxStorageCutoverRetries + 1)
      // Even on clean failure, the erased identity was never phantomed forward.
      #expect(try deviceId(at: dbPath) != d0)
      #expect(try rowsStamped(withDeviceId: d0, at: dbPath) == 0)
    }
  }

  /// The same reset window exists in the inbound-sync funnel: `applyInbound`
  /// resolves identity, then opens its transaction through a re-resolved store
  /// handle. A one-shot reset in that window must be caught by the guard and
  /// retried, so the peer envelope applies to the recreated db under a fresh
  /// identity, never phantoming the erased one.
  @Test
  func resetInTheApplyInboundWindowStrandsNoPhantomIdentity() async throws {
    try await withManagedFixture { service, dbPath in
      _ = try await service.setPreference(key: "theme", value: "system")
      let d0 = try #require(try deviceId(at: dbPath))

      // A task-upsert envelope onto the always-seeded inbox list, so the upsert
      // applies rather than deferring on a missing FK.
      let taskId = "01966a3f-7c8b-7d4e-8f3a-0000000000c3"
      let version = try Hlc.parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
      // Storage-cutover behavior is the subject, but the peer record still
      // crosses the production payload manifest and must be a complete current
      // task envelope.
      let payload = try canonicalizeJSON(
        .object([
          "ai_notes": .null,
          "archive_version": .string(version.description),
          "archived_at": .null,
          "available_from": .null,
          "body": .null,
          "canonical_occurrence_date": .null,
          "completed_at": .null,
          "content_version": .string(version.description),
          "created_at": .string("2026-04-01T00:00:00.000Z"),
          "defer_count": .int(0),
          "due_date": .null,
          "estimated_minutes": .null,
          "id": .string(taskId),
          "last_defer_reason": .null,
          "last_deferred_at": .null,
          "lifecycle_version": .string(version.description),
          "list_id": .string("inbox"),
          "planned_date": .null,
          "priority": .null,
          "raw_input": .null,
          "recurrence": .null,
          "recurrence_exceptions": .null,
          "recurrence_group_id": .null,
          "recurrence_instance_key": .null,
          "recurrence_rollover_state": .string("none"),
          "recurrence_successor_id": .null,
          "schedule_version": .string(version.description),
          "spawned_from": .null,
          "spawned_from_version": .null,
          "status": .string("open"),
          "title": .string("Inbound task"),
          "updated_at": .string("2026-04-01T00:00:00.000Z"),
          "version": .string(version.description),
        ]))
      let envelope = SyncEnvelope(
        entityType: .task,
        entityId: taskId,
        operation: .upsert,
        version: version,
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: payload,
        deviceId: "device-peer")

      let barrier = WriteStateWindowReset(dbPath: dbPath, resetEveryTime: false)
      let report = try SwiftLorvexCoreService.$afterWriteStateBarrierForTesting.withValue(
        barrier.fire
      ) {
        try service.applyInbound([envelope], undecodable: 0)
      }
      #expect(barrier.fireCount == 1)
      #expect(report.applied == 1)

      // Fresh identity in the recreated db; the peer's task landed there; the
      // erased identity is stamped on nothing.
      let postId = try deviceId(at: dbPath)
      #expect(postId != nil)
      #expect(postId != d0)
      #expect(try taskCount(id: taskId, at: dbPath) == 1)
      #expect(try rowsStamped(withDeviceId: d0, at: dbPath) == 0)
    }
  }

  // MARK: - Reset waits for complete active operations

  /// The write pauses inside `BEGIN IMMEDIATE`, after the committing identity
  /// check. Factory reset starts on a second task and must remain blocked on its
  /// EXCLUSIVE cutover lock until the write commits and releases its SHARED
  /// operation lease. The mutation therefore linearizes before reset and is
  /// erased by it; it can never commit afterward into an already-unlinked inode.
  @Test
  func resetWaitsForActiveWriteTransactionBeforeErasingIt() async throws {
    try await withManagedFixture { service, dbPath in
      _ = try await service.setPreference(key: "theme", value: "system")
      let preResetDeviceId = try #require(try deviceId(at: dbPath))

      let barrier = BlockingOperationBarrier()
      let writeTask = Task {
        try await SwiftLorvexCoreService.$afterIdentityAssertBarrierForTesting.withValue(
          barrier.pause
        ) {
          _ = try await service.setPreference(key: "language", value: "en")
        }
      }
      #expect(barrier.waitUntilPaused(), "the write never reached its transaction barrier")

      let resetState = BackgroundOperationState()
      let resetTask = Task.detached {
        resetState.markStarted()
        defer { resetState.markCompleted() }
        try SwiftLorvexCoreService.resetManagedStorage(at: URL(fileURLWithPath: dbPath))
      }
      #expect(resetState.waitUntilStarted(), "the reset task never started")
      #expect(
        !resetState.waitUntilCompleted(timeout: 0.2),
        "factory reset completed while a managed write transaction was still active")

      barrier.release()
      _ = try await writeTask.value
      try await resetTask.value
      #expect(ManagedStorageGeneration.read(forDatabase: dbPath) == 1)
      #expect(try await service.getPreference(key: "theme") == nil)
      #expect(try await service.getPreference(key: "language") == nil)

      // The service reconnects to the fresh generation and mints a new identity.
      _ = try await service.setPreference(key: "setup_summary", value: "post-reset")
      #expect(try await service.getPreference(key: "setup_summary") == "\"post-reset\"")
      let postResetDeviceId = try deviceId(at: dbPath)
      #expect(postResetDeviceId != nil, "the post-reset write left device_id unset")
      #expect(
        postResetDeviceId != preResetDeviceId,
        "the post-reset write reused the erased database's identity")
    }
  }

  /// A complete backup is one read transaction. Pausing after its active-list
  /// partition proves factory reset also waits for a long-lived read/export
  /// snapshot, rather than unlinking the database while later export queries are
  /// still reading the old inode.
  @Test
  func resetWaitsForActiveExportReadSnapshot() async throws {
    try await withManagedFixture { service, dbPath in
      _ = try await service.setPreference(key: "theme", value: "system")

      let barrier = BlockingOperationBarrier()
      let exportTask = Task {
        try await SwiftLorvexCoreService.$afterActiveListsExportReadForTesting.withValue(
          barrier.pause
        ) {
          try await service.loadSnapshotForDataExport(
            entities: ["lists"], forAI: false, includeNativeTaskGraph: false)
        }
      }
      #expect(barrier.waitUntilPaused(), "the export never reached its read barrier")

      let resetState = BackgroundOperationState()
      let resetTask = Task.detached {
        resetState.markStarted()
        defer { resetState.markCompleted() }
        try SwiftLorvexCoreService.resetManagedStorage(at: URL(fileURLWithPath: dbPath))
      }
      #expect(resetState.waitUntilStarted(), "the reset task never started")
      #expect(
        !resetState.waitUntilCompleted(timeout: 0.2),
        "factory reset completed while an export read transaction was still active")

      barrier.release()
      let snapshot = try await exportTask.value
      #expect(snapshot.payload.lists != nil)
      try await resetTask.value
      #expect(ManagedStorageGeneration.read(forDatabase: dbPath) == 1)
      #expect(try await service.getPreference(key: "theme") == nil)
    }
  }

  // MARK: - Corruption/incomplete-DB quarantine: cross-process double-opener race

  /// Two openers over one corrupt managed database, deterministically
  /// interleaved so BOTH detect the same fault before EITHER quarantines. Each
  /// opens the corrupt file on its shared-cutover-lock fast path, faults, and
  /// releases the shared lock; the `beforeManagedQuarantineRecoveryForTesting`
  /// seam then rendezvouses both in the exact window the fix closes — after fault
  /// detection, before the EXCLUSIVE cutover lock. They serialize on that lock:
  /// exactly one quarantines + recreates, and the other RE-CHECKS under the lock,
  /// finds the healthy database the winner just created, and opens it WITHOUT
  /// quarantining a second time.
  ///
  /// Asserts the three properties that fail under the pre-fix shared-lock-only
  /// quarantine (where both openers would quarantine and split the store): exactly
  /// ONE `.incompatible-*.bak`, both openers on the SAME recreated inode, and the
  /// set-aside file is the original corrupt bytes (no data-bearing fresh database
  /// was quarantined). A not-a-database file is the deterministic fixture; a
  /// structurally-incomplete DB (the #27 completeness probe) routes through the
  /// identical recovery path.
  @Test
  func twoOpenersOnACorruptManagedDbQuarantineOnceAndShareOneInode() async throws {
    let fm = FileManager.default
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("lorvex-quarantine-race-\(UUID().uuidString)", isDirectory: true)
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    let dataDir = root.appendingPathComponent("AppSupport").path
    let dbDir = dataDir + "/Lorvex"
    let dbPath = dbDir + "/db.sqlite"
    try fm.createDirectory(atPath: dbDir, withIntermediateDirectories: true)

    let preQuarantineDeviceID = "01966a3f-7c8b-7d4e-8f3a-00000000d001"
    try ManagedInstallIdentity.write(
      forDatabase: dbPath, deviceId: preQuarantineDeviceID)

    // Plant a not-a-database file at the managed path: the fast-path open throws
    // SQLITE_NOTADB, which is quarantine-recoverable.
    let corruptBytes = Data("this is not a sqlite database".utf8)
    try corruptBytes.write(to: URL(fileURLWithPath: dbPath))

    let env = InMemoryDbLocatorEnv(dataDir: dataDir, homeDir: root.path, platform: .current)
    let rendezvous = TwoPartyRendezvous(parties: 2)

    try await SwiftLorvexCoreService.$dbLocatorEnvironmentOverride.withValue(env) {
      // Two independently-opened handles over the same managed file, standing in
      // for the app service and the MCP helper in another process.
      let openerA = SwiftLorvexCoreService(databasePath: nil)
      let openerB = SwiftLorvexCoreService(databasePath: nil, surface: .mcp)

      // The barrier is bound only across the concurrent opens; the post-recovery
      // assertion writes below run with it unbound (their store() is cached and
      // healthy, so it never re-enters recovery anyway).
      try await SwiftLorvexCoreService.$beforeManagedQuarantineRecoveryForTesting.withValue(
        rendezvous.arriveAndWait
      ) {
        // Both first-touches open concurrently. A read is enough to drive the
        // lazy open + recovery; each faults on the corrupt file, rendezvouses in
        // the pre-exclusive window, then races for the exclusive lock.
        async let a: String? = openerA.getPreference(key: "theme")
        async let b: String? = openerB.getPreference(key: "theme")
        _ = try await a
        _ = try await b
      }

      // BOTH openers reached the recovery window: both detected the fault (the
      // barrier fired twice), so the interleaving the fix must survive was
      // genuinely exercised — not one opener sailing through a healthy database.
      #expect(rendezvous.arrivedCount == 2)

      // Exactly ONE opener quarantined: exactly one `.incompatible-*.bak`.
      let backups = try fm.contentsOfDirectory(atPath: dbDir)
        .filter { $0.contains(".incompatible-") && $0.hasSuffix(".bak") }
      #expect(
        backups.count == 1, "expected exactly one quarantine, got \(backups.count): \(backups)")

      // The set-aside file is the original corrupt bytes — the second arriver did
      // NOT quarantine the healthy database the first one recreated.
      if let only = backups.first {
        let setAside = try Data(contentsOf: URL(fileURLWithPath: dbDir + "/" + only))
        #expect(setAside == corruptBytes, "a data-bearing fresh database was set aside")
      }

      // Exactly one opener reports a recovery notice (the quarantiner); the other
      // re-checked, found the healthy database, and opened it clean.
      let notices = [openerA.databaseRecoveryNotice, openerB.databaseRecoveryNotice]
        .compactMap { $0 }
      #expect(notices.count == 1, "expected one recovery notice, got \(notices.count)")

      // Both openers landed on the SAME recreated inode: a write through one is
      // visible through the other. A split-brain (two inodes) would hide it.
      _ = try await openerA.setPreference(key: "theme", value: "dark")
      #expect(
        try await openerB.getPreference(key: "theme") == "\"dark\"",
        "openers ended on different inodes (split brain)")
      _ = try await openerB.setPreference(key: "language", value: "en")
      #expect(try await openerA.getPreference(key: "language") == "\"en\"")

      // The corrupt file's HLC checkpoint was discarded with the quarantined
      // database. Its backup-excluded install marker must be discarded in the
      // same cutover, so the first write mints a fresh suffix rather than
      // adopting the old writer id with no monotonic clock history.
      let postQuarantineDeviceID = try #require(try deviceId(at: dbPath))
      #expect(postQuarantineDeviceID != preQuarantineDeviceID)
      #expect(
        ManagedInstallIdentity.read(forDatabase: dbPath) == postQuarantineDeviceID)

      // The live managed file is a healthy database the recovery recreated.
      #expect(fm.fileExists(atPath: dbPath))
      #expect(ManagedStorageGeneration.databaseInode(forDatabase: dbPath) != nil)

      // Quarantine is a physical-store replacement just like factory reset.
      // It advances exactly once even though two openers independently saw the
      // original fault; delayed pre-quarantine sidecar/watch snapshots therefore
      // compare older than every projection from the recreated workspace.
      #expect(ManagedStorageGeneration.read(forDatabase: dbPath) == 1)
    }
  }

  @Test
  func quarantineIdentityMarkerRemovalFailureLeavesTheCorruptDatabaseUntouched() async throws {
    let fm = FileManager.default
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent(
        "lorvex-quarantine-identity-failure-\(UUID().uuidString)", isDirectory: true)
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    let dataDir = root.appendingPathComponent("AppSupport").path
    let dbDir = dataDir + "/Lorvex"
    let dbPath = dbDir + "/db.sqlite"
    try fm.createDirectory(atPath: dbDir, withIntermediateDirectories: true)

    let corruptBytes = Data("identity-removal failure must not quarantine me".utf8)
    try corruptBytes.write(to: URL(fileURLWithPath: dbPath))
    let oldDeviceID = "01966a3f-7c8b-7d4e-8f3a-00000000d002"
    try ManagedInstallIdentity.write(forDatabase: dbPath, deviceId: oldDeviceID)
    let identityPath = ManagedInstallIdentity.markerPath(forDatabase: dbPath)
    try fm.setAttributes([.immutable: true], ofItemAtPath: identityPath)
    defer { try? fm.setAttributes([.immutable: false], ofItemAtPath: identityPath) }

    let env = InMemoryDbLocatorEnv(dataDir: dataDir, homeDir: root.path, platform: .current)
    try await SwiftLorvexCoreService.$dbLocatorEnvironmentOverride.withValue(env) {
      let service = SwiftLorvexCoreService(databasePath: nil)
      var didThrow = false
      do {
        _ = try await service.getPreference(key: "theme")
      } catch {
        didThrow = true
      }
      #expect(didThrow, "recovery proceeded after install-identity removal failed")

      #expect(
        try Data(contentsOf: URL(fileURLWithPath: dbPath)) == corruptBytes,
        "the corrupt database moved before identity removal completed")
      let backups = try fm.contentsOfDirectory(atPath: dbDir)
        .filter { $0.contains(".incompatible-") && $0.hasSuffix(".bak") }
      #expect(backups.isEmpty, "a failed identity cutover quarantined the database")
      #expect(ManagedStorageGeneration.read(forDatabase: dbPath) == 1)
      #expect(ManagedInstallIdentity.read(forDatabase: dbPath) == oldDeviceID)
      #expect(service.databaseRecoveryNotice == nil)
    }
  }

  /// A 2-party rendezvous bound into
  /// ``SwiftLorvexCoreService/beforeManagedQuarantineRecoveryForTesting`` so two
  /// openers deterministically meet in the quarantine-recovery window — each
  /// having detected the fault and released its shared cutover lock, neither yet
  /// holding the exclusive lock. The first arriver blocks until the second
  /// arrives; a bounded deadline turns a coordination bug into a test failure
  /// rather than a hang. `@unchecked Sendable`: all state is `NSCondition`-guarded.
  private final class TwoPartyRendezvous: @unchecked Sendable {
    private let parties: Int
    private let condition = NSCondition()
    private var arrived = 0

    init(parties: Int) { self.parties = parties }

    var arrivedCount: Int {
      condition.lock()
      defer { condition.unlock() }
      return arrived
    }

    func arriveAndWait() {
      condition.lock()
      defer { condition.unlock() }
      arrived += 1
      if arrived >= parties {
        condition.broadcast()
        return
      }
      let deadline = Date().addingTimeInterval(10)
      while arrived < parties {
        if !condition.wait(until: deadline) { return }
      }
    }
  }

  /// Open a managed-storage service over a throwaway temp directory (platform
  /// data dir modeling — the generation protocol applies to every managed
  /// resolution) and run `body` with the service and its resolved db path.
  private func withManagedFixture(
    _ body: (SwiftLorvexCoreService, String) async throws -> Void
  ) async throws {
    let fm = FileManager.default
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("lorvex-cutover-window-\(UUID().uuidString)", isDirectory: true)
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    let dataDir = root.appendingPathComponent("AppSupport").path
    let dbPath = dataDir + "/Lorvex/db.sqlite"
    let env = InMemoryDbLocatorEnv(dataDir: dataDir, homeDir: root.path, platform: .current)
    try await SwiftLorvexCoreService.$dbLocatorEnvironmentOverride.withValue(env) {
      try await body(SwiftLorvexCoreService(databasePath: nil), dbPath)
    }
  }

  /// Rows across the device-id-bearing sync tables stamped with `id`, read
  /// through a fresh connection. A phantom identity from the cutover race would
  /// leave the erased device's id here; a correct guard leaves zero.
  private func rowsStamped(withDeviceId id: String, at path: String) throws -> Int {
    let queue = try DatabaseQueue(path: path)
    return try queue.read { db in
      func count(_ table: String, _ column: String) throws -> Int {
        let exists =
          try Bool.fetchOne(
            db, sql: "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE name = ?)",
            arguments: [table]) ?? false
        guard exists else { return 0 }
        return
          try Int.fetchOne(
            db, sql: "SELECT COUNT(*) FROM \(table) WHERE \(column) = ?", arguments: [id]) ?? 0
      }
      return try count("ai_changelog", "source_device_id")
        + count("sync_outbox", "device_id")
    }
  }

  /// Count of `tasks` rows with `id` at `path`, read through a fresh connection.
  private func taskCount(id: String, at path: String) throws -> Int {
    let queue = try DatabaseQueue(path: path)
    return try queue.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tasks WHERE id = ?", arguments: [id]) ?? 0
    }
  }

  /// A real `resetManagedStorage` bound into
  /// ``SwiftLorvexCoreService/afterWriteStateBarrierForTesting`` to interleave a
  /// cross-process factory reset into the identity-resolution → transaction
  /// window. `@unchecked Sendable`: the fire count is lock-guarded so the barrier
  /// is safe to invoke from the write funnel and read from the test.
  private final class WriteStateWindowReset: @unchecked Sendable {
    private let dbPath: String
    private let resetEveryTime: Bool
    private let lock = NSLock()
    private var fires = 0

    init(dbPath: String, resetEveryTime: Bool) {
      self.dbPath = dbPath
      self.resetEveryTime = resetEveryTime
    }

    var fireCount: Int {
      lock.lock()
      defer { lock.unlock() }
      return fires
    }

    func fire() {
      lock.lock()
      defer { lock.unlock() }
      if !resetEveryTime, fires > 0 { return }
      fires += 1
      _ = try? SwiftLorvexCoreService.resetManagedStorage(at: URL(fileURLWithPath: dbPath))
    }
  }

  /// Pauses a synchronous database body until the test releases it. All state is
  /// `NSCondition`-guarded; bounded waits turn coordination failures into normal
  /// assertions instead of hanging the suite.
  private final class BlockingOperationBarrier: @unchecked Sendable {
    private let condition = NSCondition()
    private var paused = false
    private var released = false

    func pause() {
      condition.lock()
      paused = true
      condition.broadcast()
      while !released {
        condition.wait()
      }
      condition.unlock()
    }

    func waitUntilPaused(timeout: TimeInterval = 10) -> Bool {
      condition.lock()
      defer { condition.unlock() }
      let deadline = Date().addingTimeInterval(timeout)
      while !paused {
        if !condition.wait(until: deadline) { return false }
      }
      return true
    }

    func release() {
      condition.lock()
      released = true
      condition.broadcast()
      condition.unlock()
    }
  }

  /// Observable lifecycle for the detached reset task used by the operation-
  /// lease tests.
  private final class BackgroundOperationState: @unchecked Sendable {
    private let condition = NSCondition()
    private var started = false
    private var completed = false

    func markStarted() {
      condition.lock()
      started = true
      condition.broadcast()
      condition.unlock()
    }

    func markCompleted() {
      condition.lock()
      completed = true
      condition.broadcast()
      condition.unlock()
    }

    func waitUntilStarted(timeout: TimeInterval = 10) -> Bool {
      wait(timeout: timeout) { started }
    }

    func waitUntilCompleted(timeout: TimeInterval) -> Bool {
      wait(timeout: timeout) { completed }
    }

    private func wait(timeout: TimeInterval, until predicate: () -> Bool) -> Bool {
      condition.lock()
      defer { condition.unlock() }
      let deadline = Date().addingTimeInterval(timeout)
      while !predicate() {
        if !condition.wait(until: deadline) { return false }
      }
      return true
    }
  }

  /// The persisted `sync_checkpoints.device_id` at `path`, or nil when the table
  /// or row is absent. Read through a fresh connection so it observes committed
  /// state independently of the service's own handle.
  private func deviceId(at path: String) throws -> String? {
    let queue = try DatabaseQueue(path: path)
    return try queue.read { db in
      let hasTable =
        try Bool.fetchOne(
          db, sql: "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE name = 'sync_checkpoints')")
        ?? false
      guard hasTable else { return nil }
      return try String.fetchOne(
        db, sql: "SELECT value FROM sync_checkpoints WHERE key = 'device_id'")
    }
  }
}

import Foundation
import GRDB
import LorvexDomain
import LorvexRuntime
import LorvexStore
import Testing

@testable import LorvexCore

/// Open-time install-identity reconciliation: the in-database `device_id` is
/// checked against a backup-excluded install marker beside the managed database,
/// so a restored/cloned DB rotates to a fresh identity instead of sharing the
/// origin install's — which would collapse two live devices into one sync-cursor
/// identity and silently drop LWW writes. All paths are injected temp dirs.
struct InstallIdentityReconcileTests {
  private func makeManagedEnv() throws -> (env: InMemoryDbLocatorEnv, dbPath: String, root: URL) {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("lorvex-install-identity-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let dataDir = root.appendingPathComponent("AppSupport").path
    let dbPath = dataDir + "/Lorvex/db.sqlite"
    let env = InMemoryDbLocatorEnv(dataDir: dataDir, homeDir: root.path, platform: .current)
    return (env, dbPath, root)
  }

  private func checkpoint(_ key: String, at path: String) throws -> String? {
    let queue = try DatabaseQueue(path: path)
    return try queue.read { db in
      let has =
        try Bool.fetchOne(
          db, sql: "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE name = 'sync_checkpoints')")
        ?? false
      guard has else { return nil }
      return try String.fetchOne(
        db, sql: "SELECT value FROM sync_checkpoints WHERE key = ?", arguments: [key])
    }
  }

  @Test
  func firstOpenMintsDeviceIdAndWritesMatchingMarker() async throws {
    let (env, dbPath, root) = try makeManagedEnv()
    defer { try? FileManager.default.removeItem(at: root) }
    try await SwiftLorvexCoreService.$dbLocatorEnvironmentOverride.withValue(env) {
      let service = SwiftLorvexCoreService(databasePath: nil)
      _ = try await service.setPreference(key: "theme", value: "system")
    }
    let dbId = try checkpoint("device_id", at: dbPath)
    let markerId = ManagedInstallIdentity.read(forDatabase: dbPath)
    let retired = try checkpoint("retired_device_ids", at: dbPath)
    #expect(dbId != nil, "the first write minted a device id")
    #expect(markerId == dbId, "the install marker records the minted device id")
    #expect(retired == nil, "no rotation happened on first open")
  }

  @Test
  func ordinaryReopenWithMatchingMarkerDoesNotRotate() async throws {
    let (env, dbPath, root) = try makeManagedEnv()
    defer { try? FileManager.default.removeItem(at: root) }
    try await SwiftLorvexCoreService.$dbLocatorEnvironmentOverride.withValue(env) {
      let first = SwiftLorvexCoreService(databasePath: nil)
      _ = try await first.setPreference(key: "theme", value: "system")
    }
    let idAfterFirst = try checkpoint("device_id", at: dbPath)
    try await SwiftLorvexCoreService.$dbLocatorEnvironmentOverride.withValue(env) {
      let second = SwiftLorvexCoreService(databasePath: nil)
      _ = try await second.setPreference(key: "theme", value: "dark")
    }
    let idAfterSecond = try checkpoint("device_id", at: dbPath)
    let retired = try checkpoint("retired_device_ids", at: dbPath)
    #expect(idAfterSecond == idAfterFirst, "an ordinary reopen (marker matches) keeps the device id")
    #expect(retired == nil, "no rotation on an ordinary reopen")
  }

  @Test
  func restoredDbWithAbsentMarkerRotatesAndReseeds() async throws {
    let (env, dbPath, root) = try makeManagedEnv()
    defer { try? FileManager.default.removeItem(at: root) }
    try await SwiftLorvexCoreService.$dbLocatorEnvironmentOverride.withValue(env) {
      let first = SwiftLorvexCoreService(databasePath: nil)
      _ = try await first.setPreference(key: "theme", value: "system")
    }
    let originalId = try #require(try checkpoint("device_id", at: dbPath))

    // Simulate a restore/clone: the DB (carrying originalId) is present, but the
    // backup-excluded install marker is not restored with it. A missing file is
    // genuine absence — the one read outcome that legitimately rotates.
    try FileManager.default.removeItem(
      atPath: ManagedInstallIdentity.markerPath(forDatabase: dbPath))
    #expect(ManagedInstallIdentity.readMarkerState(forDatabase: dbPath) == .absent)

    try await SwiftLorvexCoreService.$dbLocatorEnvironmentOverride.withValue(env) {
      let restored = SwiftLorvexCoreService(databasePath: nil)
      _ = try await restored.setPreference(key: "theme", value: "dark")
    }

    let rotatedId = try #require(try checkpoint("device_id", at: dbPath))
    let retired = try checkpoint("retired_device_ids", at: dbPath)
    let reseed = try checkpoint("reseed_required", at: dbPath)
    let markerId = ManagedInstallIdentity.read(forDatabase: dbPath)
    #expect(rotatedId != originalId, "a restored DB with an absent marker rotates to a fresh id")
    #expect(
      retired == originalId, "the pre-rotation id is retired so the HLC clock stays self-monotonic")
    #expect(reseed == "true", "rotation forces a reseed so the device re-publishes under the new id")
    #expect(
      markerId == rotatedId,
      "the marker is rewritten to the rotated id, so the next open is an ordinary reopen")
  }

  @Test
  func restoredDbRotatesBeforeItsFirstCloudTraversalIdentityRead() async throws {
    let (env, dbPath, root) = try makeManagedEnv()
    defer { try? FileManager.default.removeItem(at: root) }

    let originalDatabaseId = try await SwiftLorvexCoreService.$dbLocatorEnvironmentOverride
      .withValue(env) {
        let first = SwiftLorvexCoreService(databasePath: nil)
        _ = try await first.setPreference(key: "theme", value: "system")
        return try #require(try first.databaseInstanceIdentifier())
      }
    let originalDeviceId = try #require(try checkpoint("device_id", at: dbPath))

    // A restore carries the database identities but not this backup-excluded
    // marker. Cloud sync asks for databaseInstanceIdentifier() before any user
    // mutation, so that call itself must perform reconciliation.
    try FileManager.default.removeItem(
      atPath: ManagedInstallIdentity.markerPath(forDatabase: dbPath))
    #expect(ManagedInstallIdentity.readMarkerState(forDatabase: dbPath) == .absent)

    let returnedDatabaseId = try SwiftLorvexCoreService.$dbLocatorEnvironmentOverride
      .withValue(env) {
        let restored = SwiftLorvexCoreService(databasePath: nil)
        // Deliberately the restored service's first and only operation.
        return try #require(try restored.databaseInstanceIdentifier())
      }

    let rotatedDeviceId = try #require(try checkpoint("device_id", at: dbPath))
    let rotatedDatabaseId = try #require(try checkpoint("db_instance_id", at: dbPath))
    #expect(rotatedDeviceId != originalDeviceId)
    #expect(rotatedDatabaseId != originalDatabaseId)
    #expect(returnedDatabaseId == rotatedDatabaseId)
    #expect(try checkpoint("retired_device_ids", at: dbPath) == originalDeviceId)
    #expect(try checkpoint("reseed_required", at: dbPath) == "true")
    #expect(ManagedInstallIdentity.read(forDatabase: dbPath) == rotatedDeviceId)
  }

  /// A marker that is PRESENT but cannot be turned into an id this open (a
  /// transient I/O or permissions failure, or corrupt/partial bytes) is
  /// `unreadable`, NOT absent, so reconciliation keeps the in-DB identity rather
  /// than rotating. Pre-fix, `read`'s `try?` swallowed every failure to `nil`, and
  /// a present-but-unreadable marker was misread as the restore-dropped-marker
  /// signal — spuriously rotating a healthy install's device id, forcing a reseed,
  /// and re-pulling the zone.
  @Test
  func presentButUnreadableMarkerDoesNotRotate() async throws {
    let (env, dbPath, root) = try makeManagedEnv()
    defer { try? FileManager.default.removeItem(at: root) }
    try await SwiftLorvexCoreService.$dbLocatorEnvironmentOverride.withValue(env) {
      let first = SwiftLorvexCoreService(databasePath: nil)
      _ = try await first.setPreference(key: "theme", value: "system")
    }
    let originalId = try #require(try checkpoint("device_id", at: dbPath))
    #expect(ManagedInstallIdentity.readMarkerState(forDatabase: dbPath) == .present(originalId))

    // The marker file is present but its bytes carry no usable id. Distinct from a
    // restore, which drops the backup-excluded file entirely.
    try Data("}{ not json".utf8).write(
      to: URL(fileURLWithPath: ManagedInstallIdentity.markerPath(forDatabase: dbPath)),
      options: .atomic)
    #expect(ManagedInstallIdentity.readMarkerState(forDatabase: dbPath) == .unreadable)

    try await SwiftLorvexCoreService.$dbLocatorEnvironmentOverride.withValue(env) {
      let reopened = SwiftLorvexCoreService(databasePath: nil)
      _ = try await reopened.setPreference(key: "theme", value: "dark")
    }

    let idAfterReopen = try #require(try checkpoint("device_id", at: dbPath))
    let retired = try checkpoint("retired_device_ids", at: dbPath)
    let reseed = try checkpoint("reseed_required", at: dbPath)
    #expect(
      idAfterReopen == originalId,
      "a present-but-unreadable marker must not rotate the identity (only genuine absence does)")
    #expect(retired == nil, "no rotation, so no id is retired")
    #expect(reseed != "true", "no rotation, so no reseed is forced")
    // The unreadable marker is left untouched, not clobbered with a rewrite.
    #expect(ManagedInstallIdentity.readMarkerState(forDatabase: dbPath) == .unreadable)
  }

  @Test
  func secondProcessOverSameManagedPathDoesNotRotate() async throws {
    let (env, dbPath, root) = try makeManagedEnv()
    defer { try? FileManager.default.removeItem(at: root) }
    try await SwiftLorvexCoreService.$dbLocatorEnvironmentOverride.withValue(env) {
      // The app service and the MCP helper are two processes over ONE managed
      // path; both read the same marker, so the helper must not read the app's
      // freshly-written identity as a clone.
      let app = SwiftLorvexCoreService(databasePath: nil)
      let helper = SwiftLorvexCoreService(databasePath: nil, surface: .mcp)
      _ = try await app.setPreference(key: "theme", value: "system")
      let idAfterApp = try checkpoint("device_id", at: dbPath)
      _ = try await helper.setPreference(key: "language", value: "en")
      let idAfterHelper = try checkpoint("device_id", at: dbPath)
      let retired = try checkpoint("retired_device_ids", at: dbPath)
      #expect(idAfterHelper == idAfterApp, "the MCP helper shares the install marker; no rotation")
      #expect(retired == nil, "no spurious rotation")
    }
  }

  @Test
  func concurrentFirstOpensOverOneManagedPathResolveToOneDeviceIdWithoutRotation() async throws {
    let (env, dbPath, root) = try makeManagedEnv()
    defer { try? FileManager.default.removeItem(at: root) }
    // Two processes over ONE managed path mint identity for the FIRST time at the
    // same moment: the app service and the MCP helper. Their first writes run
    // concurrently, so both can reach install-identity reconciliation with the
    // device_id and marker still absent. Without the exclusive mint lock the loser
    // sees the winner's freshly stamped in-DB id against the marker it read as
    // absent and spuriously rotates, churning the device identity. The lock must
    // collapse them to ONE minted id with no rotation.
    //
    // Pre-seed the schema with a read-only open first (which opens the store but
    // mints no identity): it isolates the identity race from the unrelated hazard
    // of two connections applying the schema to a fresh WAL database at once, so
    // this test exercises only the identity contract, not schema-apply concurrency.
    try await SwiftLorvexCoreService.$dbLocatorEnvironmentOverride.withValue(env) {
      let seed = SwiftLorvexCoreService(databasePath: nil)
      _ = try await seed.getAllPreferences()
    }
    #expect(
      try checkpoint("device_id", at: dbPath) == nil,
      "the read-only seed open creates the schema without minting a device id")

    // In-process fidelity: the two services hold independent `LorvexStore`
    // connections and independent flock file descriptions on the shared managed
    // path, and `SwiftLorvexCoreService` is not an actor, so this exercises the
    // same cross-connection/cross-descriptor contention a real two-process mint
    // hits. What a single process cannot reproduce is OS-scheduler preemption of
    // one process mid-sequence; see the runtime-validation note in the fix.
    try await SwiftLorvexCoreService.$dbLocatorEnvironmentOverride.withValue(env) {
      let app = SwiftLorvexCoreService(databasePath: nil)
      let helper = SwiftLorvexCoreService(databasePath: nil, surface: .mcp)
      async let appWrite = app.setPreference(key: "theme", value: "system")
      async let helperWrite = helper.setPreference(key: "language", value: "en")
      _ = try await appWrite
      _ = try await helperWrite
    }
    let dbId = try #require(try checkpoint("device_id", at: dbPath))
    let markerId = ManagedInstallIdentity.read(forDatabase: dbPath)
    let retired = try checkpoint("retired_device_ids", at: dbPath)
    #expect(markerId == dbId, "the marker records the single minted device id")
    #expect(
      retired == nil,
      "concurrent first-opens serialize on the mint lock; the loser adopts the winner's id, no rotation")
  }

  /// A lock-guarded occupancy meter: records the peak number of holders observed
  /// inside a critical section at once. `@unchecked Sendable` because the `NSLock`
  /// serializes all access to the mutable fields.
  private final class Occupancy: @unchecked Sendable {
    private let lock = NSLock()
    private var current = 0
    private var observedPeak = 0
    func enter() {
      lock.lock(); defer { lock.unlock() }
      current += 1
      observedPeak = max(observedPeak, current)
    }
    func leave() {
      lock.lock(); defer { lock.unlock() }
      current -= 1
    }
    var peak: Int {
      lock.lock(); defer { lock.unlock() }
      return observedPeak
    }
  }

  @Test
  func mintLockSerializesConcurrentHolders() throws {
    let (_, dbPath, root) = try makeManagedEnv()
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(
      atPath: (dbPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)

    // A deterministic proof that `withMintLock` provides cross-descriptor mutual
    // exclusion (each call opens its own flock descriptor, so this is the same
    // exclusion two processes get). Two threads try to hold the lock at once, each
    // dwelling long enough to overlap the other's attempt; if the flock did not
    // serialize them the observed occupancy peak would reach 2.
    let occupancy = Occupancy()
    DispatchQueue.concurrentPerform(iterations: 2) { _ in
      // withMintLock is synchronous and its default 20s budget covers the sibling's
      // sub-second hold, so the loser waits rather than failing closed. A throw here
      // would only skip the occupancy probe, never inflate the peak, so the assert
      // stays sound.
      try? ManagedInstallIdentity.withMintLock(forDatabase: dbPath) {
        occupancy.enter()
        Thread.sleep(forTimeInterval: 0.1)
        occupancy.leave()
      }
    }
    #expect(occupancy.peak == 1, "the exclusive mint lock never lets two holders occupy the critical section")
  }

  /// The seed-scan property the rotation depends on: a version authored under a
  /// retired device's suffix is invisible to the new device's suffixes alone, but
  /// surfaces once the retired suffixes join the scan (as the rotated clock's do),
  /// so the rotated clock seeds past its own pre-rotation history rather than
  /// minting an HLC below it and losing its own edits under LWW.
  @Test
  func retiredSuffixSeedScanSurfacesPreRotationHistory() throws {
    let schemaURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // LorvexAppleTests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // apps/apple
      .deletingLastPathComponent()  // apps
      .deletingLastPathComponent()  // repo root
      .appendingPathComponent("schema/schema.sql")
    let schemaSQL = try String(contentsOf: schemaURL, encoding: .utf8)
    let store = try LorvexStore.openInMemory(schemaSQL: schemaSQL)

    let oldId = "old-device-aaaaaaaa"
    let newId = "new-device-bbbbbbbb"
    let oldSuffixes = HlcSurface.allSurfaces.map {
      DeviceIdentity.deviceIdToHlcSuffix(oldId, surface: $0)
    }
    let newSuffixes = HlcSurface.allSurfaces.map {
      DeviceIdentity.deviceIdToHlcSuffix(newId, surface: $0)
    }
    let oldVersion = "1800000000000_0001_\(oldSuffixes[0])"

    try store.writer.write { db in
      try db.execute(
        sql: "INSERT INTO preferences (key, value, version, updated_at) "
          + "VALUES ('seeded', '1', ?, '2026-01-01T00:00:00Z')",
        arguments: [oldVersion])
    }
    let underNew = try store.writer.read { db in
      try SwiftLorvexCoreService.HlcClock.maxLocalHlc(db, suffixes: newSuffixes)
    }
    let underOld = try store.writer.read { db in
      try SwiftLorvexCoreService.HlcClock.maxLocalHlc(db, suffixes: oldSuffixes)
    }
    #expect(underNew == nil, "the new device's own suffixes never see the pre-rotation history")
    #expect(
      underOld != nil, "including the retired suffixes surfaces it, so the rotated clock seeds above it")
  }
}

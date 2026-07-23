import Foundation
import LorvexDomain
import LorvexStore
import XCTest

@testable import LorvexCore

/// The runtime factory builds the on-disk Swift core for every in-process
/// surface (intents, Spotlight, notification actions, widgets, mobile). The only
/// storage injection is the unsandboxed dev `LORVEX_APPLE_DB_PATH` override; a
/// sandboxed process ignores it and resolves the managed store, and product
/// runtime environment never selects a preview/in-memory fixture.
final class LorvexCoreRuntimeFactoryTests: XCTestCase {
  override func setUp() {
    super.setUp()
    LorvexCoreRuntimeFactory.resetCachedServicesForTesting()
  }

  override func tearDown() {
    LorvexCoreRuntimeFactory.resetCachedServicesForTesting()
    super.tearDown()
  }

  func testDefaultEnvironmentBuildsTheManagedOnDiskService() throws {
    let core = try XCTUnwrap(
      LorvexCoreRuntimeFactory.make(environment: [:]) as? SwiftLorvexCoreService)
    // A nil path defers to DbLocator's managed resolution — no external path.
    XCTAssertNil(core.databasePath)
  }

  func testUnsandboxedDatabasePathOverrideIsHonored() throws {
    let tmp = NSTemporaryDirectory() + "lorvex-rtf-\(UUID().uuidString).db"
    let core = try XCTUnwrap(
      LorvexCoreRuntimeFactory.make(environment: ["LORVEX_APPLE_DB_PATH": tmp])
        as? SwiftLorvexCoreService)
    XCTAssertEqual(core.databasePath, tmp)
  }

  func testSandboxedProcessIgnoresDatabasePathOverride() throws {
    let tmp = NSTemporaryDirectory() + "lorvex-rtf-sandboxed-\(UUID().uuidString).db"
    let core = try XCTUnwrap(
      LorvexCoreRuntimeFactory.make(environment: [
        "APP_SANDBOX_CONTAINER_ID": "com.lorvex.apple.mcp-host",
        "LORVEX_APPLE_DB_PATH": tmp,
      ]) as? SwiftLorvexCoreService)
    // The sandbox guard drops the override; the surface resolves managed storage.
    XCTAssertNil(core.databasePath)
  }

  func testRuntimeModeEnvironmentValueNeverSelectsAFixture() throws {
    // `LORVEX_APPLE_CORE` is not a factory input: any value falls through to the
    // normal on-disk resolution; tests construct fixtures directly.
    for mode in ["inmemory", "preview", "swift"] {
      let core = LorvexCoreRuntimeFactory.make(environment: ["LORVEX_APPLE_CORE": mode])
      XCTAssertTrue(
        core is SwiftLorvexCoreService, "LORVEX_APPLE_CORE=\(mode) must not select a fixture")
    }
  }

  func testAppIntentSurfaceWritesUnderItsHlcSuffix() async throws {
    let tmp = NSTemporaryDirectory() + "lorvex-rtf-selected-\(UUID().uuidString).db"
    defer {
      for candidate in [tmp, "\(tmp)-wal", "\(tmp)-shm"] {
        try? FileManager.default.removeItem(atPath: candidate)
      }
    }
    let env = ["LORVEX_APPLE_DB_PATH": tmp]

    let core = LorvexCoreRuntimeFactory.makeForAppIntent(environment: env)
    let task = try await core.createTask(title: "Selected location", notes: "")
    let reader = SwiftLorvexCoreService(databasePath: tmp)
    let version = try XCTUnwrap(reader.read { db in
      try String.fetchOne(db, sql: "SELECT version FROM tasks WHERE id = ?", arguments: [task.id])
    })
    let suffix = try Hlc.parse(version).deviceSuffix
    let deviceID = try XCTUnwrap(reader.read { db in
      try String.fetchOne(db, sql: "SELECT value FROM sync_checkpoints WHERE key = 'device_id'")
    })
    XCTAssertEqual(
      suffix,
      DeviceIdentity.deviceIdToHlcSuffix(deviceID, surface: .appIntent))
  }

  func testFactorySurfacesDeclareUserProvenance() async throws {
    let tmp = NSTemporaryDirectory() + "lorvex-rtf-provenance-\(UUID().uuidString).db"
    defer {
      for candidate in [tmp, "\(tmp)-wal", "\(tmp)-shm"] {
        try? FileManager.default.removeItem(atPath: candidate)
      }
    }
    let env = ["LORVEX_APPLE_DB_PATH": tmp]

    // Every human surface the factory serves declares `.user`, so a write with no
    // ambient binding records `user` — not the fail-closed `unattributed`, and
    // not the assistant surface's `assistant`.
    let core = LorvexCoreRuntimeFactory.makeForAppIntent(environment: env)
    let task = try await core.createTask(title: "Human surface", notes: "")
    let reader = SwiftLorvexCoreService(databasePath: tmp)
    let initiatedBy = try XCTUnwrap(reader.read { db in
      try String.fetchOne(
        db,
        sql: "SELECT initiated_by FROM ai_changelog WHERE entity_id = ? ORDER BY timestamp DESC",
        arguments: [task.id])
    })
    XCTAssertEqual(initiatedBy, SwiftLorvexCoreService.ChangelogInitiator.user)
  }

  func testRepeatedSameSurfaceCallsReuseOneServiceAndClock() throws {
    let env = [
      "LORVEX_APPLE_DB_PATH": NSTemporaryDirectory() + "lorvex-rtf-cache-\(UUID().uuidString).db"
    ]
    let first = try XCTUnwrap(
      LorvexCoreRuntimeFactory.makeForAppIntent(environment: env) as? SwiftLorvexCoreService)
    let second = try XCTUnwrap(
      LorvexCoreRuntimeFactory.makeForAppIntent(environment: env) as? SwiftLorvexCoreService)

    // Same instance → one service, hence one HLC clock and one observer
    // registration per surface for the whole process.
    XCTAssertTrue(first === second)
  }

  func testDistinctSurfacesGetDistinctServices() throws {
    let env = [
      "LORVEX_APPLE_DB_PATH": NSTemporaryDirectory() + "lorvex-rtf-surfaces-\(UUID().uuidString).db"
    ]
    let intent = try XCTUnwrap(
      LorvexCoreRuntimeFactory.makeForAppIntent(environment: env) as? SwiftLorvexCoreService)
    let widget = try XCTUnwrap(
      LorvexCoreRuntimeFactory.makeForWidget(environment: env) as? SwiftLorvexCoreService)

    // One clock per surface: the surfaces mint under distinct HLC suffixes, so
    // they must not share a service.
    XCTAssertFalse(intent === widget)
  }

  func testDatabaseOverrideBranchIsNeverCached() throws {
    let tmp = NSTemporaryDirectory() + "lorvex-rtf-override-\(UUID().uuidString).db"
    try LorvexCoreRuntimeFactory.$databaseOverride.withValue(tmp) {
      let first = try XCTUnwrap(
        LorvexCoreRuntimeFactory.makeForAppIntent(environment: [:]) as? SwiftLorvexCoreService)
      let second = try XCTUnwrap(
        LorvexCoreRuntimeFactory.makeForAppIntent(environment: [:]) as? SwiftLorvexCoreService)
      // The test-only override hands out fresh services so per-task test
      // isolation holds.
      XCTAssertFalse(first === second)
      XCTAssertEqual(first.databasePath, tmp)
    }
  }

  func testInvalidateCachedServicesYieldsFreshInstancesForCutover() throws {
    let env = [
      "LORVEX_APPLE_DB_PATH": NSTemporaryDirectory()
        + "lorvex-rtf-invalidate-\(UUID().uuidString).db"
    ]
    let first = try XCTUnwrap(
      LorvexCoreRuntimeFactory.makeForAppIntent(environment: env) as? SwiftLorvexCoreService)
    let second = try XCTUnwrap(
      LorvexCoreRuntimeFactory.makeForAppIntent(environment: env) as? SwiftLorvexCoreService)
    XCTAssertTrue(first === second)

    // The factory-reset cutover evicts (and closes) every cached per-surface
    // service so no cached connection keeps writing the deleted database file.
    LorvexCoreRuntimeFactory.invalidateCachedServices()

    let third = try XCTUnwrap(
      LorvexCoreRuntimeFactory.makeForAppIntent(environment: env) as? SwiftLorvexCoreService)
    XCTAssertFalse(first === third)
  }
}

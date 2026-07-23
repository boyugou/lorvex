import Foundation
import LorvexRuntime
import Testing

@testable import LorvexApple
@testable import LorvexCore
@testable import LorvexMCPHost

/// Shipping storage invariant: every resolution plane — the main app, the MCP
/// helper, and every in-process system surface — opens the single Lorvex-managed
/// App Group database. There is no runtime external-database selection. The only
/// injection is the unsandboxed dev `LORVEX_APPLE_DB_PATH` override, resolved
/// directly by the core (never routed through AppSettings/UserDefaults or a
/// security-scoped bookmark); a sandboxed process ignores it entirely.
@MainActor
@Suite("Every surface opens the managed store")
struct ManagedStorageInvariantTests {
  @Test("the app core factory always builds the managed-store service")
  func appCoreFactoryIsManaged() throws {
    let service = try #require(AppCoreFactory.make() as? SwiftLorvexCoreService)
    // A nil constructor path defers to DbLocator's managed resolution; no
    // external path or bookmark is ever injected here.
    #expect(service.databasePath == nil)
  }

  @Test("app, helper, and every system surface resolve the same managed store")
  func allPlanesResolveTheSameManagedStore() throws {
    LorvexCoreRuntimeFactory.resetCachedServicesForTesting()
    defer { LorvexCoreRuntimeFactory.resetCachedServicesForTesting() }

    // The managed store path is a pure static resolution, shared by every plane
    // that passes a nil path.
    let managedPath = try SwiftLorvexCoreService.managedDatabasePath()
    #expect(!managedPath.isEmpty)

    // Main app surface.
    let app = try #require(AppCoreFactory.make() as? SwiftLorvexCoreService)
    #expect(app.databasePath == nil)

    // MCP helper: no override in the environment resolves the managed store.
    let helper = try CoreBridgeConfiguration(environment: [:])
    #expect(helper.databasePath == nil)

    // In-process system surfaces. No location/service provider exists to install,
    // so each falls through to the default managed resolution.
    let surfaces: [(String, any LorvexCoreServicing)] = [
      ("appIntent", LorvexCoreRuntimeFactory.makeForAppIntent(environment: [:])),
      ("widget", LorvexCoreRuntimeFactory.makeForWidget(environment: [:])),
      ("notification", LorvexCoreRuntimeFactory.makeForNotification(environment: [:])),
      ("mobile", LorvexCoreRuntimeFactory.makeForMobile(environment: [:])),
    ]
    for (name, service) in surfaces {
      let svc = try #require(
        service as? SwiftLorvexCoreService, "\(name) should build the on-disk service")
      #expect(svc.databasePath == nil, "\(name) must resolve managed storage")
    }

    #expect(try SwiftLorvexCoreService.managedDatabasePath() == managedPath)
  }

  @Test("a sandboxed process ignores a readable override and resolves managed")
  func sandboxedProcessIgnoresReadableOverride() throws {
    LorvexCoreRuntimeFactory.resetCachedServicesForTesting()
    defer { LorvexCoreRuntimeFactory.resetCachedServicesForTesting() }

    let readable =
      NSTemporaryDirectory() + "lorvex-managed-invariant-sandboxed-\(UUID().uuidString).db"
    FileManager.default.createFile(atPath: readable, contents: Data())
    defer { try? FileManager.default.removeItem(atPath: readable) }
    #expect(FileManager.default.isReadableFile(atPath: readable))

    let sandboxEnv = [
      "APP_SANDBOX_CONTAINER_ID": "com.lorvex.apple.mcp-host",
      "LORVEX_APPLE_DB_PATH": readable,
    ]
    // The MCP helper and the shared runtime factory both drop the override under
    // the sandbox, regardless of readability.
    let helper = try CoreBridgeConfiguration(environment: sandboxEnv)
    #expect(helper.databasePath == nil)

    let factory = try #require(
      LorvexCoreRuntimeFactory.make(environment: sandboxEnv) as? SwiftLorvexCoreService)
    #expect(factory.databasePath == nil)
  }

  @Test("a sandboxed build whose App Group container is unavailable fails closed")
  func sandboxedWithoutAppGroupFailsClosed() async throws {
    // Sandboxed (dev override off) with no resolvable App Group container: the
    // container URL came back nil (a missing/misconfigured entitlement). The
    // managed store's identity is unknown, so resolution and open must fail
    // closed — never fall back to a per-process directory that would split the
    // store across the app, MCP helper, and extensions.
    let env = InMemoryDbLocatorEnv(
      dbPathEnvOverride: NSTemporaryDirectory() + "should-not-be-used.sqlite",
      dataDir: NSTemporaryDirectory() + "should-not-be-used-datadir",
      homeDir: NSTemporaryDirectory() + "should-not-be-used-home",
      platform: .current,
      appleAppGroupContainerPath: nil,
      allowsDbPathOverride: false,
      appleAppGroupIdentifier: LorvexProductMetadata.appGroupIdentifier)

    await SwiftLorvexCoreService.$dbLocatorEnvironmentOverride.withValue(env) {
      // The managed-path accessor fails closed, naming the App Group.
      #expect(throws: DbLocationError.self) {
        _ = try SwiftLorvexCoreService.managedDatabasePath()
      }
      // Opening a managed service (nil path) fails closed on first store use —
      // no per-process fallback file is created or written.
      let service = SwiftLorvexCoreService(databasePath: nil)
      await #expect(throws: DbLocationError.self) {
        _ = try await service.setPreference(key: "theme", value: "system")
      }
    }
  }

  @Test("a sandboxed build resolves the App Group container when it is available")
  func sandboxedWithAppGroupResolvesContainer() async throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("lorvex-appgroup-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let appGroup = root.appendingPathComponent("GroupContainer", isDirectory: true).path
    let expected = appGroup + "/Lorvex/db.sqlite"

    let env = InMemoryDbLocatorEnv(
      dataDir: root.appendingPathComponent("AppSupport").path,
      homeDir: root.path,
      platform: .current,
      appleAppGroupContainerPath: appGroup,
      allowsDbPathOverride: false,
      appleAppGroupIdentifier: LorvexProductMetadata.appGroupIdentifier)

    try await SwiftLorvexCoreService.$dbLocatorEnvironmentOverride.withValue(env) {
      #expect(try SwiftLorvexCoreService.managedDatabasePath() == expected)
      // The store opens against the shared container path, not a fallback.
      let service = SwiftLorvexCoreService(databasePath: nil)
      _ = try await service.setPreference(key: "theme", value: "system")
      #expect(FileManager.default.fileExists(atPath: expected))
    }
  }

  @Test("the unsandboxed dev override is honored directly and never persisted")
  func devEnvOverrideIsHonoredAndNeverPersisted() throws {
    LorvexCoreRuntimeFactory.resetCachedServicesForTesting()
    defer { LorvexCoreRuntimeFactory.resetCachedServicesForTesting() }
    let tmp = NSTemporaryDirectory() + "lorvex-managed-invariant-\(UUID().uuidString).db"

    // The override is resolved directly by the factory (unsandboxed) — not via
    // AppSettings, a UserDefaults key, or a bookmark.
    let service = try #require(
      LorvexCoreRuntimeFactory.make(environment: ["LORVEX_APPLE_DB_PATH": tmp])
        as? SwiftLorvexCoreService)
    #expect(service.databasePath == tmp)

    // The override lives only in the process environment: a settings store over a
    // fresh UserDefaults suite with an empty environment sees no override, so
    // nothing about it is persisted.
    let suiteName = "ManagedStorageInvariant-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let settings = AppSettingsStore(defaults: defaults, environment: [:])
    #expect(!settings.usesEnvironmentDatabasePath)
  }
}

import Foundation
import Testing

@testable import LorvexMCPHost

/// Coverage for the MCP host's database resolution. The shipping store is the
/// single Lorvex-managed App Group database (a nil `databasePath`); only an
/// unsandboxed dev `LORVEX_APPLE_DB_PATH` override selects a different file. A
/// sandboxed helper ignores any override entirely — inherited env var or
/// hand-written config alike — and resolves the managed store.
struct CoreBridgeConfigurationTests {
  @Test("an empty environment resolves the managed store")
  func emptyEnvironmentResolvesManaged() throws {
    let configuration = try CoreBridgeConfiguration(environment: [:])
    #expect(configuration.databasePath == nil)
  }

  @Test("an explicit unsandboxed dev database path is honored")
  func acceptsExplicitDevEnvironmentPath() throws {
    let configuration = try CoreBridgeConfiguration(environment: [
      "LORVEX_APPLE_DB_PATH": "/tmp/dev-runtime.db"
    ])
    #expect(configuration.databasePath == "/tmp/dev-runtime.db")
  }

  @Test("a sandboxed helper resolves the managed store even for a readable override path")
  func sandboxedHelperResolvesManagedForReadableOverridePath() throws {
    let databaseURL = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("lorvex sandboxed-readable \(UUID().uuidString).db")
    FileManager.default.createFile(atPath: databaseURL.path, contents: Data())
    defer { try? FileManager.default.removeItem(at: databaseURL) }

    let configuration = try CoreBridgeConfiguration(environment: [
      "APP_SANDBOX_CONTAINER_ID": "com.lorvex.apple.mcp-host",
      "LORVEX_APPLE_DB_PATH": databaseURL.path,
    ])
    // The override is a readable, existing file, yet the sandboxed helper still
    // ignores it and serves the managed store: the sandbox guard does not gate
    // on readability.
    #expect(configuration.databasePath == nil)
  }

  @Test("the production registry ignores a legacy runtime-switch environment value")
  func productionRegistryIgnoresLegacyPreviewRuntimeSwitch() async throws {
    let registry = try ToolRegistry.production(environment: [
      "LORVEX_APPLE_CORE": "preview"
    ])
    // The legacy switch is not consulted: production still builds a real managed
    // core bridge — its durable idempotency backend is present (as it is for any
    // SwiftLorvexCoreService), so it is a functioning core, not an empty stub.
    #expect(await registry.coreBridge.mcpIdempotency != nil)
  }
}

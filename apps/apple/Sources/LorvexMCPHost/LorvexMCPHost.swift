import Foundation
import LorvexCore
import MCP

@main
struct LorvexMCPHost {
  static func main() async throws {
    // This process is the product's primary write interface but is invisible to
    // the running app. Broadcast a cross-process change signal after each write
    // so the app refreshes without a manual ⌘R.
    DatabaseChangeSignal.broadcastsOnWrite = true

    let environment = ProcessInfo.processInfo.environment
    if environment["LORVEX_MCP_PROBE"] == "1" {
      try await runProbe(environment: environment)
      return
    }
    let registry = try ToolRegistry.production(environment: environment)

    let server = Server(
      name: LorvexProductMetadata.mcpServerName,
      version: LorvexProductMetadata.marketingVersion,
      title: LorvexProductMetadata.appDisplayName,
      instructions:
        "Apple-native Lorvex MCP host. Uses the app's pure-Swift core and opens the single Lorvex-managed App Group database (cross-device sync is CloudKit-only).",
      capabilities: .init(tools: .init(listChanged: false))
    )

    await server.withMethodHandler(ListTools.self) { _ in
      ListTools.Result(tools: ToolRegistry.listTools())
    }

    await server.withMethodHandler(CallTool.self) { params in
      try await registry.call(params)
    }

    // Sweep expired idempotency rows on boot. Runs once per MCP child process.
    if let idempotency = registry.coreBridge.mcpIdempotency {
      try? await idempotency.sweepMcpIdempotency()
    }

    let transport = StdioTransport()
    try await server.start(transport: transport)

    // Await the server's receive loop instead of sleeping forever: the loop ends
    // when the stdio transport reaches end-of-stream (the client closes stdin),
    // so the host exits cleanly and releases its DB connection rather than
    // lingering as a zombie until SIGKILL.
    await server.waitUntilCompleted()
  }

  /// The `LORVEX_MCP_PROBE=1` self-check the app's MCP settings panel runs
  /// against the bundled helper. Walks the exact configuration + store-open
  /// path a real MCP client's first tool call would take — resolving
  /// `environment` into a `CoreBridgeConfiguration` and then opening the
  /// resulting store with a real read — so a denied App Group, an unreadable
  /// path, or any other open-time failure surfaces here instead of behind an
  /// unconditional "ready". `verifyBundledSchemaResources` additionally catches
  /// a packaging defect (missing/mismatched schema or checksum resources) that a
  /// store open alone would not.
  static func runProbe(environment: [String: String]) async throws {
    try SwiftLorvexCoreService.verifyBundledSchemaResources()
    guard ToolRegistry.listTools().contains(where: { $0.name == "get_overview" }) else {
      throw MCPConfigurationError.databaseUnavailable
    }
    // Probe the exact path a real client's first call takes: build the real
    // configuration and open the store, so a denied App Group or unreachable
    // path fails here instead of showing a false green.
    let registry = try ToolRegistry.production(environment: environment)
    _ = try await registry.coreBridge.service.getOverviewCompact()
  }
}

actor ToolRegistry {
  let coreBridge: CoreBridgeClient
  let mcpIdempotency: (any LorvexMcpIdempotencyServicing)?
  let idempotencyClaimWaitPolicy: IdempotencyClaimWaitPolicy
  let idempotencyCache = IdempotencyCache()
  let idempotencyInFlight = IdempotencyInFlightClaims()

  /// Every registry dispatches against a real core. Production hosts build one
  /// via ``production(environment:)`` (fails fast on a broken DB path); tests
  /// inject a bridge over an in-memory `SwiftLorvexCoreService`.
  init(coreBridge: CoreBridgeClient) {
    self.coreBridge = coreBridge
    self.mcpIdempotency = coreBridge.mcpIdempotency
    self.idempotencyClaimWaitPolicy = .production
  }

  /// Test/injected-backend seam. Passing `nil` deliberately models a backend
  /// without durable idempotency; the one-argument production initializer above
  /// always adopts the core's durable service when available.
  init(
    coreBridge: CoreBridgeClient,
    mcpIdempotency: (any LorvexMcpIdempotencyServicing)?,
    idempotencyClaimWaitPolicy: IdempotencyClaimWaitPolicy = .production
  ) {
    self.coreBridge = coreBridge
    self.mcpIdempotency = mcpIdempotency
    self.idempotencyClaimWaitPolicy = idempotencyClaimWaitPolicy
  }

  static func production(environment: [String: String]) throws -> ToolRegistry {
    let configuration = try CoreBridgeConfiguration(environment: environment)
    return ToolRegistry(
      coreBridge: CoreBridgeClient(databasePath: configuration.databasePath))
  }
}

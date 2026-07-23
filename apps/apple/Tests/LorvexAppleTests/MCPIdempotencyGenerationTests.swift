import MCP
import Testing

@testable import LorvexCore
@testable import LorvexMCPHost

@Suite("MCP durable idempotency — generation authority")
struct MCPIdempotencyGenerationTests {
  private func taskCount(_ registry: ToolRegistry, titled title: String) async throws -> Int {
    let result = try await mcpRegistryCall(
      registry, tool: "list_tasks", arguments: ["text": .string(title)])
    let tasks = result.structuredContent?.objectValue?["tasks"]?.arrayValue ?? []
    return tasks.filter {
      $0.objectValue?["title"]?.stringValue?.contains(title) == true
    }.count
  }

  @Test("durable claim wait covers cutover and SQLite maintenance contention")
  func durableClaimWaitCoversLegalMaintenanceContention() {
    // Managed-storage lock acquisition may legally wait 20 seconds and the
    // following BEGIN IMMEDIATE has a 5-second SQLite busy timeout. Keep one
    // additional second for scheduling between the mutation commit and finalize.
    #expect(IdempotencyClaimWaitPolicy.production.nominalBudgetMilliseconds >= 26_000)
  }

  @Test("transaction-claim polling accepts a response finalized on its last poll")
  func transactionClaimPollingAcceptsLastPoll() async throws {
    let fixture = try mcpInMemoryRegistryWithService()
    let response = IdempotencyCache.CachedResult(
      textContent: "Already created.",
      structuredContent: Value.object(["id": .string("finalized-id")])
    ).durablePayload()
    let durable = EventuallyFinalizedIdempotencyBackend(
      claimLookupsBeforeResponse: 3, responsePayload: response)
    let registry = ToolRegistry(
      coreBridge: CoreBridgeClient(databasePath: nil, service: fixture.service),
      mcpIdempotency: durable,
      idempotencyClaimWaitPolicy: IdempotencyClaimWaitPolicy(
        pollIntervalMilliseconds: 1, maximumPollCount: 3))

    let result = try await mcpRegistryCall(
      registry, tool: "create_task",
      arguments: [
        "title": .string("Claim waiter boundary"),
        "idempotency_key": .string("key-claim-wait-boundary"),
      ])

    #expect(result.isError != true)
    #expect(result.structuredContent?.objectValue?["id"]?.stringValue == "finalized-id")
    #expect(await durable.lookupCallCount() == 4)
  }

  @Test("a failed durable finalize never publishes a process-cache success")
  func failedDurableFinalizeDoesNotPublishProcessCache() async throws {
    let fixture = try mcpInMemoryRegistryWithService()
    let durable = FinalizeFailingIdempotencyBackend(base: fixture.service)
    let registry = ToolRegistry(
      coreBridge: CoreBridgeClient(databasePath: nil, service: fixture.service),
      mcpIdempotency: durable)
    let args: [String: Value] = [
      "title": .string("Finalize failure must not cache"),
      "idempotency_key": .string("key-finalize-failure"),
    ]
    let checksum = IdempotencyCache.checksum(for: args)

    let result = try await mcpRegistryCall(
      registry, tool: "create_task", arguments: args)

    #expect(result.isError == true)
    #expect(await durable.finalizeCallCount() == 1)
    let cache = await registry.idempotencyCache
    let cached = try await cache.lookup(
      tool: "create_task", key: "key-finalize-failure", checksum: checksum)
    if cached != nil {
      Issue.record(
        "A response whose durable finalize failed was published to the process cache")
    }
  }

  @Test("a completed durable call never replays process cache across a generation reset")
  func completedDurableCallDoesNotReplayAcrossGenerationReset() async throws {
    let fixture = try mcpInMemoryRegistryWithService()
    let durable = ResettableIdempotencyBackend(base: fixture.service)
    let registry = ToolRegistry(
      coreBridge: CoreBridgeClient(databasePath: nil, service: fixture.service),
      mcpIdempotency: durable)
    let args: [String: Value] = [
      "title": .string("Generation-scoped replay"),
      "idempotency_key": .string("key-generation-reset"),
    ]

    let first = try await mcpRegistryCall(
      registry, tool: "create_task", arguments: args)
    #expect(first.isError != true)
    let lookupsBeforeReset = await durable.lookupCallCount()

    await durable.simulateGenerationReset()
    let replay = try await mcpRegistryCall(
      registry, tool: "create_task", arguments: args)

    #expect(replay.isError == true)
    #expect(
      await durable.lookupCallCount() > lookupsBeforeReset,
      "The post-reset call must consult the new durable generation")
  }

  @Test("a backend without durable idempotency keeps same-process replay")
  func backendWithoutDurableIdempotencyKeepsProcessReplay() async throws {
    let fixture = try mcpInMemoryRegistryWithService()
    let registry = ToolRegistry(
      coreBridge: CoreBridgeClient(databasePath: nil, service: fixture.service),
      mcpIdempotency: nil)
    let title = "Process-only idempotency"
    let args: [String: Value] = [
      "title": .string(title),
      "idempotency_key": .string("key-process-only"),
    ]

    let first = try await mcpRegistryCall(
      registry, tool: "create_task", arguments: args)
    let replay = try await mcpRegistryCall(
      registry, tool: "create_task", arguments: args)

    #expect(first.isError != true)
    #expect(replay.isError != true)
    #expect(
      replay.structuredContent?.objectValue?["id"]?.stringValue
        == first.structuredContent?.objectValue?["id"]?.stringValue)
    #expect(try await taskCount(registry, titled: title) == 1)
  }
}

private enum ForcedFinalizeFailure: Error {
  case resetDuringFinalize
}

private actor FinalizeFailingIdempotencyBackend: LorvexMcpIdempotencyServicing {
  private let base: any LorvexMcpIdempotencyServicing
  private var finalizeCalls = 0

  init(base: any LorvexMcpIdempotencyServicing) {
    self.base = base
  }

  func lookupMcpIdempotency(
    toolName: String, key: String, checksum: String
  ) async throws -> McpIdempotencyOutcome {
    try await base.lookupMcpIdempotency(
      toolName: toolName, key: key, checksum: checksum)
  }

  func finalizeMcpIdempotency(
    toolName: String, key: String, checksum: String, claimToken: String,
    payload: String
  ) async throws {
    finalizeCalls += 1
    throw ForcedFinalizeFailure.resetDuringFinalize
  }

  func sweepMcpIdempotency() async throws {
    try await base.sweepMcpIdempotency()
  }

  func finalizeCallCount() -> Int {
    finalizeCalls
  }
}

private enum SimulatedGenerationReset: Error {
  case durableAuthorityChanged
}

private actor ResettableIdempotencyBackend: LorvexMcpIdempotencyServicing {
  private let base: any LorvexMcpIdempotencyServicing
  private var generationWasReset = false
  private var lookupCalls = 0

  init(base: any LorvexMcpIdempotencyServicing) {
    self.base = base
  }

  func lookupMcpIdempotency(
    toolName: String, key: String, checksum: String
  ) async throws -> McpIdempotencyOutcome {
    lookupCalls += 1
    guard !generationWasReset else {
      throw SimulatedGenerationReset.durableAuthorityChanged
    }
    return try await base.lookupMcpIdempotency(
      toolName: toolName, key: key, checksum: checksum)
  }

  func finalizeMcpIdempotency(
    toolName: String, key: String, checksum: String, claimToken: String,
    payload: String
  ) async throws {
    guard !generationWasReset else {
      throw SimulatedGenerationReset.durableAuthorityChanged
    }
    try await base.finalizeMcpIdempotency(
      toolName: toolName, key: key, checksum: checksum,
      claimToken: claimToken, payload: payload)
  }

  func sweepMcpIdempotency() async throws {
    try await base.sweepMcpIdempotency()
  }

  func simulateGenerationReset() {
    generationWasReset = true
  }

  func lookupCallCount() -> Int {
    lookupCalls
  }
}

private actor EventuallyFinalizedIdempotencyBackend: LorvexMcpIdempotencyServicing {
  private let claimLookupsBeforeResponse: Int
  private let responsePayload: String
  private var lookupCalls = 0

  init(claimLookupsBeforeResponse: Int, responsePayload: String) {
    self.claimLookupsBeforeResponse = claimLookupsBeforeResponse
    self.responsePayload = responsePayload
  }

  func lookupMcpIdempotency(
    toolName: String, key: String, checksum: String
  ) -> McpIdempotencyOutcome {
    lookupCalls += 1
    if lookupCalls <= claimLookupsBeforeResponse {
      return .hit(
        responsePayload: McpIdempotencyDurablePayload.transactionClaim(token: "owner-token"))
    }
    return .hit(responsePayload: responsePayload)
  }

  func finalizeMcpIdempotency(
    toolName: String, key: String, checksum: String, claimToken: String,
    payload: String
  ) throws {}

  func sweepMcpIdempotency() throws {}

  func lookupCallCount() -> Int {
    lookupCalls
  }
}

import Foundation
import LorvexCore
import LorvexDomain
import MCP

struct IdempotencyClaimWaitPolicy: Sendable {
  let pollIntervalMilliseconds: Int64
  let maximumPollCount: Int

  var nominalBudgetMilliseconds: Int64 {
    pollIntervalMilliseconds * Int64(maximumPollCount)
  }

  /// Cover the complete legal finalize path after the mutation transaction:
  /// managed-storage lock acquisition may wait 20 seconds, then SQLite's
  /// `BEGIN IMMEDIATE` busy handler may wait 5 seconds. One additional second
  /// absorbs scheduling between commit, finalizer, and a competing host's poll.
  static let production = IdempotencyClaimWaitPolicy(
    pollIntervalMilliseconds: 25, maximumPollCount: 1_040)
}

extension ToolRegistry {
  /// Compatibility surface for tests and diagnostics. The membership itself is
  /// derived from each tool's typed definition rather than maintained here.
  static var idempotentWriteTools: Set<String> {
    ToolDefinitionRegistry.idempotentWriteToolNames
  }

  /// Tool-call entry point. Wraps the routing body in a top-level boundary so a
  /// domain error thrown by any handler (e.g. a core validation like "cannot
  /// delete a list with assigned tasks") becomes a clean tool error result
  /// instead of escaping to the MCP framework as a `-32603` internal error. The
  /// individual handlers still catch the error types they can describe richly;
  /// this is the catch-all for anything they miss.
  func call(_ params: CallTool.Parameters) async throws -> CallTool.Result {
    // Bind the tool name for the duration of the call so the core's changelog
    // write surface can stamp `ai_changelog.mcp_tool` without threading the
    // name through every handler. Propagates across `await` to the core's
    // `writeChangelogRow`. Binding `currentInitiator` to `assistant` in the same
    // scope attributes every MCP-driven write to the assistant surface. The MCP
    // host's core has no `writeInitiatorDefault`, so a new write path that
    // skipped this binding would record the fail-closed `unattributed` sentinel
    // rather than a silent human `user`; direct human surfaces declare `.user`
    // through their service's `writeInitiatorDefault` instead.
    try await SwiftLorvexCoreService.$currentMCPTool.withValue(params.name) {
      try await SwiftLorvexCoreService.$currentInitiator.withValue(
        SwiftLorvexCoreService.ChangelogInitiator.assistant
      ) {
        do {
          return try await routeWithIdempotency(params)
        } catch is CancellationError {
          throw CancellationError()
        } catch {
          return Self.errorResult(
            code: Self.errorCode(for: error),
            message: Self.errorMessage(for: error),
            toolName: params.name)
        }
      }
    }
  }

  /// Generous ceiling for a client-supplied idempotency key. Real keys are
  /// UUIDs or short request hashes; the cap only bounds the durable PK column
  /// and the checksummed argument payload against a runaway value.
  static let maxIdempotencyKeyBytes = 256

  private func routeWithIdempotency(_ params: CallTool.Parameters) async throws -> CallTool.Result {
    let arguments = params.arguments ?? [:]
    guard let definition = ToolDefinitionRegistry.byName[params.name] else {
      return ToolResponseFencing.userControlledContent.apply(
        to: unknownToolResult(named: params.name)
      )
    }
    // A present wrong-typed key must reject, never silently run unkeyed: the
    // caller believed the mutation was replay-protected. The length cap bounds
    // the PK column and the checksummed argument payload.
    let key: String?
    if definition.participatesInIdempotency {
      key = try StrictScalarArguments.optionalString(
        arguments["idempotency_key"], field: "idempotency_key")
      if let key, key.utf8.count > Self.maxIdempotencyKeyBytes {
        throw ValidationError.tooLong(
          field: "idempotency_key", max: Self.maxIdempotencyKeyBytes, actual: key.utf8.count)
      }
    } else {
      key = nil
    }
    guard let key, !key.isEmpty else {
      return try await definition.call(on: self, arguments: arguments)
    }

    let checksum = IdempotencyCache.checksum(for: arguments)
    // An unencodable payload yields an empty checksum, which is not a usable
    // dedup identity: a second, *different* unencodable payload under the same
    // key would checksum-match ("" == "") and wrongly replay the first result
    // (Core Design Rule 5). Treat it as never-hit / never-store — run the write
    // live exactly as an unkeyed call, consulting and populating neither the
    // in-memory nor the durable idempotency cache.
    guard !checksum.isEmpty else {
      return try await definition.call(on: self, arguments: arguments)
    }
    // A durable backend is scoped to the current managed-store generation and
    // remains the replay authority for every call. A process-cache hit cannot
    // prove that the same generation is still active: factory reset or storage
    // cutover may have replaced the database after the response was cached.
    // Cache only the fallback configuration that has no durable backend at all.
    let usesProcessCache = mcpIdempotency == nil
    while true {
      if usesProcessCache {
        do {
          if let cached = try await idempotencyCache.lookup(
            tool: params.name, key: key, checksum: checksum)
          {
            return cached.toCallToolResult()
          }
        } catch is IdempotencyCache.IdempotencyCacheError {
          return Self.idempotencyConflictResult(key: key, toolName: params.name)
        }
      }

      guard await idempotencyInFlight.tryClaim(tool: params.name, key: key) else {
        // A same-process peer holds the key. Wait it out, then restart the
        // appropriate authority lookup: process cache for a non-durable backend,
        // durable DB for the production backend.
        await idempotencyInFlight.waitForRelease(tool: params.name, key: key)
        continue
      }

      do {
        let result = try await claimedIdempotentCall(
          definition, params, arguments, key: key, checksum: checksum)
        await idempotencyInFlight.release(tool: params.name, key: key)
        return result
      } catch {
        await idempotencyInFlight.release(tool: params.name, key: key)
        throw error
      }
    }
  }

  /// Executes an idempotent write while holding the in-process claim for its
  /// key. The durable DB lookup happens here — inside the claim — because a
  /// peer call commits its mutation (stamping the durable row with a transaction
  /// claim) before recording the response payload. A competing host may observe
  /// that short-lived claim, so the replay path polls the authoritative row for
  /// finalization rather than caching or reporting the claim as a success.
  private func claimedIdempotentCall(
    _ definition: ToolDefinition,
    _ params: CallTool.Parameters,
    _ arguments: [String: Value],
    key: String,
    checksum: String
  ) async throws -> CallTool.Result {
    // Check the durable DB cache for cross-restart and cross-generation replay.
    // A lookup error must
    // NOT degrade to `.miss`: that would silently re-run a mutation whose key
    // was already applied (the exact replay the key exists to prevent).
    // Surface it so the client retries the lookup instead.
    let dbIdempotency = mcpIdempotency
    if let dbIdempotency {
      let dbOutcome = try await dbIdempotency.lookupMcpIdempotency(
        toolName: params.name, key: key, checksum: checksum)
      switch dbOutcome {
      case .hit(let payload):
        return try await resultForDurablePayload(
          payload, dbIdempotency: dbIdempotency, key: key, toolName: params.name,
          checksum: checksum)
      case .checksumMismatch:
        return Self.idempotencyConflictResult(key: key, toolName: params.name)
      case .miss:
        break
      }
    }

    let idempotencyContext = dbIdempotency.map { _ in
      McpIdempotencyContext(toolName: params.name, key: key, checksum: checksum)
    }
    let result: CallTool.Result
    do {
      result = try await SwiftLorvexCoreService.$currentMCPIdempotency.withValue(
        idempotencyContext
      ) {
        try await definition.call(on: self, arguments: arguments)
      }
      if let gate = idempotencyContext?.attemptState.gate {
        return try await resultForIdempotencyGate(
          gate, dbIdempotency: dbIdempotency, key: key, toolName: params.name,
          checksum: checksum)
      }
    } catch let gate as McpIdempotencyTransactionError {
      return try await resultForIdempotencyGate(
        gate, dbIdempotency: dbIdempotency, key: key, toolName: params.name,
        checksum: checksum)
    }
    if result.isError != true {
      let cached = result.toCachedResult()
      if let dbIdempotency, let idempotencyContext {
        // Persist the durable record rather than swallowing its failure: the
        // service write uses BEGIN IMMEDIATE + a 5s busy timeout, so transient
        // contention is absorbed and a throw means a genuine failure to record
        // an applied key. Surfacing it lets the client retry the authoritative
        // lookup. Do not publish this response
        // into the process cache: even a successful finalize belongs only to the
        // managed-store generation in which it committed.
        try await dbIdempotency.finalizeMcpIdempotency(
          toolName: params.name, key: key, checksum: checksum,
          claimToken: idempotencyContext.claimToken,
          payload: cached.durablePayload())
      } else {
        // Injected backends without durable idempotency retain the original
        // same-process replay behavior.
        await idempotencyCache.store(
          cached, forTool: params.name, key: key, checksum: checksum)
      }
    }
    return result
  }

  private func resultForIdempotencyGate(
    _ gate: McpIdempotencyTransactionError,
    dbIdempotency: (any LorvexMcpIdempotencyServicing)?,
    key: String,
    toolName: String,
    checksum: String
  ) async throws -> CallTool.Result {
    switch gate {
    case .replay(let payload):
      return try await resultForDurablePayload(
        payload, dbIdempotency: dbIdempotency, key: key, toolName: toolName,
        checksum: checksum)
    case .checksumMismatch:
      return Self.idempotencyConflictResult(key: key, toolName: toolName)
    }
  }

  /// Convert a durable payload into a replay. A committed transaction claim is
  /// an in-progress handoff, not the legacy unrecoverable marker: another MCP
  /// host may have committed the domain mutation and be a few milliseconds away
  /// from replacing the claim with the response. Polling the authoritative row
  /// prevents that transient state from leaking as a permanent client error.
  private func resultForDurablePayload(
    _ payload: String,
    dbIdempotency: (any LorvexMcpIdempotencyServicing)?,
    key: String,
    toolName: String,
    checksum: String
  ) async throws -> CallTool.Result {
    switch McpIdempotencyDurablePayload.kind(of: payload) {
    case .response:
      let cached = IdempotencyCache.CachedResult.fromDurablePayload(payload)
      return cached.toCallToolResult()
    case .appliedWithoutResponse:
      return Self.appliedWithoutResponseResult(key: key, toolName: toolName)
    case .transactionClaim:
      guard let dbIdempotency else {
        return Self.appliedWithoutResponseResult(key: key, toolName: toolName)
      }
      return try await awaitFinalizedDurablePayload(
        dbIdempotency, key: key, toolName: toolName, checksum: checksum)
    }
  }

  private func awaitFinalizedDurablePayload(
    _ dbIdempotency: any LorvexMcpIdempotencyServicing,
    key: String,
    toolName: String,
    checksum: String
  ) async throws -> CallTool.Result {
    // A transaction claim is not terminal while its owner remains inside the
    // legal maintenance-finalize window. The production policy is deliberately
    // longer than both storage-cutover acquisition and SQLite write contention;
    // tests inject a short policy to exercise the exact last-poll boundary.
    for _ in 0..<idempotencyClaimWaitPolicy.maximumPollCount {
      try await Task.sleep(
        for: .milliseconds(idempotencyClaimWaitPolicy.pollIntervalMilliseconds))
      switch try await dbIdempotency.lookupMcpIdempotency(
        toolName: toolName, key: key, checksum: checksum)
      {
      case .hit(let payload):
        switch McpIdempotencyDurablePayload.kind(of: payload) {
        case .transactionClaim:
          continue
        case .appliedWithoutResponse:
          return Self.appliedWithoutResponseResult(key: key, toolName: toolName)
        case .response:
          let cached = IdempotencyCache.CachedResult.fromDurablePayload(payload)
          return cached.toCallToolResult()
        }
      case .checksumMismatch:
        return Self.idempotencyConflictResult(key: key, toolName: toolName)
      case .miss:
        continue
      }
    }
    return Self.appliedWithoutResponseResult(key: key, toolName: toolName)
  }

  private static func idempotencyConflictResult(key: String, toolName: String) -> CallTool.Result {
    Self.errorResult(
      code: "idempotency_conflict",
      message:
        "Idempotency key '\(key)' was already used for \(toolName) with different arguments. Use a new key for a different intent.",
      toolName: toolName
    )
  }

  private static func appliedWithoutResponseResult(
    key: String, toolName: String
  ) -> CallTool.Result {
    Self.errorResult(
      code: "idempotency_response_unavailable",
      message:
        "Idempotency key '\(key)' for \(toolName) was already applied, but the original response was not durably recorded before the previous host stopped. Do not retry this mutation with the same or a different key; read the affected records to recover current state.",
      toolName: toolName
    )
  }

  func unknownToolResult(named name: String) -> CallTool.Result {
    Self.errorResult(
      code: "unknown_tool",
      message: "Unknown tool: \(name)",
      toolName: name
    )
  }
}

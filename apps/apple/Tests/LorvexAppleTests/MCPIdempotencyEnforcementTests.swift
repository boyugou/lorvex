import MCP
import Testing
import LorvexRuntime

@testable import LorvexCore
@testable import LorvexMCPHost

/// Idempotency enforcement at the central tool dispatch (CLAUDE.md Core Design
/// Rule 5; `docs/design/SYNC_APPLY_SEMANTICS.md` §"Idempotency Cache").
///
/// These run against the real in-memory core: a unique task title counts live
/// writes via `list_tasks`, and the per-task `ai_changelog` row count is the
/// write-happened signal (every MCP write logs exactly one row, Rule 2).
@Suite("MCP Tool Registry — idempotency enforcement")
struct MCPIdempotencyEnforcementTests {

  /// Number of ai_changelog rows for an entity — 1 after a real create, and
  /// still 1 after a replay that performed no second live write.
  private func changelogCount(_ registry: ToolRegistry, entityID: String) async throws -> Int {
    let log = try await mcpRegistryCall(
      registry, tool: "get_ai_changelog", arguments: ["entity_id": .string(entityID)])
    return log.structuredContent?.objectValue?["entries"]?.arrayValue?.count ?? 0
  }

  private func taskCount(_ registry: ToolRegistry, titled title: String) async throws -> Int {
    let result = try await mcpRegistryCall(
      registry, tool: "list_tasks", arguments: ["text": .string(title)])
    let tasks = result.structuredContent?.objectValue?["tasks"]?.arrayValue ?? []
    return tasks.filter {
      $0.objectValue?["title"]?.stringValue?.contains(title) == true
    }.count
  }

  /// The durable record (the core's `mcp_idempotency.response_payload`, a single
  /// TEXT column) must carry the structured content, not just the text — a
  /// cross-restart replay otherwise loses the returned IDs/objects. This guards
  /// the encode/decode round-trip behind that column.
  @Test("durable idempotency payload round-trips structured content")
  func durablePayloadPreservesStructuredContent() {
    let structured: Value = .object(["id": .string("policy-1"), "deleted": .bool(true)])
    let original = IdempotencyCache.CachedResult(
      textContent: "Deleted policy-1.", structuredContent: structured)

    let restored = IdempotencyCache.CachedResult.fromDurablePayload(original.durablePayload())
    #expect(restored.textContent == "Deleted policy-1.")
    #expect(restored.structuredContent as? Value == structured)

    // A non-envelope payload (e.g. a pre-existing text-only record) still decodes
    // as text-only rather than throwing.
    let legacy = IdempotencyCache.CachedResult.fromDurablePayload("plain text only")
    #expect(legacy.textContent == "plain text only")
    #expect(legacy.structuredContent as? Value == nil)
  }

  @Test("in-flight same key claim is exclusive until release")
  func inFlightSameKeyClaimIsExclusiveUntilRelease() async {
    let claims = IdempotencyInFlightClaims()

    #expect(await claims.tryClaim(tool: "create_task", key: "key-1"))
    #expect(await claims.tryClaim(tool: "create_task", key: "key-1") == false)
    #expect(await claims.tryClaim(tool: "update_task", key: "key-1"))

    await claims.release(tool: "create_task", key: "key-1")
    #expect(await claims.tryClaim(tool: "create_task", key: "key-1"))
  }

  @Test("in-flight wait resumes after release")
  func inFlightWaitResumesAfterRelease() async {
    let claims = IdempotencyInFlightClaims()
    #expect(await claims.tryClaim(tool: "create_task", key: "key-1"))

    let waiter = Task {
      await claims.waitForRelease(tool: "create_task", key: "key-1")
      return await claims.tryClaim(tool: "create_task", key: "key-1")
    }

    await claims.release(tool: "create_task", key: "key-1")
    #expect(await waiter.value)
  }

  @Test("durable applied-without-response marker is not replayed as success")
  func durableAppliedWithoutResponseMarkerReturnsError() async throws {
    let fixture = mcpOnDiskRegistry()
    defer { fixture.cleanup() }
    let args: [String: Value] = [
      "title": .string("Sentinel should not create"),
      "idempotency_key": .string("key-sentinel"),
    ]
    let checksum = IdempotencyCache.checksum(for: args)
    let service = SwiftLorvexCoreService(databasePath: fixture.dbPath)
    try await service.recordMcpIdempotency(
      toolName: "create_task", key: "key-sentinel", checksum: checksum,
      payload: McpIdempotencyDurablePayload.appliedWithoutResponse)

    let result = try await mcpRegistryCall(fixture.registry, tool: "create_task", arguments: args)
    expectMCPStructuredError(
      result, code: "idempotency_response_unavailable", tool: "create_task")
  }

  @Test("durable payload classifier distinguishes a live claim from a legacy terminal marker")
  func durablePayloadClassifierDistinguishesClaim() {
    #expect(
      McpIdempotencyDurablePayload.kind(
        of: McpIdempotencyDurablePayload.transactionClaim(token: "claim-token"))
        == .transactionClaim(token: "claim-token"))
    #expect(
      McpIdempotencyDurablePayload.kind(
        of: McpIdempotencyDurablePayload.appliedWithoutResponse)
        == .appliedWithoutResponse)
    #expect(McpIdempotencyDurablePayload.kind(of: #"{"text":"success"}"#) == .response)
  }

  @Test("replay: same key + identical args returns cached result, no second write")
  func replaySameKeyNoSecondWrite() async throws {
    let registry = try mcpInMemoryRegistry()
    let title = "IdemReplay-\(Int.random(in: 10000...99999))"
    let args: [String: Value] = [
      "title": .string(title),
      "idempotency_key": .string("key-replay"),
    ]

    let first = try await mcpRegistryCall(registry, tool: "create_task", arguments: args)
    #expect(first.isError != true)
    let firstID = try #require(first.structuredContent?.objectValue?["id"]?.stringValue)

    let second = try await mcpRegistryCall(registry, tool: "create_task", arguments: args)
    #expect(second.isError != true)
    let secondID = second.structuredContent?.objectValue?["id"]?.stringValue

    // Replay returns the identical original payload and performs no live write:
    // one task, and still only the original create's changelog row.
    #expect(secondID == firstID)
    #expect(try await taskCount(registry, titled: title) == 1)
    #expect(try await changelogCount(registry, entityID: firstID) == 1)
  }

  @Test("concurrent same key replays one write result")
  func concurrentSameKeyReplaysOneWriteResult() async throws {
    let registry = try mcpInMemoryRegistry()
    let title = "IdemConcurrent-\(Int.random(in: 10000...99999))"
    let args: [String: Value] = [
      "title": .string(title),
      "idempotency_key": .string("key-concurrent"),
    ]

    let results = try await withThrowingTaskGroup(of: CallTool.Result.self) { group in
      for _ in 0..<8 {
        group.addTask {
          try await mcpRegistryCall(registry, tool: "create_task", arguments: args)
        }
      }
      var values: [CallTool.Result] = []
      for try await result in group {
        values.append(result)
      }
      return values
    }

    #expect(results.allSatisfy { $0.isError != true })
    let ids = Set(results.compactMap { $0.structuredContent?.objectValue?["id"]?.stringValue })
    #expect(ids.count == 1)
    #expect(try await taskCount(registry, titled: title) == 1)
  }

  @Test("two registries sharing one database cannot duplicate a keyed mutation")
  func crossRegistrySameChecksumRunsOneMutation() async throws {
    let firstFixture = mcpOnDiskRegistry()
    defer { firstFixture.cleanup() }
    let firstRegistry = firstFixture.registry
    let secondRegistry = mcpOnDiskRegistry(dbPath: firstFixture.dbPath).registry
    _ = try await mcpRegistryCall(firstRegistry, tool: "get_overview")
    _ = try await mcpRegistryCall(secondRegistry, tool: "get_overview")
    let title = "IdemCrossRegistry-\(UUID().uuidString)"
    let args: [String: Value] = [
      "title": .string(title),
      "idempotency_key": .string("cross-registry-same"),
    ]

    let results = try await withThrowingTaskGroup(of: CallTool.Result.self) { group in
      group.addTask {
        try await mcpRegistryCall(firstRegistry, tool: "create_task", arguments: args)
      }
      group.addTask {
        try await mcpRegistryCall(secondRegistry, tool: "create_task", arguments: args)
      }
      var values: [CallTool.Result] = []
      for try await result in group { values.append(result) }
      return values
    }

    #expect(results.allSatisfy { $0.isError != true })
    let ids = Set(results.compactMap {
      $0.structuredContent?.objectValue?["id"]?.stringValue
    })
    #expect(ids.count == 1, "both hosts must replay the committed candidate")
    #expect(try await taskCount(firstRegistry, titled: title) == 1)
  }

  @Test("two registries reject a cross-process checksum race before either duplicate body runs")
  func crossRegistryDifferentChecksumRejectsLoser() async throws {
    let firstFixture = mcpOnDiskRegistry()
    defer { firstFixture.cleanup() }
    let firstRegistry = firstFixture.registry
    let secondRegistry = mcpOnDiskRegistry(dbPath: firstFixture.dbPath).registry
    _ = try await mcpRegistryCall(firstRegistry, tool: "get_overview")
    _ = try await mcpRegistryCall(secondRegistry, tool: "get_overview")
    let key = "cross-registry-conflict"
    let titleA = "IdemCrossA-\(UUID().uuidString)"
    let titleB = "IdemCrossB-\(UUID().uuidString)"

    let results = try await withThrowingTaskGroup(of: CallTool.Result.self) { group in
      group.addTask {
        try await mcpRegistryCall(
          firstRegistry, tool: "create_task",
          arguments: ["title": .string(titleA), "idempotency_key": .string(key)])
      }
      group.addTask {
        try await mcpRegistryCall(
          secondRegistry, tool: "create_task",
          arguments: ["title": .string(titleB), "idempotency_key": .string(key)])
      }
      var values: [CallTool.Result] = []
      for try await result in group { values.append(result) }
      return values
    }

    #expect(results.filter { $0.isError != true }.count == 1)
    #expect(
      results.filter { $0.isError == true }.allSatisfy {
        $0.structuredContent?.objectValue?["code"]?.stringValue == "idempotency_conflict"
      })
    let countA = try await taskCount(firstRegistry, titled: titleA)
    let countB = try await taskCount(firstRegistry, titled: titleB)
    #expect(countA + countB == 1)
  }

  @Test("a batch handler cannot swallow a competing durable claim")
  func crossRegistryBatchCatchCannotBypassClaim() async throws {
    let firstFixture = mcpOnDiskRegistry()
    defer { firstFixture.cleanup() }
    let firstRegistry = firstFixture.registry
    let secondRegistry = mcpOnDiskRegistry(dbPath: firstFixture.dbPath).registry
    _ = try await mcpRegistryCall(firstRegistry, tool: "get_overview")
    _ = try await mcpRegistryCall(secondRegistry, tool: "get_overview")
    let prefix = "IdemBatchCross-\(UUID().uuidString)"
    let args: [String: Value] = [
      "events": .array([
        .object([
          "title": .string("\(prefix)-A"), "start_date": .string("2026-09-01"),
          "all_day": .bool(true),
        ]),
        .object([
          "title": .string("\(prefix)-B"), "start_date": .string("2026-09-02"),
          "all_day": .bool(true),
        ]),
      ]),
      "idempotency_key": .string("cross-registry-batch"),
    ]

    let results = try await withThrowingTaskGroup(of: CallTool.Result.self) { group in
      group.addTask {
        try await mcpRegistryCall(
          firstRegistry, tool: "batch_create_calendar_events", arguments: args)
      }
      group.addTask {
        try await mcpRegistryCall(
          secondRegistry, tool: "batch_create_calendar_events", arguments: args)
      }
      var values: [CallTool.Result] = []
      for try await result in group { values.append(result) }
      return values
    }

    // A short-lived transaction claim is an in-progress handoff. Both hosts
    // wait for its finalized response and therefore receive the same full
    // batch result; the sentinel never leaks as a client-facing error.
    #expect(results.allSatisfy { $0.isError != true })
    #expect(results.allSatisfy {
      $0.structuredContent?.objectValue?["count"]?.intValue == 2
        && $0.structuredContent?.objectValue?["results"]?.arrayValue?.count == 2
    })
    let service = SwiftLorvexCoreService(databasePath: firstFixture.dbPath)
    let count = try service.read { db in
      try Int.fetchOne(
        db, sql: "SELECT COUNT(*) FROM calendar_events WHERE title LIKE ?1",
        arguments: ["\(prefix)%"]) ?? 0
    }
    #expect(count == 2)
  }

  @Test("keyed no-op focus mutations succeed and consume their key")
  func keyedNoOpFocusMutationsSucceedAndConsumeTheirKey() async throws {
    let registry = try mcpInMemoryRegistry()

    // No focus plan exists for the date, so both mutations are pure no-ops.
    // A keyed no-op must still commit a durable claim: the host finalizes every
    // keyed non-error result against it, and the consumed key must conflict on
    // reuse with different arguments.
    let clear = try await mcpRegistryCall(
      registry, tool: "clear_current_focus",
      arguments: [
        "date": .string("2026-07-18"),
        "idempotency_key": .string("key-clear-noop"),
      ])
    #expect(clear.isError != true, "a keyed no-op clear must succeed, not surface an internal error")

    let remove = try await mcpRegistryCall(
      registry, tool: "remove_from_current_focus",
      arguments: [
        "date": .string("2026-07-18"),
        "task_id": .string("00000000-0000-4000-8000-000000000001"),
        "idempotency_key": .string("key-remove-noop"),
      ])
    #expect(
      remove.isError != true, "a keyed no-op removal must succeed, not surface an internal error")

    // Replay with identical arguments returns the cached no-op result.
    let replay = try await mcpRegistryCall(
      registry, tool: "clear_current_focus",
      arguments: [
        "date": .string("2026-07-18"),
        "idempotency_key": .string("key-clear-noop"),
      ])
    #expect(replay.isError != true)

    // Reuse with different arguments must conflict — the no-op consumed the key.
    let conflict = try await mcpRegistryCall(
      registry, tool: "clear_current_focus",
      arguments: [
        "date": .string("2026-07-19"),
        "idempotency_key": .string("key-clear-noop"),
      ])
    #expect(conflict.isError == true, "a consumed no-op key must conflict on different arguments")
  }

  @Test("reject: same key + different args returns idempotency_conflict, no second write")
  func rejectSameKeyDifferentArgs() async throws {
    let registry = try mcpInMemoryRegistry()
    let firstTitle = "IdemReject-A-\(Int.random(in: 10000...99999))"
    let secondTitle = "IdemReject-B-\(Int.random(in: 10000...99999))"

    let first = try await mcpRegistryCall(
      registry, tool: "create_task",
      arguments: ["title": .string(firstTitle), "idempotency_key": .string("key-reject")])
    #expect(first.isError != true)

    let second = try await mcpRegistryCall(
      registry, tool: "create_task",
      arguments: ["title": .string(secondTitle), "idempotency_key": .string("key-reject")])

    expectMCPStructuredError(second, code: "idempotency_conflict", tool: "create_task")
    // No live write for the rejected call.
    #expect(try await taskCount(registry, titled: secondTitle) == 0)
  }

  @Test("miss: no idempotency_key creates two distinct entities")
  func missCreatesTwoEntities() async throws {
    let registry = try mcpInMemoryRegistry()
    let title = "IdemMiss-\(Int.random(in: 10000...99999))"
    let args: [String: Value] = ["title": .string(title)]

    let first = try await mcpRegistryCall(registry, tool: "create_task", arguments: args)
    let second = try await mcpRegistryCall(registry, tool: "create_task", arguments: args)
    #expect(first.isError != true)
    #expect(second.isError != true)

    let firstID = first.structuredContent?.objectValue?["id"]?.stringValue
    let secondID = second.structuredContent?.objectValue?["id"]?.stringValue
    #expect(firstID != secondID)
    #expect(try await taskCount(registry, titled: title) == 2)
  }

  @Test("read tools are not wrapped: a key'd get_task reflects later state, never replays stale")
  func readToolNotCached() async throws {
    let registry = try mcpInMemoryRegistry()
    let title = "IdemReadGuard-\(Int.random(in: 10000...99999))"

    let create = try await mcpRegistryCall(
      registry, tool: "create_task", arguments: ["title": .string(title)])
    guard let taskID = create.structuredContent?.objectValue?["id"]?.stringValue else {
      Issue.record("create_task did not return an id")
      return
    }

    // First read with an idempotency_key. Reads are excluded from the
    // allowlist, so this is never cached.
    let firstRead = try await mcpRegistryCall(
      registry, tool: "get_task",
      arguments: ["id": .string(taskID), "idempotency_key": .string("key-read")])
    #expect(firstRead.structuredContent?.objectValue?["title"]?.stringValue?.contains(title) == true)

    // Mutate the title, then read again with the SAME key. A wrongly-cached
    // read would replay the stale title; the dispatch must return live state.
    let newTitle = "IdemReadGuard-Updated-\(Int.random(in: 10000...99999))"
    _ = try await mcpRegistryCall(
      registry, tool: "update_task",
      arguments: ["id": .string(taskID), "title": .string(newTitle)])

    let secondRead = try await mcpRegistryCall(
      registry, tool: "get_task",
      arguments: ["id": .string(taskID), "idempotency_key": .string("key-read")])
    let readTitle = secondRead.structuredContent?.objectValue?["title"]?.stringValue
    #expect(readTitle?.contains(newTitle) == true)
    #expect(readTitle?.contains(title) == false || readTitle?.contains(newTitle) == true)
  }

  /// An unencodable payload (a non-finite `Double`) has no stable checksum
  /// (`JSONEncoder` throws → `checksum` returns ""). Two *different* such payloads
  /// under the same key must each run live, not checksum-match ("" == "") and
  /// replay the first — the empty checksum is treated as never-hit/never-store.
  /// The NaN rides an extra argument no handler decodes: the checksum covers the
  /// RAW argument object at the dispatch layer, while a NaN in a declared field
  /// like `notes` would now reject at strict scalar decoding before the
  /// idempotency layer could ever see it.
  @Test("empty-checksum payloads never replay across a shared idempotency key")
  func emptyChecksumPayloadsNeverReplay() async throws {
    let registry = try mcpInMemoryRegistry()
    let titleA = "IdemEmptyA-\(Int.random(in: 10000...99999))"
    let titleB = "IdemEmptyB-\(Int.random(in: 10000...99999))"
    let argsA: [String: Value] = [
      "title": .string(titleA), "zz_unencodable_probe": .double(.nan),
      "idempotency_key": .string("key-empty-checksum"),
    ]
    let argsB: [String: Value] = [
      "title": .string(titleB), "zz_unencodable_probe": .double(.nan),
      "idempotency_key": .string("key-empty-checksum"),
    ]
    // Premise: the NaN makes the whole-payload checksum empty.
    #expect(IdempotencyCache.checksum(for: argsA).isEmpty)

    let first = try await mcpRegistryCall(registry, tool: "create_task", arguments: argsA)
    let second = try await mcpRegistryCall(registry, tool: "create_task", arguments: argsB)
    #expect(first.isError != true)
    #expect(second.isError != true)

    let firstID = first.structuredContent?.objectValue?["id"]?.stringValue
    let secondID = second.structuredContent?.objectValue?["id"]?.stringValue
    #expect(firstID != nil)
    #expect(secondID != nil)
    // OLD bug: the second call replayed the first (secondID == firstID) and B was
    // never created.
    #expect(firstID != secondID)
    #expect(try await taskCount(registry, titled: titleB) == 1)
  }
}

// MARK: - Durable DB-backed idempotency

import Foundation

@Suite("MCP durable idempotency — SwiftLorvexCoreService conformance")
struct MCPDurableIdempotencyTests {
  private func makeOnDiskService() throws -> SwiftLorvexCoreService {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("LorvexIdempotencyTest-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let dbPath = dir.appendingPathComponent("test.db").path
    return SwiftLorvexCoreService(databasePath: dbPath)
  }

  @Test("lookup returns miss for unknown key")
  func lookupMissForUnknownKey() async throws {
    let svc = try makeOnDiskService()
    let outcome = try await svc.lookupMcpIdempotency(
      toolName: "create_task", key: "unknown-key", checksum: "abc123")
    #expect(outcome == .miss)
  }

  @Test("record then lookup returns hit with same checksum")
  func recordThenLookupHit() async throws {
    let svc = try makeOnDiskService()
    try await svc.recordMcpIdempotency(
      toolName: "create_task", key: "key-1", checksum: "checksum-1", payload: "payload-1")
    let outcome = try await svc.lookupMcpIdempotency(
      toolName: "create_task", key: "key-1", checksum: "checksum-1")
    if case .hit(let payload) = outcome {
      #expect(payload == "payload-1")
    } else {
      Issue.record("Expected .hit, got \(outcome)")
    }
  }

  @Test("successful on-disk MCP call overwrites in-transaction marker with replay payload")
  func successfulOnDiskCallOverwritesMarker() async throws {
    let fixture = mcpOnDiskRegistry()
    defer { fixture.cleanup() }
    let args: [String: Value] = [
      "title": .string("Durable overwrite task"),
      "idempotency_key": .string("key-overwrite"),
    ]
    let first = try await mcpRegistryCall(fixture.registry, tool: "create_task", arguments: args)
    #expect(first.isError != true)

    let checksum = IdempotencyCache.checksum(for: args)
    let service = SwiftLorvexCoreService(databasePath: fixture.dbPath)
    let outcome = try await service.lookupMcpIdempotency(
      toolName: "create_task", key: "key-overwrite", checksum: checksum)
    if case .hit(let payload) = outcome {
      #expect(payload != McpIdempotencyDurablePayload.appliedWithoutResponse)
      let replay = IdempotencyCache.CachedResult.fromDurablePayload(payload)
      #expect(replay.structuredContent as? Value == first.structuredContent)
    } else {
      Issue.record("Expected .hit, got \(outcome)")
    }
  }

  @Test("batch calendar create is durable-idempotent across registry restart")
  func batchCalendarCreateDurableIdempotencyReplaysWithoutDuplicates() async throws {
    let fixture = mcpOnDiskRegistry()
    defer { fixture.cleanup() }
    let args: [String: Value] = [
      "events": .array([
        .object([
          "title": .string("Durable batch A"),
          "start_date": .string("2026-06-15"),
          "all_day": .bool(true),
        ]),
        .object([
          "title": .string("Durable batch B"),
          "start_date": .string("2026-06-16"),
          "all_day": .bool(true),
        ]),
      ]),
      "idempotency_key": .string("calendar-batch-key"),
    ]
    let first = try await mcpRegistryCall(
      fixture.registry, tool: "batch_create_calendar_events", arguments: args)
    #expect(first.isError != true)
    #expect(first.structuredContent?.objectValue?["count"]?.intValue == 2)

    let reopened = mcpOnDiskRegistry(dbPath: fixture.dbPath)
    let second = try await mcpRegistryCall(
      reopened.registry, tool: "batch_create_calendar_events", arguments: args)
    #expect(second.isError != true)
    #expect(second.structuredContent == first.structuredContent)

    let service = SwiftLorvexCoreService(databasePath: fixture.dbPath)
    let count = try service.read { db in
      try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM calendar_events WHERE title LIKE 'Durable batch %'") ?? 0
    }
    #expect(count == 2)
  }

  @Test("durable idempotency maintenance does not bump local change sequence")
  func durableMaintenanceDoesNotBumpLocalChangeSequence() async throws {
    let svc = try makeOnDiskService()
    let beforeRecord = try svc.read { try LocalChangeSeq.read($0) }
    try await svc.recordMcpIdempotency(
      toolName: "create_task", key: "key-seq", checksum: "checksum-seq", payload: "payload-seq")
    let afterRecord = try svc.read { try LocalChangeSeq.read($0) }

    try await svc.sweepMcpIdempotency()
    let afterSweep = try svc.read { try LocalChangeSeq.read($0) }

    #expect(beforeRecord == 0)
    #expect(afterRecord == beforeRecord)
    #expect(afterSweep == beforeRecord)
  }

  @Test("lookup returns checksumMismatch when checksum differs")
  func lookupChecksumMismatch() async throws {
    let svc = try makeOnDiskService()
    try await svc.recordMcpIdempotency(
      toolName: "create_task", key: "key-2", checksum: "original", payload: "payload-2")
    let outcome = try await svc.lookupMcpIdempotency(
      toolName: "create_task", key: "key-2", checksum: "different")
    if case .checksumMismatch(let stored, let supplied) = outcome {
      #expect(stored == "original")
      #expect(supplied == "different")
    } else {
      Issue.record("Expected .checksumMismatch, got \(outcome)")
    }
  }

  @Test("sweep removes no rows when none are expired")
  func sweepNoExpiredRows() async throws {
    let svc = try makeOnDiskService()
    try await svc.recordMcpIdempotency(
      toolName: "create_task", key: "key-3", checksum: "c3", payload: "p3")
    try await svc.sweepMcpIdempotency()
    let outcome = try await svc.lookupMcpIdempotency(
      toolName: "create_task", key: "key-3", checksum: "c3")
    #expect(outcome == .hit(responsePayload: "p3"))
  }
}

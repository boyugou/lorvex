import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Multi-row task update.
///
/// Per-row shape is the same `TaskUpdateInput` the single-item
/// ``TaskUpdate/updateTask(_:hlc:input:deviceId:recurrenceHandler:)``
/// consumes, so MCP / CLI / app surfaces share one wire shape. The
/// orchestrator:
///
/// 1. Sanitizes every patch in place.
/// 2. Pre-flight `validateBatchIds`: at least one item, no more than
///    ``batchUpdateTasksLimit``, no duplicates, every id passes the
///    entity-id sentinel.
/// 3. Pre-loads enriched `before` rows once (avoids reloading per row
///    inside the transaction).
/// 4. For each patch, dispatches to the shared per-row apply
///    ``TaskUpdate/applySingleUpdateInSavepoint(...)`` the single-item
///    surface also uses. Per-row error handling is fail-fast: the
///    first row's throw aborts the batch and the surrounding
///    transaction rolls back.
/// 5. Runs ``TaskUpdate/revalidateDependencyCycles(_:depChangedIds:errorContext:)``
///    once at the end against the final edge state.
///
/// Opens its own `BEGIN IMMEDIATE` transaction via
/// ``StoreTransactions/withImmediateTransaction(_:_:)``, matching the
/// single-row ``TaskUpdate/updateTask`` shape — functionally identical
/// at the call sites the Apple core targets, which do not nest writes
/// under a pre-existing transaction.
///
/// Sync effects: the per-row ``TaskUpdateSyncEffects`` accumulator is
/// reused as the aggregate — vectors grow across rows in row order.
/// The dedicated ``BatchUpdateSyncEffects`` typealias preserves the
/// historical batch name while keeping a single source of truth.
public enum TaskBatchUpdate {
  /// Hard cap on the number of rows accepted in one batch. Doubles as
  /// the cycle-revalidation cost ceiling.
  public static let batchUpdateTasksLimit: Int = 500

  public static func batchUpdateTasks(
    _ writer: any DatabaseWriter,
    hlc: HlcSession,
    input: BatchUpdateTasksInput,
    recurrenceHandler: RecurrenceSpawnHandler = LifecycleRecurrenceSpawnHandler()
  ) throws -> BatchUpdateTasksResult {
    try StoreTransactions.withImmediateTransaction(writer) { db in
      try batchUpdateTasksInTransaction(
        db, hlc: hlc, input: input, recurrenceHandler: recurrenceHandler)
    }
  }

  /// Transaction-scoped variant for higher-level write surfaces that must keep
  /// the batch row mutations, outbox effects, changelog, and local-change
  /// counter in one caller-owned transaction.
  public static func batchUpdateTasksInTransaction(
    _ db: Database,
    hlc: HlcSession,
    input: BatchUpdateTasksInput,
    recurrenceHandler: RecurrenceSpawnHandler = LifecycleRecurrenceSpawnHandler()
  ) throws -> BatchUpdateTasksResult {
    var updates = input.updates
    if updates.isEmpty {
      throw StoreError.validation("updates must contain at least one item")
    }
    if updates.count > batchUpdateTasksLimit {
      throw StoreError.validation(
        "batch_update_tasks supports at most \(batchUpdateTasksLimit) items, got \(updates.count)"
      )
    }
    for i in updates.indices {
      TaskUpdateSanitize.sanitizeInput(&updates[i])
    }
    let updateIds = updates.map { $0.id }
    try validateBatchIds(updateIds, toolName: "batch_update_tasks")

    let beforeTasks = try TaskResponse.loadEnrichedTasksJSON(
      db, taskIds: updateIds)
    var beforeById: [String: JSONValue] = [:]
    for (id, task) in zip(updateIds, beforeTasks) {
      beforeById[id] = task
    }

    let now = SyncTimestampFormat.syncTimestampNow()
    var syncEffects = BatchUpdateSyncEffects()
    var updatedIds: [String] = []
    updatedIds.reserveCapacity(updates.count)
    var depChangedIds: [String] = []

    for update in updates {
      guard let before = beforeById[update.id] else {
        throw StoreError.notFound(
          entity: EntityName.task, id: update.id)
      }
      let beforeStatus: String
      if case .object(let obj) = before,
        case .string(let s) = obj["status"] ?? .null
      {
        beforeStatus = s
      } else {
        throw StoreError.invariant(
          "batch_update_tasks before-task: missing string field `status`")
      }
      try TaskUpdate.applySingleUpdateInSavepoint(
        db,
        hlc: hlc,
        update: update,
        beforeStatus: beforeStatus,
        now: now,
        syncEffects: &syncEffects,
        depChangedIds: &depChangedIds,
        recurrenceHandler: recurrenceHandler)
      updatedIds.append(update.id)
    }
    try TaskUpdate.revalidateDependencyCycles(
      db, depChangedIds: depChangedIds,
      errorContext: "batch_update_tasks")

    let updatedTasks = try TaskResponse.loadEnrichedTasksJSON(
      db, taskIds: updatedIds)
    let summary = try buildSummary(updatedTasks: updatedTasks)
    let payload: JSONValue = .object([
      "updated_count": .int(Int64(updatedTasks.count)),
      "tasks": .array(updatedTasks),
    ])

    return BatchUpdateTasksResult(
      updatedIds: updatedIds,
      beforeTasks: beforeTasks,
      updatedTasks: updatedTasks,
      payload: payload,
      summary: summary,
      syncEffects: syncEffects)
  }

  /// Cross-row id-list shape guard: every id parses through the
  /// entity-id sentinel, no duplicates, within the batch cap.
  public static func validateBatchIds(
    _ ids: [String], toolName: String
  ) throws {
    if ids.isEmpty {
      throw StoreError.validation("\(toolName) requires at least one ID")
    }
    if ids.count > batchUpdateTasksLimit {
      throw StoreError.validation(
        "\(toolName) supports at most \(batchUpdateTasksLimit) items, got \(ids.count)"
      )
    }
    var seen = Set<String>()
    for id in ids {
      try TaskUpdatePreparation.validateTaskIdShape(id, fieldName: "id")
      if !seen.insert(id).inserted {
        throw StoreError.validation(
          "\(toolName) contains duplicate id '\(id)'")
      }
    }
  }

  /// One-line audit summary.
  static func buildSummary(updatedTasks: [JSONValue]) throws -> String {
    var titles: [String] = []
    titles.reserveCapacity(updatedTasks.count)
    for task in updatedTasks {
      guard case .object(let obj) = task,
        case .string(let title) = obj["title"] ?? .null
      else {
        throw StoreError.invariant(
          "batch_update_tasks updated-task: missing string field `title`")
      }
      titles.append("'\(title)'")
    }
    let suffix = updatedTasks.count == 1 ? "" : "s"
    return "Updated \(updatedTasks.count) task\(suffix): \(titles.joined(separator: ", "))"
  }
}

/// Single-row patch input. Type alias preserves the canonical batch
/// name while keeping the wire definition in ``TaskUpdateInput``.
public typealias BatchUpdateTaskPatchInput = TaskUpdateInput

/// Per-row sync-effect accumulator reused as the aggregate envelope.
public typealias BatchUpdateSyncEffects = TaskUpdateSyncEffects

/// Input envelope for ``TaskBatchUpdate/batchUpdateTasks``.
public struct BatchUpdateTasksInput: Sendable {
  public var updates: [BatchUpdateTaskPatchInput]
  public init(updates: [BatchUpdateTaskPatchInput]) {
    self.updates = updates
  }
}

/// Result envelope of ``TaskBatchUpdate/batchUpdateTasks``.
public struct BatchUpdateTasksResult: Sendable {
  public let updatedIds: [String]
  public let beforeTasks: [JSONValue]
  public let updatedTasks: [JSONValue]
  public let payload: JSONValue
  public let summary: String
  public let syncEffects: BatchUpdateSyncEffects
}

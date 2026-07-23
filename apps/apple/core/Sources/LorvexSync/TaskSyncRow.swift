import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Fully materialized task snapshot used by the grouped-register sync join.
///
/// A task is the product of four independently ordered values. `version` is
/// only the transport/delete high-water mark; it must never decide which
/// content, schedule, lifecycle, or archive bytes survive an Upsert.
struct TaskSyncRow: Equatable {
  var id: String
  var title: String
  var body: String?
  var rawInput: String?
  var aiNotes: String?
  var status: String
  var listId: String
  var priority: Int64?
  var dueDate: String?
  var estimatedMinutes: Int64?
  var recurrence: String?
  var recurrenceExceptions: String?
  var spawnedFrom: String?
  var spawnedFromVersion: String?
  var recurrenceGroupId: String?
  var canonicalOccurrenceDate: String?
  var completedAt: String?
  var lastDeferredAt: String?
  var lastDeferReason: String?
  var plannedDate: String?
  var availableFrom: String?
  var deferCount: Int64
  var recurrenceInstanceKey: String?
  var archivedAt: String?
  var contentVersion: String
  var scheduleVersion: String
  var lifecycleVersion: String
  var archiveVersion: String
  var recurrenceRolloverState: String
  var recurrenceSuccessorId: String?
  var createdAt: String
  var updatedAt: String
  var version: String

  static func load(_ db: Database, id: String) throws -> TaskSyncRow? {
    guard
      let row = try Row.fetchOne(
        db,
        sql: """
          SELECT id, title, body, raw_input, ai_notes, status, list_id, priority,
                 due_date, estimated_minutes, recurrence,
                 (SELECT NULLIF(json_group_array(exception_date), '[]')
                    FROM (SELECT exception_date
                            FROM task_recurrence_exceptions
                           WHERE task_id = tasks.id
                           ORDER BY exception_date)) AS recurrence_exceptions,
                 spawned_from, spawned_from_version, recurrence_group_id,
                 canonical_occurrence_date, completed_at, last_deferred_at,
                 last_defer_reason, planned_date, available_from, defer_count,
                 recurrence_instance_key, archived_at, content_version,
                 schedule_version, lifecycle_version, archive_version,
                 recurrence_rollover_state, recurrence_successor_id,
                 created_at, updated_at, version
            FROM tasks WHERE id = ?
          """,
        arguments: [id])
    else { return nil }
    return TaskSyncRow(
      id: row["id"], title: row["title"], body: row["body"], rawInput: row["raw_input"],
      aiNotes: row["ai_notes"], status: row["status"], listId: row["list_id"],
      priority: row["priority"], dueDate: row["due_date"],
      estimatedMinutes: row["estimated_minutes"], recurrence: row["recurrence"],
      recurrenceExceptions: row["recurrence_exceptions"], spawnedFrom: row["spawned_from"],
      spawnedFromVersion: row["spawned_from_version"],
      recurrenceGroupId: row["recurrence_group_id"],
      canonicalOccurrenceDate: row["canonical_occurrence_date"],
      completedAt: row["completed_at"], lastDeferredAt: row["last_deferred_at"],
      lastDeferReason: row["last_defer_reason"], plannedDate: row["planned_date"],
      availableFrom: row["available_from"], deferCount: row["defer_count"],
      recurrenceInstanceKey: row["recurrence_instance_key"], archivedAt: row["archived_at"],
      contentVersion: row["content_version"], scheduleVersion: row["schedule_version"],
      lifecycleVersion: row["lifecycle_version"], archiveVersion: row["archive_version"],
      recurrenceRolloverState: row["recurrence_rollover_state"],
      recurrenceSuccessorId: row["recurrence_successor_id"],
      createdAt: row["created_at"], updatedAt: row["updated_at"], version: row["version"])
  }

  /// Materialize the parser's partial representation over the current row.
  /// Public wire Upserts are full snapshots, but keeping this boundary total
  /// preserves direct parser tests and historical inner callers.
  static func materialize(
    _ row: ApplyTask.TaskRow, over local: TaskSyncRow?,
    payloadSchemaVersion: UInt32 = LorvexVersion.payloadSchemaVersion
  ) throws -> TaskSyncRow {
    func str(_ value: String?, _ present: Int64, _ old: String?) -> String? {
      present != 0 ? value : old
    }
    func int(_ value: Int64?, _ present: Int64, _ old: Int64?) -> Int64? {
      present != 0 ? value : old
    }
    guard let listId = row.listId ?? local?.listId else {
      throw ApplyError.invalidPayload("task \(row.entityId) has no resolvable list_id")
    }
    let result = TaskSyncRow(
      id: row.entityId, title: row.title,
      body: str(row.body, row.bodyPresent, local?.body),
      rawInput: str(row.rawInput, row.rawInputPresent, local?.rawInput),
      aiNotes: str(row.aiNotes, row.aiNotesPresent, local?.aiNotes),
      status: row.status, listId: listId,
      priority: int(row.priority, row.priorityPresent, local?.priority),
      dueDate: str(row.dueDate, row.dueDatePresent, local?.dueDate),
      estimatedMinutes: int(
        row.estimatedMinutes, row.estimatedMinutesPresent, local?.estimatedMinutes),
      recurrence: str(row.recurrence, row.recurrencePresent, local?.recurrence),
      recurrenceExceptions: str(
        row.recurrenceExceptions, row.recurrenceExceptionsPresent, local?.recurrenceExceptions),
      spawnedFrom: str(row.spawnedFrom, row.spawnedFromPresent, local?.spawnedFrom),
      spawnedFromVersion: str(
        row.spawnedFromVersion, row.spawnedFromVersionPresent, local?.spawnedFromVersion),
      recurrenceGroupId: str(
        row.recurrenceGroupId, row.recurrenceGroupIdPresent, local?.recurrenceGroupId),
      canonicalOccurrenceDate: str(
        row.canonicalOccurrenceDate, row.canonicalOccurrenceDatePresent,
        local?.canonicalOccurrenceDate),
      completedAt: str(row.completedAt, row.completedAtPresent, local?.completedAt),
      lastDeferredAt: str(
        row.lastDeferredAt, row.lastDeferredAtPresent, local?.lastDeferredAt),
      lastDeferReason: str(
        row.lastDeferReason, row.lastDeferReasonPresent, local?.lastDeferReason),
      plannedDate: str(row.plannedDate, row.plannedDatePresent, local?.plannedDate),
      availableFrom: str(row.availableFrom, row.availableFromPresent, local?.availableFrom),
      deferCount: int(row.deferCount, row.deferCountPresent, local?.deferCount) ?? 0,
      recurrenceInstanceKey: str(
        row.recurrenceInstanceKey, row.recurrenceInstanceKeyPresent,
        local?.recurrenceInstanceKey),
      archivedAt: str(row.archivedAt, row.archivedAtPresent, local?.archivedAt),
      contentVersion: row.contentVersion, scheduleVersion: row.scheduleVersion,
      lifecycleVersion: row.lifecycleVersion, archiveVersion: row.archiveVersion,
      recurrenceRolloverState: row.recurrenceRolloverState,
      recurrenceSuccessorId: str(
        row.recurrenceSuccessorId, row.recurrenceSuccessorIdPresent,
        local?.recurrenceSuccessorId),
      createdAt: row.createdAt, updatedAt: row.updatedAt, version: row.version)
    try result.validate(payloadSchemaVersion: payloadSchemaVersion)
    return result
  }

  static func merged(
    local: TaskSyncRow, incoming: TaskSyncRow,
    preferIncomingOnEqual: Bool = false
  ) throws -> (
    row: TaskSyncRow, repairIntent: TaskRegisterIntent, needsRootReemit: Bool
  ) {
    guard local.id == incoming.id else {
      throw ApplyError.invalidPayload("task grouped merge requires matching ids")
    }
    if let oldParent = local.spawnedFrom, let newParent = incoming.spawnedFrom,
      newParent != oldParent
    {
      throw ApplyError.invalidPayload("task \(local.id) cannot change immutable spawned_from")
    }
    var result = local
    if try incomingWins(
      localVersion: local.contentVersion, incomingVersion: incoming.contentVersion,
      localBytes: local.contentBytes(), incomingBytes: incoming.contentBytes(),
      preferIncomingOnEqual: preferIncomingOnEqual)
    {
      result.copyContent(from: incoming)
    }
    if try incomingWins(
      localVersion: local.scheduleVersion, incomingVersion: incoming.scheduleVersion,
      localBytes: local.scheduleBytes(), incomingBytes: incoming.scheduleBytes(),
      preferIncomingOnEqual: preferIncomingOnEqual)
    {
      result.copySchedule(from: incoming)
    }
    if try incomingWins(
      localVersion: local.lifecycleVersion, incomingVersion: incoming.lifecycleVersion,
      localBytes: local.lifecycleBytes(), incomingBytes: incoming.lifecycleBytes(),
      preferIncomingOnEqual: preferIncomingOnEqual)
    {
      result.copyLifecycle(from: incoming)
    }
    if try incomingWins(
      localVersion: local.archiveVersion, incomingVersion: incoming.archiveVersion,
      localBytes: local.archiveBytes(), incomingBytes: incoming.archiveBytes(),
      preferIncomingOnEqual: preferIncomingOnEqual)
    {
      result.copyArchive(from: incoming)
    }
    result.createdAt = min(local.createdAt, incoming.createdAt)
    if try incomingWins(
      localVersion: local.version, incomingVersion: incoming.version,
      localBytes: Array(local.updatedAt.utf8), incomingBytes: Array(incoming.updatedAt.utf8))
    {
      result.updatedAt = incoming.updatedAt
    }
    result.version = try maxHlc(local.version, incoming.version)
    let preNormalization = result
    try result.normalizeRolloverProduct()
    try result.validate()
    return (
      result,
      try result.changedRegisters(comparedTo: preNormalization),
      result.createdAt != local.createdAt
    )
  }

  static func staleIncomingRegisterWins(
    local: TaskSyncRow, incoming: TaskSyncRow
  ) throws -> Bool {
    try incomingWins(
      localVersion: local.contentVersion, incomingVersion: incoming.contentVersion,
      localBytes: local.contentBytes(), incomingBytes: incoming.contentBytes())
      || incomingWins(
        localVersion: local.scheduleVersion, incomingVersion: incoming.scheduleVersion,
        localBytes: local.scheduleBytes(), incomingBytes: incoming.scheduleBytes())
      || incomingWins(
        localVersion: local.lifecycleVersion, incomingVersion: incoming.lifecycleVersion,
        localBytes: local.lifecycleBytes(), incomingBytes: incoming.lifecycleBytes())
      || incomingWins(
        localVersion: local.archiveVersion, incomingVersion: incoming.archiveVersion,
        localBytes: local.archiveBytes(), incomingBytes: incoming.archiveBytes())
      || incoming.createdAt < local.createdAt
  }

  func asApplyRow() -> ApplyTask.TaskRow {
    ApplyTask.TaskRow(
      entityId: id, title: title, body: body, bodyPresent: 1,
      rawInput: rawInput, rawInputPresent: 1, aiNotes: aiNotes, aiNotesPresent: 1,
      status: status, listId: listId, priority: priority, priorityPresent: 1,
      dueDate: dueDate, dueDatePresent: 1, estimatedMinutes: estimatedMinutes,
      estimatedMinutesPresent: 1, recurrence: recurrence, recurrencePresent: 1,
      recurrenceExceptions: recurrenceExceptions, recurrenceExceptionsPresent: 1,
      spawnedFrom: spawnedFrom, spawnedFromPresent: 1,
      spawnedFromVersion: spawnedFromVersion, spawnedFromVersionPresent: 1,
      recurrenceGroupId: recurrenceGroupId, recurrenceGroupIdPresent: 1,
      canonicalOccurrenceDate: canonicalOccurrenceDate, canonicalOccurrenceDatePresent: 1,
      createdAt: createdAt, updatedAt: updatedAt, completedAt: completedAt,
      completedAtPresent: 1, lastDeferredAt: lastDeferredAt, lastDeferredAtPresent: 1,
      lastDeferReason: lastDeferReason, lastDeferReasonPresent: 1,
      plannedDate: plannedDate, plannedDatePresent: 1,
      availableFrom: availableFrom, availableFromPresent: 1,
      deferCount: deferCount, deferCountPresent: 1,
      recurrenceInstanceKey: recurrenceInstanceKey, recurrenceInstanceKeyPresent: 1,
      archivedAt: archivedAt, archivedAtPresent: 1,
      contentVersion: contentVersion, scheduleVersion: scheduleVersion,
      lifecycleVersion: lifecycleVersion, archiveVersion: archiveVersion,
      recurrenceRolloverState: recurrenceRolloverState,
      recurrenceSuccessorId: recurrenceSuccessorId, recurrenceSuccessorIdPresent: 1,
      version: version)
  }

  private func validate(
    payloadSchemaVersion: UInt32 = LorvexVersion.payloadSchemaVersion
  ) throws {
    let rowClock = try Self.canonical(version, field: "version")
    for (field, raw) in [
      ("content_version", contentVersion), ("schedule_version", scheduleVersion),
      ("lifecycle_version", lifecycleVersion), ("archive_version", archiveVersion),
    ] {
      guard try Self.canonical(raw, field: field) <= rowClock else {
        throw ApplyError.invalidPayload("task \(id) \(field) exceeds version")
      }
    }
    if let spawnedFromVersion {
      guard try Self.canonical(spawnedFromVersion, field: "spawned_from_version") <= rowClock else {
        throw ApplyError.invalidPayload("task \(id) spawned_from_version exceeds version")
      }
    }
    guard (spawnedFrom == nil) == (spawnedFromVersion == nil), spawnedFrom != id else {
      throw ApplyError.invalidPayload("task \(id) has invalid successor lineage")
    }
    if let parentId = spawnedFrom {
      guard let recurrenceGroupId,
        TaskRecurrenceSuccessorID.make(
          parentTaskId: parentId, recurrenceGroupId: recurrenceGroupId) == id
      else {
        throw ApplyError.invalidPayload(
          "task \(id) is not the deterministic successor of its declared parent")
      }
    }
    if let recurrenceInstanceKey {
      guard let recurrenceGroupId, let canonicalOccurrenceDate,
        Recurrence.generateInstanceKey(
          recurrenceGroupID: recurrenceGroupId,
          canonicalOccurrenceDate: canonicalOccurrenceDate) == recurrenceInstanceKey
      else {
        throw ApplyError.invalidPayload(
          "task \(id) has a non-canonical recurrence_instance_key")
      }
    }
    if spawnedFrom != nil, recurrenceInstanceKey == nil {
      throw ApplyError.invalidPayload(
        "task \(id) generated successor requires recurrence_instance_key")
    }
    guard
      recurrence == nil
        || (dueDate != nil && recurrenceGroupId != nil && canonicalOccurrenceDate != nil)
    else {
      throw ApplyError.forwardCompatOrInvalid(
        payloadSchemaVersion: payloadSchemaVersion,
        "task \(id) recurrence requires due_date, recurrence_group_id, and canonical_occurrence_date"
      )
    }
    let exceptionDates: [String]
    do {
      exceptionDates = try RecurrenceExceptionsRepo.parseExceptionDates(recurrenceExceptions)
    } catch {
      throw ApplyError.forwardCompatOrInvalid(
        payloadSchemaVersion: payloadSchemaVersion,
        "task \(id) has invalid recurrence_exceptions: \(error.localizedDescription)")
    }
    guard recurrence != nil || exceptionDates.isEmpty else {
      throw ApplyError.forwardCompatOrInvalid(
        payloadSchemaVersion: payloadSchemaVersion,
        "task \(id) recurrence_exceptions require recurrence")
    }
    guard (status == StatusName.completed) == (completedAt != nil) else {
      throw ApplyError.invalidPayload("task \(id) has incoherent completion lifecycle")
    }
    let terminal = status == StatusName.completed || status == StatusName.cancelled
    let active =
      status == StatusName.open || status == StatusName.inProgress || status == StatusName.someday
    switch recurrenceRolloverState {
    case "none" where recurrenceSuccessorId == nil && (recurrence == nil || active):
      break
    case "authorized" where recurrenceSuccessorId != nil && terminal && recurrence != nil:
      break
    case "revoked" where recurrenceSuccessorId != nil && active && recurrence != nil:
      break
    case "ended" where recurrenceSuccessorId == nil && terminal:
      break
    default:
      throw ApplyError.invalidPayload("task \(id) has incoherent recurrence rollover state")
    }
    if recurrenceRolloverState == "authorized" || recurrenceRolloverState == "revoked" {
      guard let recurrenceGroupId, let recurrenceSuccessorId,
        TaskRecurrenceSuccessorID.make(
          parentTaskId: id, recurrenceGroupId: recurrenceGroupId) == recurrenceSuccessorId
      else {
        throw ApplyError.invalidPayload(
          "task \(id) has a non-deterministic recurrence_successor_id")
      }
    }
    if recurrenceSuccessorId == id {
      throw ApplyError.invalidPayload("task \(id) cannot authorize itself as successor")
    }
  }

  /// Normalize legal independent schedule/lifecycle joins into the one durable
  /// rollover decision accepted by the row invariant. This is a deterministic
  /// derived join, not a new user mutation; the convergence re-emit publishes
  /// the normalized full snapshot at a fresh transport HLC.
  private mutating func normalizeRolloverProduct() throws {
    let terminal = status == StatusName.completed || status == StatusName.cancelled

    if recurrenceRolloverState == "authorized" || recurrenceRolloverState == "revoked" {
      let expectedSuccessorId = recurrenceGroupId.map {
        TaskRecurrenceSuccessorID.make(parentTaskId: id, recurrenceGroupId: $0)
      }
      if recurrenceSuccessorId != expectedSuccessorId {
        recurrenceRolloverState = terminal ? "ended" : "none"
        recurrenceSuccessorId = nil
      }
    }

    if terminal {
      switch recurrenceRolloverState {
      case "authorized" where recurrence == nil:
        recurrenceRolloverState = "ended"
        recurrenceSuccessorId = nil
      case "revoked":
        if recurrence != nil, recurrenceSuccessorId != nil {
          recurrenceRolloverState = "authorized"
        } else {
          recurrenceRolloverState = "ended"
          recurrenceSuccessorId = nil
        }
      case "none" where recurrence != nil:
        recurrenceRolloverState = "ended"
      case "ended":
        recurrenceSuccessorId = nil
      default:
        break
      }
    } else {
      switch recurrenceRolloverState {
      case "authorized":
        recurrenceRolloverState = "revoked"
      case "ended":
        recurrenceRolloverState = "none"
        recurrenceSuccessorId = nil
      case "none":
        recurrenceSuccessorId = nil
      case "revoked" where recurrence == nil:
        recurrenceRolloverState = "none"
        recurrenceSuccessorId = nil
      default:
        break
      }
    }
  }

  mutating func reRootSuccessor(at decisionVersion: String) throws {
    let decision = try Self.canonical(decisionVersion, field: "parent decision version")
    spawnedFrom = nil
    spawnedFromVersion = nil
    scheduleVersion =
      max(try Self.canonical(scheduleVersion, field: "schedule_version"), decision)
      .description
    version = max(try Self.canonical(version, field: "version"), decision).description
    try normalizeRolloverProduct()
    try validate()
  }

  mutating func cancelRevokedSuccessor(at decisionVersion: String) throws {
    let decision = try Self.canonical(decisionVersion, field: "parent decision version")
    status = StatusName.cancelled
    completedAt = nil
    recurrenceRolloverState = "ended"
    recurrenceSuccessorId = nil
    lifecycleVersion =
      max(
        try Self.canonical(lifecycleVersion, field: "lifecycle_version"), decision
      ).description
    version = max(try Self.canonical(version, field: "version"), decision).description
    try validate()
  }

  mutating func endAuthorizationForDeletedSuccessor(at decisionVersion: String) throws {
    guard recurrenceRolloverState == "authorized", recurrenceSuccessorId != nil else {
      return
    }
    let decision = try Self.canonical(decisionVersion, field: "successor delete version")
    recurrenceRolloverState = "ended"
    recurrenceSuccessorId = nil
    lifecycleVersion =
      max(
        try Self.canonical(lifecycleVersion, field: "lifecycle_version"), decision
      ).description
    version = max(try Self.canonical(version, field: "version"), decision).description
    try validate()
  }

  mutating func acceptAuthorization(
    parentId: String, parentVersion: String, reviveIfDominated: Bool
  ) throws {
    let parent = try Self.canonical(parentVersion, field: "parent lifecycle_version")
    if reviveIfDominated,
      parent > (try Self.canonical(lifecycleVersion, field: "lifecycle_version")),
      status == StatusName.cancelled
    {
      status = StatusName.open
      completedAt = nil
      recurrenceRolloverState = "none"
      recurrenceSuccessorId = nil
      lifecycleVersion = parent.description
    }
    spawnedFrom = parentId
    spawnedFromVersion = parent.description
    scheduleVersion =
      max(
        try Self.canonical(scheduleVersion, field: "schedule_version"), parent
      ).description
    version = max(try Self.canonical(version, field: "version"), parent).description
    try validate()
  }

  func advancedBeyondAuthorization() throws -> Bool {
    guard let raw = spawnedFromVersion else { return true }
    let authorization = try Self.canonical(raw, field: "spawned_from_version")
    let clocks = try [contentVersion, scheduleVersion, lifecycleVersion, archiveVersion].map {
      try Self.canonical($0, field: "task register version")
    }
    return clocks.contains(where: { $0 > authorization })
      || status != StatusName.open || archivedAt != nil || recurrenceSuccessorId != nil
  }

  func changedRegisters(comparedTo other: TaskSyncRow) throws -> TaskRegisterIntent {
    var intent: TaskRegisterIntent = []
    if try contentBytes() != other.contentBytes() { intent.insert(.content) }
    if try scheduleBytes() != other.scheduleBytes() { intent.insert(.schedule) }
    if try lifecycleBytes() != other.lifecycleBytes() { intent.insert(.lifecycle) }
    if try archiveBytes() != other.archiveBytes() { intent.insert(.archive) }
    return intent
  }

  private mutating func copyContent(from other: TaskSyncRow) {
    title = other.title
    body = other.body
    rawInput = other.rawInput
    aiNotes = other.aiNotes
    listId = other.listId
    priority = other.priority
    contentVersion = other.contentVersion
  }

  private mutating func copySchedule(from other: TaskSyncRow) {
    dueDate = other.dueDate
    estimatedMinutes = other.estimatedMinutes
    recurrence = other.recurrence
    recurrenceExceptions = other.recurrenceExceptions
    spawnedFrom = other.spawnedFrom
    spawnedFromVersion = other.spawnedFromVersion
    recurrenceGroupId = other.recurrenceGroupId
    canonicalOccurrenceDate = other.canonicalOccurrenceDate
    lastDeferredAt = other.lastDeferredAt
    lastDeferReason = other.lastDeferReason
    plannedDate = other.plannedDate
    availableFrom = other.availableFrom
    deferCount = other.deferCount
    recurrenceInstanceKey = other.recurrenceInstanceKey
    scheduleVersion = other.scheduleVersion
  }

  private mutating func copyLifecycle(from other: TaskSyncRow) {
    status = other.status
    completedAt = other.completedAt
    recurrenceRolloverState = other.recurrenceRolloverState
    recurrenceSuccessorId = other.recurrenceSuccessorId
    lifecycleVersion = other.lifecycleVersion
  }

  private mutating func copyArchive(from other: TaskSyncRow) {
    archivedAt = other.archivedAt
    archiveVersion = other.archiveVersion
  }

  private func contentBytes() throws -> [UInt8] {
    try bytes([
      "title": .string(title), "body": nullable(body), "raw_input": nullable(rawInput),
      "ai_notes": nullable(aiNotes), "list_id": .string(listId),
      "priority": priority.map(JSONValue.int) ?? .null,
    ])
  }

  private func scheduleBytes() throws -> [UInt8] {
    try bytes([
      "due_date": nullable(dueDate),
      "estimated_minutes": estimatedMinutes.map(JSONValue.int) ?? .null,
      "recurrence": nullable(recurrence),
      "recurrence_exceptions": recurrenceExceptions.flatMap(JSONValue.parse) ?? .null,
      "spawned_from": nullable(spawnedFrom),
      "spawned_from_version": nullable(spawnedFromVersion),
      "recurrence_group_id": nullable(recurrenceGroupId),
      "canonical_occurrence_date": nullable(canonicalOccurrenceDate),
      "last_deferred_at": nullable(lastDeferredAt),
      "last_defer_reason": nullable(lastDeferReason), "planned_date": nullable(plannedDate),
      "available_from": nullable(availableFrom), "defer_count": .int(deferCount),
      "recurrence_instance_key": nullable(recurrenceInstanceKey),
    ])
  }

  private func lifecycleBytes() throws -> [UInt8] {
    try bytes([
      "status": .string(status), "completed_at": nullable(completedAt),
      "recurrence_rollover_state": .string(recurrenceRolloverState),
      "recurrence_successor_id": nullable(recurrenceSuccessorId),
    ])
  }

  private func archiveBytes() throws -> [UInt8] {
    try bytes(["archived_at": nullable(archivedAt)])
  }

  private func nullable(_ value: String?) -> JSONValue {
    value.map(JSONValue.string) ?? .null
  }

  private func bytes(_ object: [String: JSONValue]) throws -> [UInt8] {
    do { return Array(try SyncCanonicalize.canonicalizeJSON(.object(object)).utf8) } catch {
      throw ApplyError.invalidPayload("task group canonicalization failed: \(error)")
    }
  }

  private static func incomingWins(
    localVersion: String, incomingVersion: String,
    localBytes: @autoclosure () throws -> [UInt8],
    incomingBytes: @autoclosure () throws -> [UInt8],
    preferIncomingOnEqual: Bool = false
  ) throws -> Bool {
    let local = try canonical(localVersion, field: "register version")
    let incoming = try canonical(incomingVersion, field: "register version")
    if incoming != local { return incoming > local }
    if preferIncomingOnEqual { return true }
    return try localBytes().lexicographicallyPrecedes(incomingBytes())
  }

  private static func maxHlc(_ lhs: String, _ rhs: String) throws -> String {
    max(try canonical(lhs, field: "version"), try canonical(rhs, field: "version")).description
  }

  private static func canonical(_ raw: String, field: String) throws -> Hlc {
    do { return try Hlc.parseCanonical(raw) } catch {
      throw ApplyError.invalidPayload("task \(field) must be a canonical HLC")
    }
  }
}

import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Per-entity apply handler for the `task` aggregate root.
///
/// Conforms to ``EntityApplier`` for `entity_type == "task"`. The upsert path
/// parses + validates + scrubs the inbound payload into a fully-typed row
/// (preserving local values on field absence via the `(value, present)`
/// partial-update gate), pre-reads row existence to route INSERT vs UPDATE, then
/// replaces the EXDATE registry when the envelope carried `recurrence_exceptions`
/// and the upsert actually landed. The delete path LWW-gates the parent row and,
/// on apply, pre-tombstones every cascading child / edge row before SQLite's
/// `ON DELETE CASCADE` removes them.
/// Generated successors use one deterministic UUIDv8 identity. A distinct task
/// id claiming an already-used recurrence instance key is therefore invalid
/// input, not an identity split to merge.
public struct TaskApplier: EntityApplier {
  public init() {}

  public var handledEntityTypes: [String] { [EntityKind.task.asString] }

  public func applyUpsert(
    _ db: Database, envelope: SyncEnvelope, tieBreak: LwwTieBreak, applyTs: String
  ) throws -> EntityApplyOutcome {
    let repairTargets = try ApplyTask.applyTaskUpsert(
      db, entityId: envelope.entityId, payload: envelope.payload,
      version: envelope.version.description,
      tieBreak: tieBreak, applyTs: applyTs, payloadSchemaVersion: envelope.payloadSchemaVersion)
    if !repairTargets.isEmpty {
      return .repairRequired(
        .propagateTaskRollover(
          targets: repairTargets,
          additionalFloor: envelope.version))
    }
    return .applied
  }

  public func applyDelete(
    _ db: Database, envelope: SyncEnvelope, applyTs: String
  ) throws -> EntityApplyOutcome {
    let result = try ApplyTask.applyTaskDeleteWithRepairs(
      db, entityId: envelope.entityId, version: envelope.version.description, applyTs: applyTs)
    switch result.decision {
    case .applied:
      guard !result.repairTargets.isEmpty else { return .applied }
      // A delete that also normalizes adjacent recurrence rows still needs the
      // deleted task's tombstone. Returning `.repairRequired` makes the generic
      // delete finalizer defer tombstone creation, so author it here atomically
      // before the host mints the neighboring convergence writes.
      try Tombstone.createTombstone(
        db, entityType: EntityName.task, entityId: envelope.entityId,
        version: envelope.version.description, deletedAt: applyTs)
      return .repairRequired(
        .propagateTaskRollover(
          targets: result.repairTargets, additionalFloor: envelope.version))
    case .rejected(let localVersion):
      return .lwwRejected(localVersion: localVersion)
    }
  }
}

enum ApplyTask {

  // MARK: - Upsert

  static func applyTaskUpsert(
    _ db: Database, entityId: String, payload: String, version: String,
    tieBreak: LwwTieBreak, applyTs: String,
    payloadSchemaVersion: UInt32 = LorvexVersion.payloadSchemaVersion
  ) throws -> [TaskGraphRepairTarget] {
    let parsed = try buildTaskRow(
      db, taskId: entityId, payload: payload, version: version,
      payloadSchemaVersion: payloadSchemaVersion)
    let local = try TaskSyncRow.load(db, id: entityId)
    let incoming = try TaskSyncRow.materialize(
      parsed, over: local, payloadSchemaVersion: payloadSchemaVersion)
    var repairIntent: TaskRegisterIntent = []
    var needsRootReemit = false
    var joined: TaskSyncRow
    if let local {
      // Live equal-clock collisions use the deterministic canonical-byte join.
      // The explicit shadow-promotion path has already proven equal base-row
      // provenance. Its synthesized payload is the complete local projection
      // overlaid with fields this older build had truncated, so those incoming
      // bytes must repair the equal-clock register rather than lose to the
      // truncated projection's byte ordering.
      let merge = try TaskSyncRow.merged(
        local: local, incoming: incoming,
        preferIncomingOnEqual: tieBreak == .shadowPromotion)
      joined = merge.row
      repairIntent.formUnion(merge.repairIntent)
      needsRootReemit = merge.needsRootReemit
    } else {
      joined = incoming
    }
    let incomingReconciliation = try TaskRolloverReconciliation.reconcileIncoming(
      db, row: joined)
    joined = incomingReconciliation.row
    repairIntent.formUnion(incomingReconciliation.repairIntent)
    let row = joined.asApplyRow()
    let rowExists = local != nil

    let taskUpsertLanded: Bool
    if rowExists {
      // A group can win under an equal or older transport HLC. The grouped join
      // already performed the authoritative comparison, so the SQL write must
      // allow the joined high-water mark to equal the stored row version.
      if joined != local {
        try executeTaskUpdate(db, row: row, tieBreak: .allowEqual)
        taskUpsertLanded = db.changesCount > 0
      } else {
        taskUpsertLanded = false
      }
    } else {
      taskUpsertLanded = try executeTaskInsert(db, row: row)
    }

    // EXDATEs live in `task_recurrence_exceptions`. The partial-update presence
    // flag gates the replace so an envelope that omitted the field preserves the
    // local registry. Only run the replace when the upsert actually landed
    // (`changesCount > 0`) — a stale-version envelope rejected by the LWW gate
    // must not mutate the registry.
    if row.recurrenceExceptionsPresent != 0 && taskUpsertLanded {
      do {
        try RecurrenceExceptionsRepo.replaceTaskExceptionsFromJSON(
          db, taskId: entityId, json: row.recurrenceExceptions)
      } catch { throw ApplyError.lift(error) }
    }
    var targets = try TaskRolloverReconciliation.reconcileDescendants(
      db, parentId: entityId, applyTs: applyTs)
    if taskUpsertLanded {
      targets += try TaskGraphReconciliation.repairTargetsAfterTaskWrite(
        db, taskId: entityId, applyTs: applyTs)
    }
    if !repairIntent.isEmpty {
      targets.append(
        .taskUpsert(taskId: entityId, registerIntent: repairIntent))
    } else if needsRootReemit || !targets.isEmpty {
      // A root-only target publishes derived metadata without advancing a
      // register clock. It also carries the triggering parent when descendant
      // normalization bypasses the ordinary convergence-reemit callback.
      targets.append(.taskUpsert(taskId: entityId, registerIntent: []))
    }
    return TaskGraphRepairTarget.coalesced(targets)
  }

  /// Whether an equal-HLC semantic collision is a task grouped-register pair.
  /// Exact replay is still terminated by the generic gate before this hook.
  static func isGroupedMergePair(_ db: Database, envelope: SyncEnvelope) throws -> Bool {
    guard envelope.operation == .upsert, envelope.entityType == .task,
      let local = try TaskSyncRow.load(db, id: envelope.entityId)
    else { return false }
    let parsed = try buildTaskRow(
      db, taskId: envelope.entityId, payload: envelope.payload,
      version: envelope.version.description,
      payloadSchemaVersion: envelope.payloadSchemaVersion)
    _ = try TaskSyncRow.materialize(
      parsed, over: local, payloadSchemaVersion: envelope.payloadSchemaVersion)
    return true
  }

  /// A stale whole-row task may still carry a winning independent register or
  /// the earlier immutable creation timestamp.
  static func staleIncomingRegisterWins(
    _ db: Database, envelope: SyncEnvelope
  ) throws -> Bool {
    guard envelope.operation == .upsert, envelope.entityType == .task,
      let local = try TaskSyncRow.load(db, id: envelope.entityId)
    else { return false }
    let parsed = try buildTaskRow(
      db, taskId: envelope.entityId, payload: envelope.payload,
      version: envelope.version.description,
      payloadSchemaVersion: envelope.payloadSchemaVersion)
    let incoming = try TaskSyncRow.materialize(
      parsed, over: local, payloadSchemaVersion: envelope.payloadSchemaVersion)
    return try TaskSyncRow.staleIncomingRegisterWins(local: local, incoming: incoming)
  }

  /// Validate the recurrence-companion cross-field schema CHECK on `tasks`
  /// against the EFFECTIVE post-write row — for each column the envelope value
  /// when the field is present, otherwise the preserved local value (`nil` for a
  /// fresh insert):
  ///
  ///   * `CHECK (recurrence IS NULL OR (due_date IS NOT NULL AND
  ///     recurrence_group_id IS NOT NULL AND canonical_occurrence_date IS NOT
  ///     NULL))`
  ///
  /// Surfacing a violation as ``ApplyError/invalidPayload(_:)`` keeps a
  /// deterministic SQLITE_CONSTRAINT from escaping the applier and wedging the
  /// inbound batch. Evaluating the MERGED row (not the payload alone) is required
  /// because the partial-update UPDATE preserves local columns for absent fields,
  /// so a payload that sets `recurrence` while omitting `due_date` is valid
  /// exactly when the local `due_date` is non-null.
  private static func validateTaskCrossFieldInvariants(
    row: TaskRow, local: Row?, entityId: String
  ) throws {
    func effective(present: Int64, bound: String?, column: String) -> String? {
      if present != 0 { return bound }
      guard let local else { return nil }
      let value: String? = local[column]
      return value
    }
    let dueDate = effective(present: row.dueDatePresent, bound: row.dueDate, column: "due_date")
    let recurrence = effective(
      present: row.recurrencePresent, bound: row.recurrence, column: "recurrence")
    let recurrenceGroupId = effective(
      present: row.recurrenceGroupIdPresent, bound: row.recurrenceGroupId,
      column: "recurrence_group_id")
    let canonicalOccurrenceDate = effective(
      present: row.canonicalOccurrenceDatePresent, bound: row.canonicalOccurrenceDate,
      column: "canonical_occurrence_date")

    if recurrence != nil,
      dueDate == nil || recurrenceGroupId == nil || canonicalOccurrenceDate == nil
    {
      throw ApplyError.invalidPayload(
        "task \(entityId) violates schema CHECK: recurrence requires non-null due_date, "
          + "recurrence_group_id, and canonical_occurrence_date")
    }
  }

  // MARK: - Row build

  /// Fully-typed row state ready to bind into the partial-update UPDATE or the
  /// fresh-row INSERT. Every nullable column travels as a `(value, present)`
  /// pair so the UPDATE's `CASE WHEN :col_present THEN :col ELSE tasks.col END`
  /// gate can preserve the local column when the envelope omits the field.
  struct TaskRow {
    var entityId: String
    var title: String
    var body: String?
    var bodyPresent: Int64
    var rawInput: String?
    var rawInputPresent: Int64
    var aiNotes: String?
    var aiNotesPresent: Int64
    var status: String
    var listId: String?
    var priority: Int64?
    var priorityPresent: Int64
    var dueDate: String?
    var dueDatePresent: Int64
    var estimatedMinutes: Int64?
    var estimatedMinutesPresent: Int64
    var recurrence: String?
    var recurrencePresent: Int64
    var recurrenceExceptions: String?
    var recurrenceExceptionsPresent: Int64
    var spawnedFrom: String?
    var spawnedFromPresent: Int64
    var spawnedFromVersion: String?
    var spawnedFromVersionPresent: Int64
    var recurrenceGroupId: String?
    var recurrenceGroupIdPresent: Int64
    var canonicalOccurrenceDate: String?
    var canonicalOccurrenceDatePresent: Int64
    var createdAt: String
    var updatedAt: String
    var completedAt: String?
    var completedAtPresent: Int64
    var lastDeferredAt: String?
    var lastDeferredAtPresent: Int64
    var lastDeferReason: String?
    var lastDeferReasonPresent: Int64
    var plannedDate: String?
    var plannedDatePresent: Int64
    var availableFrom: String?
    var availableFromPresent: Int64
    var deferCount: Int64
    var deferCountPresent: Int64
    var recurrenceInstanceKey: String?
    var recurrenceInstanceKeyPresent: Int64
    var archivedAt: String?
    var archivedAtPresent: Int64
    var contentVersion: String
    var scheduleVersion: String
    var lifecycleVersion: String
    var archiveVersion: String
    var recurrenceRolloverState: String
    var recurrenceSuccessorId: String?
    var recurrenceSuccessorIdPresent: Int64
    var version: String
  }

  private static func throwOnValidationFailure(
    _ result: Result<Void, ValidationError>, _ entityId: String, _ field: String
  ) throws {
    if case .failure(let e) = result {
      throw ApplyError.invalidPayload(
        "task \(entityId) \(field) failed validation: \(e.description)")
    }
  }

  /// Parse + validate an envelope payload and return the row state ready to bind
  /// into the UPDATE / INSERT templates. `db` is needed for the `list_id`
  /// fallback (canonical inbox list, then oldest remaining list).
  static func buildTaskRow(
    _ db: Database, taskId entityId: String, payload: String, version: String,
    payloadSchemaVersion: UInt32 = LorvexVersion.payloadSchemaVersion
  ) throws -> TaskRow {
    let val = try ApplyJSON.parseObject(payload)

    // --- text columns: title + free-text (body, raw_input, ai_notes) ---
    let titleRaw = try ApplyJSON.requiredStr(val, "title", entity: "task")
    let bodyTri = try ApplyAggregate.optionalStrPreservingEmpty(val, "body", "task")
    let rawInputTri = try ApplyAggregate.optionalStrPreservingEmpty(val, "raw_input", "task")
    let aiNotesTri = try ApplyAggregate.optionalStrPreservingEmpty(val, "ai_notes", "task")
    let titleOwned = ApplyAggregate.scrub(titleRaw)
    let bodyValidate = ApplyAggregate.scrubOpt(ApplyAggregate.nullableStrOrClear(bodyTri))
    let rawInputValidate = ApplyAggregate.scrubOpt(ApplyAggregate.nullableStrOrClear(rawInputTri))
    let aiNotesValidate = ApplyAggregate.scrubOpt(ApplyAggregate.nullableStrOrClear(aiNotesTri))

    try throwOnValidationFailure(ValidationText.validateTitle(titleOwned), entityId, "title")
    if let b = bodyValidate {
      try throwOnValidationFailure(ValidationText.validateBody(b), entityId, "body")
    }
    if let notes = aiNotesValidate {
      try throwOnValidationFailure(ValidationText.validateBody(notes), entityId, "ai_notes")
    }
    if let input = rawInputValidate {
      try throwOnValidationFailure(ValidationText.validateBody(input), entityId, "raw_input")
    }

    // --- status ---
    let statusStr = try ApplyJSON.requiredStr(val, "status", entity: "task")
    if !(statusStr == StatusName.open || statusStr == StatusName.inProgress
      || statusStr == StatusName.completed
      || statusStr == StatusName.cancelled || statusStr == StatusName.someday)
    {
      throw ApplyError.forwardCompatOrInvalid(
        payloadSchemaVersion: payloadSchemaVersion,
        "task \(entityId) status \(applyDebugQuoted(statusStr)) must be one of "
          + "open|in_progress|completed|cancelled|someday")
    }

    // --- list_id fallback ---
    let listIdOwned = try resolveListId(db, val)

    // --- scheduling columns ---
    let priorityTri = try ApplyAggregate.optionalInt64PreservingNull(val, "priority", "task")
    if case .set(let p) = priorityTri {
      try throwOnValidationFailure(ValidationNumeric.validatePriority(p), entityId, "priority")
    }
    let dueDateTri = try ApplyAggregate.optionalStrPreservingEmpty(val, "due_date", "task")
    if case .set(let d) = dueDateTri {
      try throwOnValidationFailure(ValidationFormat.validateDateFormat(d), entityId, "due_date")
    }
    let estimatedMinutesTri =
      try ApplyAggregate.optionalInt64PreservingNull(val, "estimated_minutes", "task")
    if case .set(let m) = estimatedMinutesTri {
      try throwOnValidationFailure(
        ValidationNumeric.validateEstimatedMinutes(m), entityId, "estimated_minutes")
    }
    // --- recurrence-related text columns ---
    // Route inbound `recurrence` through the canonical task normalizer at the
    // trust boundary (matching ``ApplyCalendarEvent``), so a peer can't ship a
    // rule that violates the recurrence contract and have it stored verbatim.
    // The `.set` value is replaced with its canonical form; a whitespace-only
    // rule normalizes to a clear. A rule a newer-schema peer authored that this
    // build's normalizer rejects is forward-compat data to RETAIN
    // (`deferForwardCompat`); a same-version reject is corruption
    // (`invalidPayload` → drop). `.unset` / `.clear` pass through untouched so
    // the partial-update preserve/clear semantics are unchanged.
    let recurrenceTri: Patch<String>
    switch try ApplyAggregate.optionalStrPreservingEmpty(val, "recurrence", "task") {
    case .unset:
      recurrenceTri = .unset
    case .clear:
      recurrenceTri = .clear
    case .set(let raw):
      switch ValidationRecurrence.normalizeTaskRecurrence(raw) {
      case .success(let canonical):
        if let canonical {
          recurrenceTri = .set(canonical)
        } else {
          recurrenceTri = .clear
        }
      case .failure(let e):
        throw ApplyError.forwardCompatOrInvalid(
          payloadSchemaVersion: payloadSchemaVersion,
          "task \(entityId) recurrence: \(e.description)")
      }
    }
    let recurrenceExceptionsTri =
      try ApplyAggregate.optionalStrPreservingEmpty(val, "recurrence_exceptions", "task")
    let spawnedFromTri = try ApplyAggregate.optionalStrPreservingEmpty(val, "spawned_from", "task")
    let spawnedFromVersionTri =
      try ApplyAggregate.optionalStrPreservingEmpty(val, "spawned_from_version", "task")
    let recurrenceGroupIdTri =
      try ApplyAggregate.optionalStrPreservingEmpty(val, "recurrence_group_id", "task")

    let createdAtStr = try ApplyJSON.requiredStr(val, "created_at", entity: "task")
    let updatedAtStr = try ApplyJSON.requiredStr(val, "updated_at", entity: "task")

    // --- lifecycle columns ---
    // `status` and `completed_at` are one lifecycle value, not two independent
    // LWW fields. Accepting them independently can produce a completed task
    // that never appears in completion history, or an open task that still
    // counts as completed. Older payloads may omit nullable fields, so a
    // non-completed status treats omission as an authoritative clear. A
    // completed status must carry the instant that gives the transition its
    // meaning; never fabricate that timestamp at the receiving device.
    let completedAtTri: Patch<String>
    let incomingCompletedAt =
      try ApplyAggregate.optionalStrPreservingEmpty(val, "completed_at", "task")
    if statusStr == StatusName.completed {
      guard case .set(let rawCompletedAt) = incomingCompletedAt,
        let canonicalCompletedAt = SyncTimestamp.parse(rawCompletedAt)?.asString
      else {
        throw ApplyError.forwardCompatOrInvalid(
          payloadSchemaVersion: payloadSchemaVersion,
          "task \(entityId) completed status requires a valid UTC RFC 3339 completed_at")
      }
      completedAtTri = .set(canonicalCompletedAt)
    } else {
      if case .set = incomingCompletedAt {
        throw ApplyError.forwardCompatOrInvalid(
          payloadSchemaVersion: payloadSchemaVersion,
          "task \(entityId) non-completed status must not carry completed_at")
      }
      completedAtTri = .clear
    }
    let lastDeferredAtTri =
      try ApplyAggregate.optionalStrPreservingEmpty(val, "last_deferred_at", "task")
    let lastDeferReasonTri =
      try ApplyAggregate.optionalStrPreservingEmpty(val, "last_defer_reason", "task")
    let lastDeferReasonOwned = ApplyAggregate.scrubOpt(
      ApplyAggregate.nullableStrOrClear(lastDeferReasonTri))
    if let reason = lastDeferReasonOwned {
      if !DeferReasonName.isValid(reason) {
        throw ApplyError.forwardCompatOrInvalid(
          payloadSchemaVersion: payloadSchemaVersion,
          "task \(entityId) last_defer_reason \(applyDebugQuoted(reason)) must be one of: "
            + DeferReasonName.allDeferReasons.joined(separator: "|"))
      }
    }
    let plannedDateTri = try ApplyAggregate.optionalStrPreservingEmpty(val, "planned_date", "task")
    if case .set(let d) = plannedDateTri {
      try throwOnValidationFailure(
        ValidationFormat.validateDateFormat(d), entityId, "planned_date")
    }
    let availableFromTri = try ApplyAggregate.optionalStrPreservingEmpty(
      val, "available_from", "task")
    if case .set(let d) = availableFromTri {
      try throwOnValidationFailure(
        ValidationFormat.validateDateFormat(d), entityId, "available_from")
    }
    let deferCountTri = try ApplyAggregate.optionalInt64PreservingNull(val, "defer_count", "task")
    if case .set(let n) = deferCountTri {
      if n < 0 {
        throw ApplyError.invalidPayload(
          "task \(entityId) defer_count must be non-negative (got \(n))")
      }
    }
    let recurrenceInstanceKeyTri =
      try ApplyAggregate.optionalStrPreservingEmpty(val, "recurrence_instance_key", "task")
    let canonicalOccurrenceDateTri =
      try ApplyAggregate.optionalStrPreservingEmpty(val, "canonical_occurrence_date", "task")
    if case .set(let d) = canonicalOccurrenceDateTri {
      try throwOnValidationFailure(
        ValidationFormat.validateDateFormat(d), entityId, "canonical_occurrence_date")
    }
    let archivedAtTri = try ApplyAggregate.optionalStrPreservingEmpty(val, "archived_at", "task")

    // The row HLC is only the transport/delete high-water mark. Task content,
    // schedule, lifecycle, and archive state are four independent registers.
    // Direct parser tests written before the register split may omit these
    // fields, so this inner helper defaults them to the envelope HLC; the public
    // sync contract still requires every field on every Upsert.
    func registerVersion(_ key: String) throws -> String {
      let raw = try ApplyJSON.optionalStr(val, key, entity: "task") ?? version
      guard let clock = try? Hlc.parseCanonical(raw),
        let envelopeClock = try? Hlc.parseCanonical(version), clock <= envelopeClock
      else {
        throw ApplyError.invalidPayload(
          "task \(entityId) \(key) must be a canonical HLC no newer than version")
      }
      return raw
    }
    let contentVersion = try registerVersion("content_version")
    let scheduleVersion = try registerVersion("schedule_version")
    let lifecycleVersion = try registerVersion("lifecycle_version")
    let archiveVersion = try registerVersion("archive_version")

    let recurrenceSuccessorIdTri =
      try ApplyAggregate.optionalStrPreservingEmpty(val, "recurrence_successor_id", "task")
    let rolloverDefault =
      (statusStr == StatusName.completed || statusStr == StatusName.cancelled) ? "ended" : "none"
    let recurrenceRolloverState =
      try ApplyJSON.optionalStr(val, "recurrence_rollover_state", entity: "task") ?? rolloverDefault
    guard ["none", "authorized", "revoked", "ended"].contains(recurrenceRolloverState) else {
      throw ApplyError.forwardCompatOrInvalid(
        payloadSchemaVersion: payloadSchemaVersion,
        "task \(entityId) recurrence_rollover_state \(applyDebugQuoted(recurrenceRolloverState)) "
          + "must be one of none|authorized|revoked|ended")
    }

    // --- split each tri-state into its (value, present) pair, re-scrub text ---
    let (bodyBind, bodyPresent) = ApplyAggregate.splitPartialStrValue(bodyTri)
    let (rawInputBind, rawInputPresent) = ApplyAggregate.splitPartialStrValue(rawInputTri)
    let (aiNotesBind, aiNotesPresent) = ApplyAggregate.splitPartialStrValue(aiNotesTri)
    let (priorityBind, priorityPresent) = ApplyAggregate.splitPartialInt64Value(priorityTri)
    let (dueDateBind, dueDatePresent) = ApplyAggregate.splitPartialStrValue(dueDateTri)
    let (estimatedMinutesBind, estimatedMinutesPresent) =
      ApplyAggregate.splitPartialInt64Value(estimatedMinutesTri)
    let (recurrenceBind, recurrencePresent) = ApplyAggregate.splitPartialStrValue(recurrenceTri)
    let (recurrenceExceptionsBind, recurrenceExceptionsPresent) =
      ApplyAggregate.splitPartialStrValue(recurrenceExceptionsTri)
    let (spawnedFromBind, spawnedFromPresent) = ApplyAggregate.splitPartialStrValue(spawnedFromTri)
    let (spawnedFromVersionBind, spawnedFromVersionPresent) =
      ApplyAggregate.splitPartialStrValue(spawnedFromVersionTri)
    let (recurrenceGroupIdBind, recurrenceGroupIdPresent) =
      ApplyAggregate.splitPartialStrValue(recurrenceGroupIdTri)
    let (completedAtBind, completedAtPresent) = ApplyAggregate.splitPartialStrValue(completedAtTri)
    let (lastDeferredAtBind, lastDeferredAtPresent) =
      ApplyAggregate.splitPartialStrValue(lastDeferredAtTri)
    let (_, lastDeferReasonPresent) = ApplyAggregate.splitPartialStrValue(lastDeferReasonTri)
    let (plannedDateBind, plannedDatePresent) = ApplyAggregate.splitPartialStrValue(plannedDateTri)
    let (availableFromBind, availableFromPresent) =
      ApplyAggregate.splitPartialStrValue(availableFromTri)
    let (deferCountValue, deferCountPresent) = ApplyAggregate.splitPartialInt64Value(deferCountTri)
    let deferCount = deferCountValue ?? 0
    let (recurrenceInstanceKeyBind, recurrenceInstanceKeyPresent) =
      ApplyAggregate.splitPartialStrValue(recurrenceInstanceKeyTri)
    let (canonicalOccurrenceDateBind, canonicalOccurrenceDatePresent) =
      ApplyAggregate.splitPartialStrValue(canonicalOccurrenceDateTri)
    let (archivedAtBind, archivedAtPresent) = ApplyAggregate.splitPartialStrValue(archivedAtTri)
    let (recurrenceSuccessorIdBind, recurrenceSuccessorIdPresent) =
      ApplyAggregate.splitPartialStrValue(recurrenceSuccessorIdTri)

    return TaskRow(
      entityId: entityId,
      title: titleOwned,
      body: ApplyAggregate.scrubOpt(bodyBind),
      bodyPresent: bodyPresent,
      rawInput: ApplyAggregate.scrubOpt(rawInputBind),
      rawInputPresent: rawInputPresent,
      aiNotes: ApplyAggregate.scrubOpt(aiNotesBind),
      aiNotesPresent: aiNotesPresent,
      status: statusStr,
      listId: listIdOwned,
      priority: priorityBind,
      priorityPresent: priorityPresent,
      dueDate: dueDateBind,
      dueDatePresent: dueDatePresent,
      estimatedMinutes: estimatedMinutesBind,
      estimatedMinutesPresent: estimatedMinutesPresent,
      recurrence: recurrenceBind,
      recurrencePresent: recurrencePresent,
      recurrenceExceptions: recurrenceExceptionsBind,
      recurrenceExceptionsPresent: recurrenceExceptionsPresent,
      spawnedFrom: spawnedFromBind,
      spawnedFromPresent: spawnedFromPresent,
      spawnedFromVersion: spawnedFromVersionBind,
      spawnedFromVersionPresent: spawnedFromVersionPresent,
      recurrenceGroupId: recurrenceGroupIdBind,
      recurrenceGroupIdPresent: recurrenceGroupIdPresent,
      canonicalOccurrenceDate: canonicalOccurrenceDateBind,
      canonicalOccurrenceDatePresent: canonicalOccurrenceDatePresent,
      createdAt: createdAtStr,
      updatedAt: updatedAtStr,
      completedAt: completedAtBind,
      completedAtPresent: completedAtPresent,
      lastDeferredAt: lastDeferredAtBind,
      lastDeferredAtPresent: lastDeferredAtPresent,
      lastDeferReason: lastDeferReasonOwned,
      lastDeferReasonPresent: lastDeferReasonPresent,
      plannedDate: plannedDateBind,
      plannedDatePresent: plannedDatePresent,
      availableFrom: availableFromBind,
      availableFromPresent: availableFromPresent,
      deferCount: deferCount,
      deferCountPresent: deferCountPresent,
      recurrenceInstanceKey: recurrenceInstanceKeyBind,
      recurrenceInstanceKeyPresent: recurrenceInstanceKeyPresent,
      archivedAt: archivedAtBind,
      archivedAtPresent: archivedAtPresent,
      contentVersion: contentVersion,
      scheduleVersion: scheduleVersion,
      lifecycleVersion: lifecycleVersion,
      archiveVersion: archiveVersion,
      recurrenceRolloverState: recurrenceRolloverState,
      recurrenceSuccessorId: recurrenceSuccessorIdBind,
      recurrenceSuccessorIdPresent: recurrenceSuccessorIdPresent,
      version: version)
  }

  /// Resolve the row's `list_id`. `tasks.list_id` is NOT NULL, so when the
  /// envelope omits the field (or sets it to an empty string) we pick the
  /// canonical inbox list when it exists locally, otherwise the oldest remaining
  /// list (ties broken by id). If no lists exist, returns `nil` and the FK
  /// preflight defers the envelope until a list is synced.
  private static func resolveListId(_ db: Database, _ val: [String: JSONValue]) throws -> String? {
    let payloadListId = try ApplyJSON.optionalStr(val, "list_id", entity: "task")
    if let id = payloadListId, !id.isEmpty {
      do {
        if try ApplyFk.rowExists(db, "lists", "id", id) {
          return id
        }
        if try Tombstone.getTombstone(
          db, entityType: EntityName.list, entityId: id) != nil
        {
          return try inboxOrOldestListId(db)
        }
      } catch { throw ApplyError.lift(error) }
      return id
    }
    return try inboxOrOldestListId(db)
  }

  private static func inboxOrOldestListId(_ db: Database) throws -> String? {
    do {
      if let inbox = try String.fetchOne(
        db, sql: "SELECT id FROM lists WHERE id = ?", arguments: [inboxListId])
      {
        return inbox
      }
      return try String.fetchOne(
        db, sql: "SELECT id FROM lists ORDER BY created_at ASC, id ASC LIMIT 1")
    } catch { throw ApplyError.lift(error) }
  }

}

import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Per-entity apply handlers for the day-scoped aggregates whose natural primary
/// key is a `date` string and which embed one or more materialization child
/// tables: `current_focus` (→ `current_focus_items`), `focus_schedule` (→
/// `focus_schedule_blocks`), and `daily_review` (→ `daily_review_task_links` /
/// `daily_review_list_links`).
///
/// Each upsert runs the sync-mode parent upsert (the envelope is authoritative
/// for `timezone` / `created_at`) and rebuilds the embedded child rows atomically
/// — but only when the parent row was actually written (the LWW gate accepted).
/// The child rows have no `version` column, no outbox enqueue site, and no
/// dispatch entry: their state is wholly derived from the parent payload and
/// rebuilt on every apply, so the parent delete cascades them via FK WITHOUT
/// per-edge tombstones (no peer can resurrect a stale edge). Each delete carries
/// a defense-in-depth LWW gate via ``ApplyLww/lwwGatedDelete``.
enum ApplyDayScoped {

  struct ReferenceRepair: Sendable, Equatable {
    let operation: SyncOperation
    let removedTaskReference: Bool
    let removedCalendarReference: Bool
  }

  /// The complete nested wire shape this build understands for one
  /// `focus_schedule.blocks` entry. The production manifest freezes this nested
  /// shape and rejects an unknown key before dispatch. This duplicate inner
  /// guard protects direct applier callers and documents why nested additions
  /// cannot use top-level payload shadow.
  private static let focusScheduleBlockKeys: Set<String> = [
    "block_type", "start_minutes", "end_minutes", "task_id", "calendar_event_id",
    "event_source", "title",
  ]

  /// A present `null` maps to an empty array (an explicit clear); a present array
  /// maps to its string list. A non-array, or an array with a non-string element,
  /// errors. Callers apply absence-preserving semantics by gating on key presence
  /// BEFORE calling (an ABSENT key preserves the existing children upstream), so
  /// in practice only present values reach here; the absent arm is a defensive
  /// fallback that maps to the empty array.
  private static func stringArrayField(_ obj: [String: JSONValue], _ key: String) throws
    -> [String]
  {
    switch obj[key] {
    case .none, .null:
      return []
    case .array(let items):
      return try items.map { entry in
        guard case .string(let s) = entry else {
          throw ApplyError.invalidPayload(
            "invalid day-scoped payload: \(key) must contain only strings")
        }
        return s
      }
    default:
      throw ApplyError.invalidPayload(
        "invalid day-scoped payload: \(key) must be an array of strings")
    }
  }

  private static func requiredArrayField(
    _ obj: [String: JSONValue], _ key: String, _ entity: String
  )
    throws -> [JSONValue]
  {
    if case .array(let items)? = obj[key] { return items }
    throw ApplyError.invalidPayload("\(entity) payload: \(key) must be an array")
  }

  /// Validate embedded storage identities with the same canonical rules as a
  /// top-level sync envelope. Day-scoped children are soft references, so SQL
  /// foreign keys cannot protect this boundary from malformed peer values.
  private static func validatedEntityIdArray(
    _ obj: [String: JSONValue], key: String, entity: String, kind: EntityKind
  ) throws -> [String] {
    let values = try stringArrayField(obj, key)
    for (index, value) in values.enumerated() {
      guard case .success = SyncEntityId.validateForKind(kind, value) else {
        throw ApplyError.invalidPayload(
          "invalid \(entity) payload: \(key)[\(index)] has a non-canonical identity")
      }
    }
    return values
  }

  /// Parse a time field that may be an integer (minutes from midnight) or an
  /// "HH:MM" string. Out-of-i64-range / non-time values error rather than
  /// silently collapsing to 0.
  private static func parseRequiredTimeField(_ value: JSONValue?, _ field: String) throws -> Int64 {
    switch value {
    case .int(let i):
      return i
    case .string(let raw):
      guard let minutes = Parsing.parseHhmmToMinutes(raw) else {
        throw ApplyError.invalidPayload(
          "invalid day-scoped payload: \(field) has invalid time \(raw)")
      }
      return minutes
    case .none:
      throw ApplyError.invalidPayload(
        "invalid day-scoped payload: missing required field \(field)")
    default:
      throw ApplyError.invalidPayload(
        "invalid day-scoped payload: \(field) must be an integer or HH:MM string")
    }
  }

  /// Shared canonical sync UUID check exposed internally for focused tests.
  static func isCanonicalUUID(_ s: String) -> Bool {
    SyncEntityId.isCanonicalUuid(s)
  }

  // MARK: - current_focus

  @discardableResult
  static func applyCurrentFocusUpsert(
    _ db: Database, entityId: String, payload: String, version: String, tieBreak: LwwTieBreak
  ) throws -> ReferenceRepair? {
    let val = try ApplyJSON.parseObject(payload)
    let date = entityId
    let briefing = try ApplyJSON.optionalStr(val, "briefing", entity: "current_focus")
    let timezone = try ApplyJSON.optionalStr(val, "timezone", entity: "current_focus")
    let createdAt = try ApplyJSON.requiredStr(val, "created_at", entity: "current_focus")
    let updatedAt = try ApplyJSON.requiredStr(val, "updated_at", entity: "current_focus")

    let wrote: Bool
    do {
      wrote = try CurrentFocusItemsRepo.syncUpsertCurrentFocus(
        db, date: date, briefing: briefing, timezone: timezone, version: version,
        createdAt: createdAt, updatedAt: updatedAt, versionCmp: tieBreak.sqlOp)
    } catch { throw ApplyError.lift(error) }

    // Absence-preserving (SYNC-MED-2): rebuild the items only when the envelope
    // carried an explicit `task_ids` value (an array, including empty). An absent
    // key preserves the existing items rather than wiping them, so two receivers
    // observing different envelope subsets do not diverge under the same version.
    if wrote && val["task_ids"] != nil {
      let taskIds = try validatedEntityIdArray(
        val, key: "task_ids", entity: "current_focus", kind: .task)
      let normalized = try TaskGraphReconciliation.removingIneligibleFocusTasks(
        db, from: taskIds)
      do {
        try CurrentFocusItemsRepo.materializeFocusItems(
          db, date: date, taskIds: normalized.taskIds)
      } catch { throw ApplyError.lift(error) }
      guard normalized.removed else { return nil }
      if normalized.taskIds.isEmpty {
        try CurrentFocusItemsRepo.deleteCurrentFocus(db, date: date)
        return ReferenceRepair(
          operation: .delete, removedTaskReference: true,
          removedCalendarReference: false)
      }
      return ReferenceRepair(
        operation: .upsert, removedTaskReference: true,
        removedCalendarReference: false)
    }
    return nil
  }

  static func applyCurrentFocusDelete(_ db: Database, entityId: String, version: String) throws {
    try ApplyLww.lwwGatedDelete(
      db, table: "current_focus", pkColumns: ["date"], pkValues: [entityId],
      incomingVersion: version)
  }

  // MARK: - focus_schedule

  @discardableResult
  static func applyFocusScheduleUpsert(
    _ db: Database, entityId: String, payload: String, version: String, tieBreak: LwwTieBreak,
    payloadSchemaVersion: UInt32 = LorvexVersion.payloadSchemaVersion
  ) throws -> ReferenceRepair? {
    let val = try ApplyJSON.parseObject(payload)
    let date = entityId
    let rationale = try ApplyJSON.optionalStr(val, "rationale", entity: "focus_schedule")
    let timezone = try ApplyJSON.optionalStr(val, "timezone", entity: "focus_schedule")
    let createdAt = try ApplyJSON.requiredStr(val, "created_at", entity: "focus_schedule")
    let updatedAt = try ApplyJSON.requiredStr(val, "updated_at", entity: "focus_schedule")

    let blocks = try requiredArrayField(val, "blocks", "focus_schedule")
    var entries: [FocusScheduleBlocksRepo.ScheduleBlockEntry] = []
    entries.reserveCapacity(blocks.count)
    for block in blocks {
      guard let obj = ApplyJSON.object(block) else {
        throw ApplyError.invalidPayload(
          "invalid day-scoped payload: blocks[*] must be an object")
      }
      let unknownKeys = obj.keys.filter { !focusScheduleBlockKeys.contains($0) }.sorted()
      if !unknownKeys.isEmpty {
        throw ApplyError.forwardCompatOrInvalid(
          payloadSchemaVersion: payloadSchemaVersion,
          "invalid day-scoped payload: blocks[*] contains unknown key(s): "
            + unknownKeys.joined(separator: ", "))
      }
      let blockType: String
      switch obj["block_type"] {
      case .none, .null:
        blockType = "buffer"
      case .string(let s):
        // Validate against the closed `FocusBlockType` set before the value
        // reaches the CHECK-constrained column. Production manifest preflight
        // rejects enum drift first; this inner classification keeps direct
        // applier calls deterministic instead of surfacing an opaque SQLite
        // constraint error.
        guard FocusBlockType.parse(s) != nil else {
          throw ApplyError.forwardCompatOrInvalid(
            payloadSchemaVersion: payloadSchemaVersion,
            "invalid day-scoped payload: blocks[*].block_type '\(s)' is not one of "
              + "{task, buffer, event}")
        }
        blockType = s
      default:
        throw ApplyError.invalidPayload(
          "invalid day-scoped payload: blocks[*].block_type must be a string")
      }
      let startMinutes = try parseRequiredTimeField(obj["start_minutes"], "blocks[*].start_minutes")
      let endMinutes = try parseRequiredTimeField(obj["end_minutes"], "blocks[*].end_minutes")
      // Validate the range before storing: the integer branch accepts arbitrary
      // i64, but the schema CHECK does not enforce 0..=1440 or start <= end.
      if !(0...1440).contains(startMinutes) || !(0...1440).contains(endMinutes) {
        throw ApplyError.invalidPayload(
          "invalid day-scoped payload: blocks[*] time minutes must be in 0..=1440 "
            + "(got start=\(startMinutes), end=\(endMinutes))")
      }
      if endMinutes <= startMinutes {
        throw ApplyError.invalidPayload(
          "invalid day-scoped payload: blocks[*] end_minutes (\(endMinutes)m) must be after "
            + "start_minutes (\(startMinutes)m)")
      }
      let taskId: String?
      switch obj["task_id"] {
      case .none, .null:
        taskId = nil
      case .string(let s):
        guard case .success = SyncEntityId.validateForKind(.task, s) else {
          throw ApplyError.invalidPayload(
            "invalid day-scoped payload: blocks[*].task_id must be a canonical task UUID or null")
        }
        taskId = s
      default:
        throw ApplyError.invalidPayload(
          "invalid day-scoped payload: blocks[*].task_id must be a string or null")
      }
      // Defensive strip: only canonical calendar_event UUIDs pass; provider keys
      // (EventKit identifiers, VEVENT UIDs) must never leak into synced payloads.
      let calendarEventId: String?
      switch obj["calendar_event_id"] {
      case .none, .null:
        calendarEventId = nil
      case .string(let s) where SyncEntityId.isCanonicalUuid(s):
        calendarEventId = s
      default:
        throw ApplyError.invalidPayload(
          "invalid day-scoped payload: blocks[*].calendar_event_id must be a canonical UUID "
            + "string or null")
      }
      let eventSource: FocusScheduleEventSource?
      switch obj["event_source"] {
      case .null:
        eventSource = nil
      case .string(let raw):
        guard let parsed = FocusScheduleEventSource.parse(raw) else {
          throw ApplyError.invalidPayload(
            "invalid day-scoped payload: blocks[*].event_source must be canonical, provider, "
              + "freeform, or null")
        }
        eventSource = parsed
      case .none:
        throw ApplyError.invalidPayload(
          "invalid day-scoped payload: missing required blocks[*].event_source")
      default:
        throw ApplyError.invalidPayload(
          "invalid day-scoped payload: blocks[*].event_source must be a string or null")
      }
      let title: String?
      switch obj["title"] {
      case .none, .null:
        title = nil
      case .string(let s):
        title = s
      default:
        throw ApplyError.invalidPayload(
          "invalid day-scoped payload: blocks[*].title must be a string or null")
      }
      // Cross-field consistency matches the schema CHECK on
      // `focus_schedule_blocks (block_type, task_id, calendar_event_id, event_source)`.
      // The `block_type`
      // enum, the time range, and the id shapes are each already validated above,
      // but not their combination. Pre-empt the CHECK here so a malformed peer
      // envelope (e.g. a 'task' block with no task_id, or a 'buffer' carrying a
      // calendar_event_id) drops as a typed InvalidPayload skip with a clear reason
      // instead of tripping SQLITE_CONSTRAINT deep in the child materialization.
      //   - task   → task_id NOT NULL, event fields NULL
      //   - event  → source required; only canonical carries calendar_event_id
      //   - buffer → task_id/event fields NULL
      switch blockType {
      case "task":
        if taskId == nil || calendarEventId != nil || eventSource != nil {
          throw ApplyError.invalidPayload(
            "invalid day-scoped payload: block_type 'task' requires a non-null task_id and a "
              + "null calendar_event_id/event_source")
        }
      case "event":
        if taskId != nil {
          throw ApplyError.invalidPayload(
            "invalid day-scoped payload: block_type 'event' requires a null task_id")
        }
        switch eventSource {
        case .some(.canonical) where calendarEventId != nil:
          break
        case .some(.provider) where calendarEventId == nil,
          .some(.freeform) where calendarEventId == nil:
          break
        default:
          throw ApplyError.invalidPayload(
            "invalid day-scoped payload: event blocks require canonical + calendar_event_id, "
              + "or provider/freeform + null calendar_event_id")
        }
      case "buffer":
        if taskId != nil || calendarEventId != nil || eventSource != nil {
          throw ApplyError.invalidPayload(
            "invalid day-scoped payload: block_type 'buffer' requires a null task_id and a null "
              + "calendar_event_id/event_source")
        }
      default:
        break
      }
      entries.append(
        FocusScheduleBlocksRepo.ScheduleBlockEntry(
          blockType: blockType, startMinutes: startMinutes, endMinutes: endMinutes,
          taskId: taskId, calendarEventId: calendarEventId, eventSource: eventSource,
          title: FocusScheduleSnapshot.normalizeBlockForExternalTransfer(
            eventSource: eventSource, calendarEventId: calendarEventId, title: title
          ).title))
    }

    let cmp: FocusScheduleBlocksRepo.SyncVersionCmp =
      tieBreak.allowsEqual ? .greaterOrEqual : .greater
    let wrote: Bool
    do {
      wrote = try FocusScheduleBlocksRepo.syncUpsertFocusSchedule(
        db, date: date, rationale: rationale, timezone: timezone, version: version,
        createdAt: createdAt, updatedAt: updatedAt, versionCmp: cmp)
    } catch { throw ApplyError.lift(error) }
    if !wrote { return nil }

    var normalizedEntries: [FocusScheduleBlocksRepo.ScheduleBlockEntry] = []
    normalizedEntries.reserveCapacity(entries.count)
    var removedTaskReference = false
    var removedCalendarReference = false
    for entry in entries {
      if let taskId = entry.taskId,
        try TaskGraphReconciliation.removingIneligibleFocusTasks(db, from: [taskId]).removed
      {
        removedTaskReference = true
      } else if entry.eventSource == .canonical, let calendarEventId = entry.calendarEventId,
        try isDeletedCanonicalEventReference(db, calendarEventId: calendarEventId)
      {
        removedCalendarReference = true
      } else {
        normalizedEntries.append(entry)
      }
    }

    do {
      try FocusScheduleBlocksRepo.materializeScheduleBlocks(
        db, date: date, blocks: normalizedEntries)
    } catch { throw ApplyError.lift(error) }
    guard removedTaskReference || removedCalendarReference else { return nil }
    if normalizedEntries.isEmpty {
      try db.execute(sql: "DELETE FROM focus_schedule WHERE date = ?1", arguments: [date])
      return ReferenceRepair(
        operation: .delete, removedTaskReference: removedTaskReference,
        removedCalendarReference: removedCalendarReference)
    }
    return ReferenceRepair(
      operation: .upsert, removedTaskReference: removedTaskReference,
      removedCalendarReference: removedCalendarReference)
  }

  /// A missing soft reference may simply mean that CloudKit delivered the day
  /// root before its event, so absence alone is not terminal. An ordinary event
  /// tombstone is the durable proof that a canonical block must be removed.
  private static func isDeletedCanonicalEventReference(
    _ db: Database, calendarEventId: String
  ) throws -> Bool {
    try Tombstone.getTombstone(
      db, entityType: EntityName.calendarEvent, entityId: calendarEventId) != nil
  }

  static func applyFocusScheduleDelete(_ db: Database, entityId: String, version: String) throws {
    try ApplyLww.lwwGatedDelete(
      db, table: "focus_schedule", pkColumns: ["date"], pkValues: [entityId],
      incomingVersion: version)
  }

  // MARK: - daily_review

  static func applyDailyReviewUpsert(
    _ db: Database, entityId: String, payload: String, version: String, tieBreak: LwwTieBreak
  ) throws {
    let val = try ApplyJSON.parseObject(payload)
    let date = entityId
    let summary = try ApplyJSON.requiredStr(val, "summary", entity: "daily_review")
    let mood = try ApplyJSON.optionalInt64(val, "mood", entity: "daily_review")
    let energyLevel = try ApplyJSON.optionalInt64(val, "energy_level", entity: "daily_review")
    // Validate the 1…5 scale at the trust boundary before the SQL bind. An
    // out-of-range value would trip `CHECK (mood/energy_level BETWEEN 1 AND 5)`
    // as a deterministic SQLITE_CONSTRAINT that `applyInbound` treats as
    // batch-fatal, wedging inbound sync; drop the one bad envelope instead.
    try validateDayReviewScale(mood, field: "mood", entityId: date)
    try validateDayReviewScale(energyLevel, field: "energy_level", entityId: date)
    let wins = try ApplyJSON.optionalStr(val, "wins", entity: "daily_review")
    let blockers = try ApplyJSON.optionalStr(val, "blockers", entity: "daily_review")
    let learnings = try ApplyJSON.optionalStr(val, "learnings", entity: "daily_review")
    let timezone = try ApplyJSON.optionalStr(val, "timezone", entity: "daily_review")
    let createdAt = try ApplyJSON.requiredStr(val, "created_at", entity: "daily_review")
    let updatedAt = try ApplyJSON.requiredStr(val, "updated_at", entity: "daily_review")

    let wrote: Bool
    do {
      wrote = try DailyReviewOpsRepo.syncUpsertDailyReview(
        db, date: date, summary: summary, mood: mood, energyLevel: energyLevel, wins: wins,
        blockers: blockers, learnings: learnings, timezone: timezone,
        version: version, createdAt: createdAt, updatedAt: updatedAt, versionCmp: tieBreak.sqlOp)
    } catch { throw ApplyError.lift(error) }

    // Absence-preserving (SYNC-MED-2): rebuild each link collection only when the
    // envelope carried its explicit key (an array, including empty). An absent key
    // preserves the existing links rather than wiping them.
    if wrote {
      if val["linked_task_ids"] != nil {
        let taskIds = try validatedEntityIdArray(
          val, key: "linked_task_ids", entity: "daily_review", kind: .task)
        do {
          try DailyReviewOpsRepo.materializeReviewTaskLinks(db, date: date, taskIds: taskIds)
        } catch { throw ApplyError.lift(error) }
      }
      if val["linked_list_ids"] != nil {
        let listIds = try validatedEntityIdArray(
          val, key: "linked_list_ids", entity: "daily_review", kind: .list)
        do {
          try DailyReviewOpsRepo.materializeReviewListLinks(db, date: date, listIds: listIds)
        } catch { throw ApplyError.lift(error) }
      }
    }
  }

  static func applyDailyReviewDelete(_ db: Database, entityId: String, version: String) throws {
    try ApplyLww.lwwGatedDelete(
      db, table: "daily_reviews", pkColumns: ["date"], pkValues: [entityId],
      incomingVersion: version)
  }

  /// Reject a `daily_review` `mood` / `energy_level` outside the schema's 1…5
  /// scale (NULL passes) at the trust boundary, so a crafted out-of-range value
  /// drops as ``ApplyError/invalidPayload(_:)`` instead of tripping the SQL CHECK
  /// and aborting the whole inbound batch.
  private static func validateDayReviewScale(
    _ value: Int64?, field: String, entityId: String
  ) throws {
    guard let value else { return }
    if !(ValidationLimits.moodMin...ValidationLimits.moodMax).contains(value) {
      throw ApplyError.invalidPayload(
        "daily_review \(entityId) \(field) must be between \(ValidationLimits.moodMin) and "
          + "\(ValidationLimits.moodMax) or null (got \(value))")
    }
  }
}

// MARK: - EntityApplier conformances

public struct CurrentFocusApplier: EntityApplier {
  public init() {}
  public var handledEntityTypes: [String] { [EntityName.currentFocus] }
  public func applyUpsert(
    _ db: Database, envelope: SyncEnvelope, tieBreak: LwwTieBreak, applyTs: String
  ) throws -> EntityApplyOutcome {
    let repair = try ApplyDayScoped.applyCurrentFocusUpsert(
      db, entityId: envelope.entityId, payload: envelope.payload,
      version: envelope.version.description, tieBreak: tieBreak)
    if let repair {
      return .repairRequired(
        .propagateTaskRollover(
          targets: [
            .relatedEntity(
              entityType: .currentFocus, entityId: envelope.entityId,
              operation: repair.operation, knownVersionFloor: envelope.version)
          ],
          additionalFloor: envelope.version))
    }
    return .applied
  }
  public func applyDelete(_ db: Database, envelope: SyncEnvelope, applyTs: String) throws
    -> EntityApplyOutcome
  {
    try ApplyDayScoped.applyCurrentFocusDelete(
      db, entityId: envelope.entityId, version: envelope.version.description)
    return .applied
  }
}

public struct FocusScheduleApplier: EntityApplier {
  public init() {}
  public var handledEntityTypes: [String] { [EntityName.focusSchedule] }
  public func applyUpsert(
    _ db: Database, envelope: SyncEnvelope, tieBreak: LwwTieBreak, applyTs: String
  ) throws -> EntityApplyOutcome {
    let repair = try ApplyDayScoped.applyFocusScheduleUpsert(
      db, entityId: envelope.entityId, payload: envelope.payload,
      version: envelope.version.description, tieBreak: tieBreak,
      payloadSchemaVersion: envelope.payloadSchemaVersion)
    if let repair, repair.removedCalendarReference {
      return .repairRequired(
        .propagateCalendarCleanup(
          targets: [
            CalendarCleanupRepairTarget(
              entityType: .focusSchedule, entityId: envelope.entityId,
              operation: repair.operation)
          ],
          additionalFloor: envelope.version))
    }
    if let repair {
      return .repairRequired(
        .propagateTaskRollover(
          targets: [
            .relatedEntity(
              entityType: .focusSchedule, entityId: envelope.entityId,
              operation: repair.operation, knownVersionFloor: envelope.version)
          ],
          additionalFloor: envelope.version))
    }
    return .applied
  }
  public func applyDelete(_ db: Database, envelope: SyncEnvelope, applyTs: String) throws
    -> EntityApplyOutcome
  {
    try ApplyDayScoped.applyFocusScheduleDelete(
      db, entityId: envelope.entityId, version: envelope.version.description)
    return .applied
  }
}

public struct DailyReviewApplier: EntityApplier {
  public init() {}
  public var handledEntityTypes: [String] { [EntityName.dailyReview] }
  public func applyUpsert(
    _ db: Database, envelope: SyncEnvelope, tieBreak: LwwTieBreak, applyTs: String
  ) throws -> EntityApplyOutcome {
    try ApplyDayScoped.applyDailyReviewUpsert(
      db, entityId: envelope.entityId, payload: envelope.payload,
      version: envelope.version.description, tieBreak: tieBreak)
    return .applied
  }
  public func applyDelete(_ db: Database, envelope: SyncEnvelope, applyTs: String) throws
    -> EntityApplyOutcome
  {
    try ApplyDayScoped.applyDailyReviewDelete(
      db, entityId: envelope.entityId, version: envelope.version.description)
    return .applied
  }
}

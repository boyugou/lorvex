import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Real ``RecurrenceSpawnHandler`` that spawns the next recurrence occurrence
/// when a recurring task is completed (or skip-cancelled) and rewinds its
/// recorded direct successor when a completed recurring parent is reopened.
///
/// All side effects (successor row create/revive, focus-plan rewire,
/// tag/checklist/reminder copy, recurrence rewind) stamp with the single
/// ``reminderVersion`` HLC the orchestrator forwards, so the entire recurrence
/// rollover ships as one HLC's worth of writes.
public struct LifecycleRecurrenceSpawnHandler: RecurrenceSpawnHandler {
  public init() {}

  public func spawnRecurrenceSuccessor(
    _ db: Database,
    taskId: TaskId,
    snapshot: LifecycleTaskSnapshot,
    activeReminderTimes: [String],
    now: String,
    reminderVersion: String
  ) throws -> SpawnedRecurrenceSuccessor? {
    guard
      let decision = try SpawnSuccessor.computeNextDueDate(
        db, snapshot: snapshot, now: now)
    else {
      return nil
    }

    guard let groupId = snapshot.recurrenceGroupId else {
      throw StoreError.invariant(
        "recurring task \(taskId.asString) has no recurrence_group_id")
    }
    let successorId = TaskRecurrenceSuccessorID.make(
      parentTaskId: taskId.asString, recurrenceGroupId: groupId)
    if let recordedId = snapshot.recurrenceSuccessorId, recordedId != successorId {
      throw StoreError.invariant(
        "task \(taskId.asString) records successor \(recordedId), expected deterministic id \(successorId)")
    }
    guard
      let instanceKey = Recurrence.generateInstanceKey(
        recurrenceGroupID: groupId,
        canonicalOccurrenceDate: decision.nextDueDate)
    else {
      throw StoreError.invariant(
        "could not derive recurrence instance key for task \(taskId.asString)")
    }
    let successorPlannedDate = SpawnSuccessor.computeSuccessorPlannedDate(
      snapshot: snapshot, nextDueDate: decision.nextDueDate)
    let successorAvailableFrom = SpawnSuccessor.computeSuccessorAvailableFrom(
      snapshot: snapshot, nextDueDate: decision.nextDueDate)

    let rowWrite = try SpawnSuccessor.createOrReviveSuccessorRow(
      db,
      parentId: taskId.asString,
      successorId: successorId,
      nextDueDate: decision.nextDueDate,
      spawnedRecurrence: decision.spawnedRecurrence,
      spawnedGroupId: groupId,
      instanceKey: instanceKey,
      successorPlannedDate: successorPlannedDate,
      successorAvailableFrom: successorAvailableFrom,
      version: reminderVersion,
      now: now)

    try SpawnSuccessor.replaceRecurrenceExceptions(
      db,
      parentId: taskId.asString,
      successorId: successorId)

    let rewire = try SpawnSuccessor.rewireFocusPlan(
      db,
      parentId: taskId.asString,
      successorId: successorId,
      todayYmd: decision.todayYmd)

    let copiedTagEdges = rowWrite.inserted
      ? try SpawnSuccessor.copyTaskTags(
        db, parentId: taskId.asString, successorId: successorId,
        version: reminderVersion, now: now)
      : []
    let copiedChecklistItemIds = rowWrite.inserted
      ? try SpawnSuccessor.copyChecklistItems(
        db, parentId: taskId.asString, successorId: successorId,
        version: reminderVersion, now: now)
      : []
    let copiedReminderIds: [String]
    if rowWrite.inserted {
      copiedReminderIds = try SpawnSuccessor.copyReminders(
        db, snapshot: snapshot, successorId: successorId,
        nextDueDate: decision.nextDueDate,
        parentActiveReminderTimes: activeReminderTimes,
        version: reminderVersion, now: now)
    } else if let priorLifecycleVersion = rowWrite.priorLifecycleVersion {
      copiedReminderIds = try SpawnSuccessor.reviveRewindCancelledReminders(
        db, successorId: successorId,
        cancellationVersion: priorLifecycleVersion,
        version: reminderVersion, now: now)
    } else {
      copiedReminderIds = []
    }

    try SpawnSuccessor.authorizeParent(
      db, parentId: taskId.asString, successorId: successorId,
      version: reminderVersion)

    return SpawnedRecurrenceSuccessor(
      successorId: successorId,
      copiedTagEdges: copiedTagEdges,
      copiedChecklistItemIds: copiedChecklistItemIds,
      copiedReminderIds: copiedReminderIds,
      rewiredFocusScheduleDates: rewire.rewiredFocusScheduleDates,
      rewiredCurrentFocusDates: rewire.rewiredCurrentFocusDates)
  }

  public func cancelRecurringSuccessors(
    _ db: Database,
    taskId: TaskId,
    snapshot: LifecycleTaskSnapshot,
    now: String,
    reminderVersion: String
  ) throws -> SuccessorCancelOutcome {
    guard snapshot.recurrenceRolloverState == .authorized,
      let successorId = snapshot.recurrenceSuccessorId
    else {
      return SuccessorCancelOutcome(ids: [], sideEffects: .empty)
    }

    if let groupId = snapshot.recurrenceGroupId {
      let expectedId = TaskRecurrenceSuccessorID.make(
        parentTaskId: taskId.asString, recurrenceGroupId: groupId)
      guard successorId == expectedId else {
        throw StoreError.invariant(
          "task \(taskId.asString) records successor \(successorId), expected deterministic id \(expectedId)")
      }
    }

    guard let row = try Row.fetchOne(
      db,
      sql:
        "SELECT status, recurrence_rollover_state, spawned_from, spawned_from_version "
        + "FROM tasks WHERE id = ?1",
      arguments: [successorId])
    else {
      return SuccessorCancelOutcome(ids: [], sideEffects: .empty)
    }
    let rawStatus: String = row[0]
    guard let status = TaskStatus.parse(rawStatus) else {
      throw LifecycleStatus.invalidPersistedTaskStatus(
        taskId: TaskId(trusted: successorId), raw: rawStatus)
    }
    let rawRollover: String = row[1]
    guard let successorRollover = TaskRecurrenceRolloverState(rawValue: rawRollover) else {
      throw StoreError.invariant(
        "task \(successorId) has invalid recurrence_rollover_state \"\(rawRollover)\"")
    }
    let spawnedFrom: String? = row[2]
    guard spawnedFrom == taskId.asString else {
      throw StoreError.invariant(
        "task \(successorId) is not a direct successor of \(taskId.asString)")
    }
    let spawnedFromVersion: String? = row[3]
    guard spawnedFromVersion == snapshot.lifecycleVersion else {
      throw StoreError.validation(
        "Cannot reopen task \(taskId.asString): successor \(successorId) belongs to a different lifecycle generation")
    }
    guard status.isActive else {
      throw StoreError.validation(
        "Cannot reopen task \(taskId.asString): recurrence successor \(successorId) has already advanced")
    }
    guard successorRollover == .none || successorRollover == .revoked else {
      throw StoreError.validation(
        "Cannot reopen task \(taskId.asString): recurrence successor \(successorId) has already advanced")
    }

    let activeDescendantExists = (try Int.fetchOne(
      db,
      sql:
        "WITH RECURSIVE descendants(id) AS ("
        + "SELECT id FROM tasks WHERE spawned_from = ?1 "
        + "UNION ALL "
        + "SELECT child.id FROM tasks child JOIN descendants parent "
        + "ON child.spawned_from = parent.id"
        + ") SELECT EXISTS(SELECT 1 FROM tasks t JOIN descendants d ON d.id = t.id "
        + "WHERE t.status IN (\(StatusName.activeStatusSqlList)))",
      arguments: [successorId])) ?? 0
    guard activeDescendantExists == 0 else {
      throw StoreError.validation(
        "Cannot reopen task \(taskId.asString): a later recurrence descendant is still active")
    }

    let result = try LifecycleStatus.cancelRecurrenceSuccessorForReopen(
      db, taskId: TaskId(trusted: successorId), oldStatus: status,
      now: now, version: reminderVersion)
    let focusRewire = try LifecycleSuccessorFocusRewind.rewire(
      db, successorId: successorId, parentId: taskId.asString)

    return SuccessorCancelOutcome(
      ids: [successorId],
      sideEffects: SuccessorCancelSideEffects(
        cancelledReminderIds: result.cancelledReminderIds,
        deletedDependencyEdges: result.deletedDependencyEdges,
        affectedDependentIds: result.affectedDependentIds,
        rewiredFocusScheduleDates: focusRewire.focusScheduleDates,
        rewiredCurrentFocusDates: focusRewire.currentFocusDates))
  }
}

// MARK: - Internal helpers (file-private namespace)

/// Spawn-successor implementation pieces, split by concern (next-due,
/// insert, copy, rewire, timezone) — landed in one file because the
/// surface is small and each helper is consumed only by the handler above.
enum SpawnSuccessor {

  struct SuccessorRowWrite {
    let inserted: Bool
    let priorLifecycleVersion: String?
  }

  struct NextDueDecision {
    let nextDueDate: String
    /// Recurrence rule the successor row should carry. Possibly
    /// `decrementRecurrenceCount`-modified if the original carried a finite
    /// COUNT.
    let spawnedRecurrence: String
    /// Today in the user's configured timezone — reused by the focus-plan
    /// rewire so the preference isn't re-read.
    let todayYmd: String
  }

  /// Walk the EXDATE list past excluded dates, decrement COUNT, and surface the
  /// next successor anchor. Duplicate suppression belongs to the deterministic
  /// successor UUID, so this computation never hides an existing row that a
  /// re-completion must revive.
  static func computeNextDueDate(
    _ db: Database, snapshot: LifecycleTaskSnapshot, now: String
  ) throws -> NextDueDecision? {
    guard let rule = snapshot.recurrence else { return nil }
    guard let cadenceAnchor = snapshot.canonicalOccurrenceDate else { return nil }

    let todayYmd = try Self.todayYmdInUserTimezone(db, now: now)

    let exclusionSet: Set<String>
    do {
      exclusionSet = try RecurrenceExceptionsRepo.parseExceptionDatesAsSet(
        snapshot.recurrenceExceptions)
    } catch {
      throw StoreError.serialization(
        "malformed recurrence_exceptions JSON: \(error)")
    }

    let maxExdateSkipIterations = 1000
    // Completion-anchored rules ignore the calendar cadence: the next due date
    // is INTERVAL units after the completion day (`todayYmd`), so a task closed
    // late slips forward instead of piling up missed occurrences. BYMONTHDAY
    // injection is skipped — positional keys are rejected for this anchor.
    let isCompletionAnchored =
      try CalendarRecurrence.recurrenceAnchorIsCompletion(recurrenceJson: rule)

    let enrichedRule: String
    let resolvedNextDueDate: String
    if isCompletionAnchored {
      enrichedRule = rule
      var candidateBase = todayYmd
      var found: String? = nil
      for _ in 0..<maxExdateSkipIterations {
        guard
          let candidate = try CalendarRecurrence.nextOccurrenceAfterCompletion(
            recurrenceJson: rule, completionYmd: candidateBase)
        else {
          break
        }
        if !exclusionSet.contains(candidate) {
          found = candidate
          break
        }
        candidateBase = candidate
      }
      guard let resolved = found else { return nil }
      resolvedNextDueDate = resolved
    } else {
      enrichedRule =
        (try CalendarRecurrence.injectBymonthday(
          recurrenceJson: rule, dueDateYmd: cadenceAnchor)) ?? rule
      var candidateAnchor = cadenceAnchor
      var nextDueDate: String? = nil
      for _ in 0..<maxExdateSkipIterations {
        guard
          let candidate = try CalendarRecurrence.nextOccurrenceStrictlyAfter(
            recurrenceJson: enrichedRule,
            baseDateYmd: candidateAnchor,
            todayYmd: todayYmd)
        else {
          break
        }
        if !exclusionSet.contains(candidate) {
          nextDueDate = candidate
          break
        }
        candidateAnchor = candidate
      }
      guard let resolved = nextDueDate else { return nil }
      resolvedNextDueDate = resolved
    }

    guard
      let spawnedRecurrence = try CalendarRecurrence.decrementRecurrenceCount(
        recurrenceJson: enrichedRule)
    else {
      return nil
    }

    return NextDueDecision(
      nextDueDate: resolvedNextDueDate,
      spawnedRecurrence: spawnedRecurrence,
      todayYmd: todayYmd)
  }

  /// Resolves today's date in the configured timezone: missing preference
  /// ⇒ system local, malformed preference ⇒ typed
  /// ``StoreError/validation``.
  ///
  /// Distinct from ``WorkflowTimezone/todayYmdForConn(_:now:)``: that helper
  /// substitutes the system identifier when the preference is missing
  /// (different DST-day-boundary semantics on hosts whose system zone differs
  /// from UTC). This helper passes `nil` straight through to the domain
  /// renderer when the preference is absent.
  static func todayYmdInUserTimezone(
    _ db: Database, now: String
  ) throws -> String {
    guard let nowDate = ReminderAnchor.parseRfc3339ToDate(now) else {
      throw StoreError.validation(
        "completion timestamp must be valid RFC3339: \(now)")
    }
    let rawTz: String? = try String.fetchOne(
      db,
      sql: "SELECT value FROM preferences WHERE key = 'timezone'")
    let timezoneName: String?
    if let raw = rawTz {
      switch Timezone.parseRequiredTimezonePreference(raw, key: "timezone") {
      case .success(let name):
        timezoneName = name
      case .failure(let error):
        throw StoreError.validation(error.description)
      }
    } else {
      timezoneName = nil
    }
    return Timezone.todayYmdForTimezoneName(
      now: nowDate,
      timezoneName: timezoneName,
      systemFallback: TimeZone.current)
  }

  // MARK: - planned-date offset

  /// Preserve the offset from the parent's canonical anchor to its planned
  /// date when computing the successor's planned date. Cadence anchor — not
  /// `due_date` — is the reference because it never moves under deferral.
  static func computeSuccessorPlannedDate(
    snapshot: LifecycleTaskSnapshot, nextDueDate: String
  ) -> String? {
    guard let parentPlanned = snapshot.plannedDate,
      let anchor = snapshot.canonicalOccurrenceDate,
      let parentPlannedYmd = IsoDate.parse(parentPlanned),
      let anchorYmd = IsoDate.parse(anchor),
      let nextDueYmd = IsoDate.parse(nextDueDate)
    else {
      return nil
    }
    let offsetDays = IsoDate.dayNumber(parentPlannedYmd) - IsoDate.dayNumber(anchorYmd)
    return IsoDate.addingDays(nextDueYmd, offsetDays).canonicalString
  }

  // MARK: - available-from offset

  /// Preserve the offset from the parent's canonical anchor to its
  /// `available_from` (defer-until) date when computing the successor's
  /// `available_from`. Cadence anchor — not `due_date` — is the reference
  /// because it never moves under deferral, so each generation's hide window
  /// keeps the same day-delta from its occurrence date. Returns `nil` (never
  /// hidden) when the parent has no `available_from` or no canonical anchor.
  static func computeSuccessorAvailableFrom(
    snapshot: LifecycleTaskSnapshot, nextDueDate: String
  ) -> String? {
    guard let parentAvailableFrom = snapshot.availableFrom,
      let anchor = snapshot.canonicalOccurrenceDate,
      let parentAvailableFromYmd = IsoDate.parse(parentAvailableFrom),
      let anchorYmd = IsoDate.parse(anchor),
      let nextDueYmd = IsoDate.parse(nextDueDate)
    else {
      return nil
    }
    let offsetDays = IsoDate.dayNumber(parentAvailableFromYmd) - IsoDate.dayNumber(anchorYmd)
    return IsoDate.addingDays(nextDueYmd, offsetDays).canonicalString
  }

  // MARK: - create / revive

  /// Create a direct successor or revive its previously-cancelled stable row.
  /// Returns `true` only for a fresh insert; callers use that bit to avoid
  /// duplicating child content on re-completion.
  static func createOrReviveSuccessorRow(
    _ db: Database,
    parentId: String,
    successorId: String,
    nextDueDate: String,
    spawnedRecurrence: String,
    spawnedGroupId: String,
    instanceKey: String,
    successorPlannedDate: String?,
    successorAvailableFrom: String?,
    version: String,
    now: String
  ) throws -> SuccessorRowWrite {
    if let existing = try Row.fetchOne(
      db,
      sql:
        "SELECT status, recurrence_rollover_state, spawned_from, version, lifecycle_version "
        + "FROM tasks WHERE id = ?1",
      arguments: [successorId])
    {
      let rawStatus: String = existing[0]
      guard let status = TaskStatus.parse(rawStatus) else {
        throw LifecycleStatus.invalidPersistedTaskStatus(
          taskId: TaskId(trusted: successorId), raw: rawStatus)
      }
      let rawRollover: String = existing[1]
      guard let rollover = TaskRecurrenceRolloverState(rawValue: rawRollover) else {
        throw StoreError.invariant(
          "task \(successorId) has invalid recurrence_rollover_state \"\(rawRollover)\"")
      }
      let spawnedFrom: String? = existing[2]
      // A contradictory parent decision may have re-rooted this reserved
      // deterministic id to preserve a concurrent edit. A later explicit
      // re-authorization is allowed to adopt that root again; an id owned by a
      // different parent remains a hard invariant failure.
      guard spawnedFrom == parentId || spawnedFrom == nil else {
        throw StoreError.invariant(
          "deterministic successor id \(successorId) belongs to a different parent")
      }
      guard status.isActive || (status == .cancelled && rollover == .ended) else {
        throw StoreError.validation(
          "Cannot re-complete task \(parentId): successor \(successorId) has already advanced")
      }
      let existingVersion: String = existing[3]
      guard version > existingVersion else {
        throw StoreError.staleVersion(entity: EntityName.task, id: successorId)
      }

      try db.execute(
        sql:
          "UPDATE tasks SET "
          + "status = 'open', completed_at = NULL, "
          + "due_date = ?1, planned_date = ?2, available_from = ?3, "
          + "canonical_occurrence_date = ?1, recurrence = ?4, "
          + "recurrence_group_id = ?5, recurrence_instance_key = ?6, "
          + "spawned_from = ?7, spawned_from_version = ?8, "
          + "last_deferred_at = NULL, last_defer_reason = NULL, defer_count = 0, "
          + "recurrence_rollover_state = 'none', recurrence_successor_id = NULL, "
          + "schedule_version = ?8, lifecycle_version = ?8, "
          + "version = ?8, updated_at = ?9 "
          + "WHERE id = ?10 AND ?8 > version",
        arguments: [
          nextDueDate, successorPlannedDate, successorAvailableFrom,
          spawnedRecurrence, spawnedGroupId, instanceKey, parentId,
          version, now, successorId,
        ])
      guard db.changesCount == 1 else {
        throw StoreError.staleVersion(entity: EntityName.task, id: successorId)
      }
      return SuccessorRowWrite(
        inserted: false, priorLifecycleVersion: existing[4])
    }

    try db.execute(
      sql:
        "INSERT INTO tasks ("
        + "id, title, body, ai_notes, "
        + "status, list_id, priority, "
        + "due_date, planned_date, available_from, canonical_occurrence_date, "
        + "estimated_minutes, recurrence, recurrence_group_id, "
        + "recurrence_instance_key, spawned_from, spawned_from_version, "
        + "content_version, schedule_version, lifecycle_version, archive_version, "
        + "recurrence_rollover_state, version, created_at, updated_at, defer_count"
        + ") SELECT "
        + "?1, title, body, ai_notes, "
        + "'open', list_id, priority, "
        + "?2, ?10, ?11, ?2, "
        + "estimated_minutes, ?3, ?9, "
        + "?4, ?5, ?6, "
        + "?6, ?6, ?6, ?6, "
        + "'none', ?6, ?7, ?7, 0 "
        + "FROM tasks WHERE id = ?8",
      arguments: [
        successorId,
        nextDueDate,
        spawnedRecurrence,
        instanceKey,
        parentId,
        version,
        now,
        parentId,
        spawnedGroupId,
        successorPlannedDate,
        successorAvailableFrom,
      ])
    guard db.changesCount == 1 else {
      throw StoreError.notFound(entity: EntityName.task, id: parentId)
    }
    return SuccessorRowWrite(inserted: true, priorLifecycleVersion: nil)
  }

  /// Finalize the parent's terminal rollover decision after the successor row
  /// and its generated children are durable in the same transaction.
  static func authorizeParent(
    _ db: Database, parentId: String, successorId: String, version: String
  ) throws {
    try db.execute(
      sql:
        "UPDATE tasks SET recurrence_rollover_state = 'authorized', "
        + "recurrence_successor_id = ?1, lifecycle_version = ?2, "
        + "schedule_version = ?2 "
        + "WHERE id = ?3 AND status IN ('completed', 'cancelled') "
        + "AND version = ?2 AND lifecycle_version = ?2",
      arguments: [successorId, version, parentId])
    guard db.changesCount == 1 else {
      throw StoreError.invariant(
        "could not authorize recurrence successor \(successorId) on parent \(parentId)")
    }
  }

  // MARK: - rewire focus plan

  struct FocusRewireResult {
    let rewiredFocusScheduleDates: [String]
    let rewiredCurrentFocusDates: [String]
  }

  static func rewireFocusPlan(
    _ db: Database,
    parentId: String,
    successorId: String,
    todayYmd: String
  ) throws -> FocusRewireResult {
    let rewiredFocusScheduleDates = try String.fetchAll(
      db,
      sql:
        "SELECT DISTINCT date FROM focus_schedule_blocks "
        + "WHERE task_id = ?1 AND date >= ?2 "
        + "ORDER BY date ASC",
      arguments: [parentId, todayYmd])
    let rewiredCurrentFocusDates = try String.fetchAll(
      db,
      sql:
        "SELECT DISTINCT date FROM current_focus_items "
        + "WHERE task_id = ?1 AND date >= ?2 "
        + "ORDER BY date ASC",
      arguments: [parentId, todayYmd])
    try db.execute(
      sql:
        "UPDATE focus_schedule_blocks SET task_id = ?1 "
        + "WHERE task_id = ?2 AND date >= ?3",
      arguments: [successorId, parentId, todayYmd])
    try db.execute(
      sql:
        "UPDATE current_focus_items SET task_id = ?1 "
        + "WHERE task_id = ?2 AND date >= ?3",
      arguments: [successorId, parentId, todayYmd])
    return FocusRewireResult(
      rewiredFocusScheduleDates: rewiredFocusScheduleDates,
      rewiredCurrentFocusDates: rewiredCurrentFocusDates)
  }

  // MARK: - copy tags / checklist / reminders

  static func copyTaskTags(
    _ db: Database,
    parentId: String,
    successorId: String,
    version: String,
    now: String
  ) throws -> [CopiedTagEdge] {
    try db.execute(
      sql:
        "INSERT OR IGNORE INTO task_tags (task_id, tag_id, version, created_at) "
        + "SELECT ?1, tag_id, ?2, ?3 FROM task_tags WHERE task_id = ?4",
      arguments: [successorId, version, now, parentId])
    let tagIds = try String.fetchAll(
      db,
      sql: "SELECT tag_id FROM task_tags WHERE task_id = ?1",
      arguments: [successorId])
    return tagIds.map { tagId in
      CopiedTagEdge(
        taskId: successorId, tagId: tagId, version: version, createdAt: now)
    }
  }

  /// Carry the parent series' EXDATE registry onto the spawned successor so a
  /// future-dated skip survives across generations. Without this, completing an
  /// occurrence drops every recurrence exception — the next-date walk only
  /// protects the immediate slot, so a later generation would land on a skipped
  /// date. EXDATE rows are PK-only (no version/HLC); they ride to sync inside
  /// the successor's task payload, whose projection rebuilds them from this
  /// table via json_group_array.
  static func replaceRecurrenceExceptions(
    _ db: Database,
    parentId: String,
    successorId: String
  ) throws {
    try db.execute(
      sql: "DELETE FROM task_recurrence_exceptions WHERE task_id = ?1",
      arguments: [successorId])
    try db.execute(
      sql:
        "INSERT INTO task_recurrence_exceptions (task_id, exception_date) "
        + "SELECT ?1, exception_date FROM task_recurrence_exceptions WHERE task_id = ?2",
      arguments: [successorId, parentId])
  }

  static func copyChecklistItems(
    _ db: Database,
    parentId: String,
    successorId: String,
    version: String,
    now: String
  ) throws -> [String] {
    let parentItems = try Row.fetchAll(
      db,
      sql:
        "SELECT position, text FROM task_checklist_items "
        + "WHERE task_id = ?1 ORDER BY position ASC",
      arguments: [parentId])
    var copied: [String] = []
    copied.reserveCapacity(parentItems.count)
    for row in parentItems {
      let position: Int64 = row[0]
      let text: String = row[1]
      let itemId = EntityID.newEntityIDString()
      try db.execute(
        sql:
          "INSERT INTO task_checklist_items "
          + "(id, task_id, position, text, completed_at, version, created_at, updated_at) "
          + "VALUES (?1, ?2, ?3, ?4, NULL, ?5, ?6, ?6)",
        arguments: [itemId, successorId, position, text, version, now])
      copied.append(itemId)
    }
    return copied
  }

  /// Copy parent-active reminders to the successor, advancing each reminder by
  /// the parent→successor calendar-day delta in the user's anchored timezone so
  /// its local wall-clock time survives a DST transition between the two due
  /// dates. A raw `days * 86400` UTC shift would drift the reminder ±1h when a
  /// DST boundary falls between the dates; a calendar-day add preserves both the
  /// wall clock and the day offset, and reduces to `days * 86400` whenever no
  /// boundary is crossed. Only reminders whose recomputed time is strictly in
  /// the future (`> now`) are copied. A malformed stored or computed timestamp
  /// surfaces as ``StoreError/validation`` rather than silently dropping the
  /// reminder.
  static func copyReminders(
    _ db: Database,
    snapshot: LifecycleTaskSnapshot,
    successorId: String,
    nextDueDate: String,
    parentActiveReminderTimes: [String],
    version: String,
    now: String
  ) throws -> [String] {
    var copied: [String] = []
    guard let parentDue = snapshot.dueDate else { return copied }
    guard let parentDueYmd = IsoDate.parse(parentDue) else {
      throw StoreError.validation(
        "spawn_successor: corrupt parent due_date \(parentDue)")
    }
    guard let successorDueYmd = IsoDate.parse(nextDueDate) else {
      throw StoreError.validation(
        "spawn_successor: corrupt next_due_date \(nextDueDate)")
    }
    guard let nowDt = ReminderAnchor.parseRfc3339ToDate(now) else {
      throw StoreError.validation(
        "spawn_successor: corrupt `now` timestamp \"\(now)\"")
    }

    let deltaDays = IsoDate.dayNumber(successorDueYmd) - IsoDate.dayNumber(parentDueYmd)
    let anchoredZone =
      TimeZone(identifier: try WorkflowTimezone.anchoredTimezoneName(db))
      ?? TimeZone(secondsFromGMT: 0)!
    var cal = Calendar(identifier: .gregorian)
    cal.locale = Locale(identifier: "en_US_POSIX")
    cal.timeZone = anchoredZone

    for reminderAtStr in parentActiveReminderTimes {
      guard let reminderDt = ReminderAnchor.parseRfc3339ToDate(reminderAtStr) else {
        throw StoreError.validation(
          "spawn_successor: corrupt parent reminder_at \"\(reminderAtStr)\"")
      }
      guard
        let successorReminderDt = cal.date(
          byAdding: .day, value: deltaDays, to: reminderDt)
      else {
        throw StoreError.validation(
          "spawn_successor: could not shift reminder_at \"\(reminderAtStr)\" "
            + "by \(deltaDays) days")
      }
      if successorReminderDt <= nowDt { continue }

      let reminderId = EntityID.newEntityIDString()
      let successorReminderAt = SyncTimestampFormat.formatSyncTimestamp(
        successorReminderDt)
      let (originalLocalTime, originalTz) =
        try ReminderAnchor.resolveTaskReminderLocalAnchorForUtc(
          db, reminderUtc: successorReminderDt)
      try db.execute(
        sql:
          "INSERT INTO task_reminders ("
          + "id, task_id, reminder_at, original_local_time, original_tz, "
          + "dismissed_at, cancelled_at, version, created_at"
          + ") VALUES (?1, ?2, ?3, ?4, ?5, NULL, NULL, ?6, ?7)",
        arguments: [
          reminderId,
          successorId,
          successorReminderAt,
          originalLocalTime,
          originalTz,
          version,
          now,
        ])
      copied.append(reminderId)
    }
    return copied
  }

  /// Re-enable only reminders cancelled by the exact parent-reopen lifecycle
  /// generation. User-cancelled reminders carry a different HLC and remain
  /// cancelled; past reminders are never resurrected.
  static func reviveRewindCancelledReminders(
    _ db: Database,
    successorId: String,
    cancellationVersion: String,
    version: String,
    now: String
  ) throws -> [String] {
    let ids = try String.fetchAll(
      db,
      sql:
        "SELECT id FROM task_reminders WHERE task_id = ?1 "
        + "AND dismissed_at IS NULL AND cancelled_at IS NOT NULL "
        + "AND version = ?2 AND reminder_at > ?3 AND ?4 > version "
        + "ORDER BY id ASC",
      arguments: [successorId, cancellationVersion, now, version])
    guard !ids.isEmpty else { return [] }

    let placeholders = Sql.sqlCsvPlaceholders(ids.count)
    var arguments: [DatabaseValueConvertible] = [version]
    arguments.append(contentsOf: ids)
    try db.execute(
      sql:
        "UPDATE task_reminders SET cancelled_at = NULL, version = ? "
        + "WHERE id IN (\(placeholders)) AND ? > version",
      arguments: StatementArguments(arguments + [version]))
    return try String.fetchAll(
      db,
      sql:
        "SELECT id FROM task_reminders WHERE id IN (\(placeholders)) "
        + "AND version = ? ORDER BY id ASC",
      arguments: StatementArguments(ids + [version]))
  }
}

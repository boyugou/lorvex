import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Per-entity apply handler for the `habit` aggregate root.
///
/// The upsert bridges the typed cadence fields (`frequency_type`, `weekdays`,
/// `per_period_target`, `day_of_month`) into the typed ``HabitCadence``, runs
/// the domain create-draft validator, and re-renders the validated cadence back
/// to its typed columns for the SQL bind (never passing the raw payload values
/// straight through). When the upsert lands as the live survivor it rebuilds
/// the `habit_weekdays` child from the payload's weekday array (delete-then-
/// insert keyed by `habit_id`).
/// On the insert-collision merge path the staged incoming's weekdays are rebuilt
/// during staging (before the merge) so the merge's max-HLC content carry can copy
/// the surviving row's weekday set; the merge then owns the winner's final set. The
/// delete is LWW-gated and cascades tombstones onto `habit_completions`
/// (composite edge) and `habit_reminder_policies` (single-PK child) ahead of
/// SQLite's `ON DELETE CASCADE`, each stamped at `max(parentVersion,
/// rowVersion)`; `habit_weekdays` is device-local and cascades unstamped.
public struct HabitApplier: EntityApplier {
  public init() {}

  public var handledEntityTypes: [String] { [EntityKind.habit.asString] }

  public func applyUpsert(
    _ db: Database, envelope: SyncEnvelope, tieBreak: LwwTieBreak, applyTs: String
  ) throws -> EntityApplyOutcome {
    try ApplyHabit.applyHabitUpsert(
      db, entityId: envelope.entityId, payload: envelope.payload,
      version: envelope.version.description, tieBreak: tieBreak, applyTs: applyTs,
      payloadSchemaVersion: envelope.payloadSchemaVersion)
    return .applied
  }

  public func applyDelete(
    _ db: Database, envelope: SyncEnvelope, applyTs: String
  ) throws -> EntityApplyOutcome {
    switch try ApplyHabit.applyHabitDelete(
      db, entityId: envelope.entityId, version: envelope.version.description, applyTs: applyTs)
    {
    case .applied:
      return .applied
    case let .rejected(localVersion):
      return .lwwRejected(localVersion: localVersion)
    }
  }
}

enum ApplyHabit {
  static func applyHabitUpsert(
    _ db: Database, entityId: String, payload: String, version: String, tieBreak: LwwTieBreak,
    applyTs: String, payloadSchemaVersion: UInt32 = LorvexVersion.payloadSchemaVersion
  ) throws {
    let val = try ApplyJSON.parseObject(payload)

    let name = try ApplyJSON.requiredStr(val, "name", entity: "habit")
    let icon = try ApplyJSON.optionalStr(val, "icon", entity: "habit")
    let color = try ApplyJSON.optionalStr(val, "color", entity: "habit")
    let cue = try ApplyJSON.optionalStr(val, "cue", entity: "habit")
    let frequencyType = try ApplyJSON.requiredStr(val, "frequency_type", entity: "habit")
    let targetCount = try ApplyJSON.requiredInt64(val, "target_count", entity: "habit")

    // Strict-enum gate on the closed `frequency_type` vocabulary BEFORE cadence
    // parsing, so an unknown value a newer-schema peer authored is retained for
    // replay (forward-compat) rather than dropped; `fromFields` below still
    // validates the typed detail for a known type.
    guard HabitFrequencyType.parse(frequencyType) != nil else {
      throw ApplyError.forwardCompatOrInvalid(
        payloadSchemaVersion: payloadSchemaVersion,
        "habit \(entityId) frequency_type '\(frequencyType)' is not one of "
          + "daily|weekly|monthly|times_per_week")
    }

    // Typed cadence fields. A peer that predates a column omits it; the schema
    // DEFAULTs (perPeriodTarget 1, dayOfMonth NULL) apply. `weekdays`
    // is an array of Monday-first ints (0=Mon … 6=Sun).
    let weekdays = try parseWeekdays(val, entity: "habit", entityId: entityId)
    let perPeriodTarget = try ApplyJSON.optionalInt64(val, "per_period_target", entity: "habit") ?? 1
    let dayOfMonth = try optionalDayOfMonth(val, entityId: entityId)

    let frequency: HabitCadence
    do {
      frequency = try HabitCadence.fromFields(
        HabitFrequencyFields(
          frequencyType: frequencyType, weekdays: weekdays, perPeriodTarget: perPeriodTarget,
          dayOfMonth: dayOfMonth))
    } catch {
      throw ApplyError.invalidPayload("habit \(entityId) failed cadence parse: \(error)")
    }

    let validated: ValidatedHabitCreate
    do {
      validated = try validateHabitCreateDraft(
        HabitCreateDraft(
          name: name, icon: icon, color: color, cue: cue,
          frequency: frequency, targetCount: targetCount))
    } catch {
      throw ApplyError.invalidPayload("habit \(entityId) failed validation: \(error)")
    }

    let cadenceFields = validated.frequency.toFields()
    // milestone_target is a standalone habit goal, not a cadence field, so it is
    // parsed and bound directly rather than routed through the cadence validator.
    let milestoneTarget = try optionalMilestoneTarget(val, entityId: entityId)
    let archived = try ApplyJSON.optionalBoolAsInt64(val, "archived", entity: "habit") ?? 0
    let createdAt = try ApplyJSON.requiredStr(val, "created_at", entity: "habit")
    let updatedAt = try ApplyJSON.requiredStr(val, "updated_at", entity: "habit")
    // Synced manual display order. A peer that predates the column omits it; in
    // that case preserve this device's current position instead of resetting it
    // to 0 — a bare `?? 0` would let a position-less envelope clobber an order
    // already set here. A genuinely new row with no incoming position starts at 0.
    let position: Int64
    if let incomingPosition = try ApplyJSON.optionalInt64(val, "position", entity: "habit") {
      position = incomingPosition
    } else {
      position = try Int64.fetchOne(
        db, sql: "SELECT position FROM habits WHERE id = ?", arguments: [entityId]) ?? 0
    }

    // The base-row column set is the descriptor's plain columns (owned keys minus
    // the synthetic `weekdays`, which materializes into the `habit_weekdays`
    // child below). The bound values — cadence normalization, lookup_key
    // re-derivation, position preserve-on-absent — stay hand-written here.
    let sql = LwwUpsertSpec(
      table: "habits",
      columns: SyncEntityDescriptor.require(.habit).plainColumns,
      conflict: ["id"], tieBreak: tieBreak, createdAtFloor: true
    ).buildSQL()

    func runUpsert(_ db: Database, archived archivedValue: Int64) throws {
      try db.execute(
        sql: sql,
        arguments: [
          "id": entityId, "name": validated.name, "icon": validated.icon,
          "color": validated.color, "cue": validated.cue,
          "frequency_type": cadenceFields.frequencyType,
          "per_period_target": cadenceFields.perPeriodTarget,
          "day_of_month": cadenceFields.dayOfMonth.map { Int64($0) },
          "target_count": validated.targetCount,
          "milestone_target": milestoneTarget.map { Int64($0) }, "archived": archivedValue,
          "lookup_key": validated.lookupKey, "created_at": createdAt, "updated_at": updatedAt,
          "position": position, "version": version,
        ])
    }

    let outcome: CollisionMergeOutcome
    do {
      try runUpsert(db, archived: archived)
      outcome = CollisionMergeOutcome(
        incomingSurvived: db.changesCount > 0, mergeRan: false)
    } catch let dbError as DatabaseError
      where dbError.isUniqueConstraintViolation && archived == 0
    {
      // Sync-wedge fix (W-1): two devices created the SAME habit offline (same
      // normalized `lookup_key`) with distinct ids, so the second trips the partial
      // `UNIQUE(lookup_key) WHERE archived = 0`. Converge it (min id wins, loser
      // tombstoned with redirect) rather than letting the constraint escape as the
      // batch-fatal `ApplyError.db` that wedges the inbound page. Stage the incoming
      // as archived=1 (outside the partial index) so it lands beside the existing
      // active claimant; the merge collapses the duplicates and restores the real
      // archived flag to the winner. Only an active (archived=0) incoming can hit
      // this index, so the restored value is always 0.
      outcome = try ApplyHabitMerge.insertHabitByMergingCollision(
        db, entityId: entityId, lookupKey: validated.lookupKey, archived: archived,
        version: version, applyTs: applyTs, originalError: dbError
      ) { db in
        try runUpsert(db, archived: 1)
        // Materialize the staged incoming's `habit_weekdays` from its payload
        // BEFORE the merge collapses the duplicates, so the merge's max-HLC content
        // carry can copy this row's weekday set when it is the content winner P*.
        try rebuildHabitWeekdays(db, habitId: entityId, weekdays: cadenceFields.weekdays ?? [])
      }
    } catch { throw ApplyError.lift(error) }

    // Version-rejected payloads still lower the creation floor (min-register;
    // see ApplyLww.foldCreatedAtFloor). After a collision merge this id may be
    // a deleted loser — the guarded UPDATE then matches no row, and the merge
    // itself already folded every participant's floor into the winner.
    try ApplyLww.foldCreatedAtFloor(
      db, table: "habits", pkValue: entityId, incomingCreatedAt: createdAt)

    // Rebuild the `habit_weekdays` materialization from the payload's weekday
    // array for the plain survivor path — a version-rejected upsert
    // (`changesCount == 0`) must not overwrite the current (newer) weekdays with a
    // stale payload. Runs BEFORE the defensive dedup tail so that tail's content
    // carry sees the materialized set. The insert-collision path (`mergeRan`)
    // already materialized the staged incoming's weekdays before its merge, and
    // that merge's content carry then set the winner's final weekday set, so
    // re-running here would clobber a carried set — hence `!mergeRan`. The set is
    // the validated cadence's weekdays (empty for every non-weekly cadence
    // and for weekly-every-day).
    if outcome.incomingSurvived && !outcome.mergeRan {
      try rebuildHabitWeekdays(db, habitId: entityId, weekdays: cadenceFields.weekdays ?? [])
    }

    // Post-upsert dedup tail: only when the upsert landed as an ACTIVE row and the
    // collision path did not already merge. Defensive convergence pass mirroring
    // the other immutable-key aggregate merges. Archived habits do not participate in dedup.
    if outcome.incomingSurvived && !outcome.mergeRan && archived == 0 {
      try ApplyHabitMerge.mergeDuplicateHabits(
        db, justUpsertedId: entityId, lookupKey: validated.lookupKey, version: version,
        applyTs: applyTs)
    }
  }

  /// Delete-then-insert the `habit_weekdays` rows for one habit from a weekday
  /// set. Device-local materialization: the rows carry no version and are never
  /// synced independently. An empty set leaves the habit with no weekday rows
  /// ("every day" for a weekly cadence).
  static func rebuildHabitWeekdays(
    _ db: Database, habitId: String, weekdays: [WeekDay]
  ) throws {
    do {
      try db.execute(sql: "DELETE FROM habit_weekdays WHERE habit_id = ?", arguments: [habitId])
      for day in weekdays {
        try db.execute(
          sql: "INSERT OR IGNORE INTO habit_weekdays (habit_id, weekday) VALUES (?, ?)",
          arguments: [habitId, day.rawValue])
      }
    } catch { throw ApplyError.lift(error) }
  }

  /// LWW-gated delete that cascades child / edge tombstones BEFORE the parent
  /// DELETE. Returns ``ApplyAggregate/CascadingDeleteDecision`` so the in-handler
  /// LWW gate's reject arm surfaces as a typed outcome rather than a silent no-op.
  static func applyHabitDelete(
    _ db: Database, entityId: String, version: String, applyTs: String
  ) throws -> ApplyAggregate.CascadingDeleteDecision {
    try ApplyAggregate.gateThenCascade(
      db,
      readVersionSQL: "SELECT version FROM habits WHERE id = ?",
      deleteSQL: "DELETE FROM habits WHERE id = :id",
      entityId: entityId, incomingVersion: version, tieBreak: .allowEqual
    ) { db in
      try ApplyAggregate.tombstoneCompositeEdges(
        db,
        selectSQL: "SELECT completed_date, version FROM habit_completions WHERE habit_id = ?",
        parentId: entityId, entityType: EdgeName.habitCompletion,
        composeId: { other in "\(entityId):\(other)" },
        version: version, deletedAt: applyTs)
      try ApplyAggregate.tombstoneChildRows(
        db,
        selectSQL: "SELECT id, version FROM habit_reminder_policies WHERE habit_id = ?",
        parentId: entityId, entityType: EntityName.habitReminderPolicy,
        version: version, deletedAt: applyTs)
    }
  }

  /// Parse the payload `weekdays` array (Monday-first ints 0=Mon … 6=Sun) into
  /// typed ``WeekDay`` values. Absent / null → empty. An out-of-range or
  /// non-integer entry is a shape error for the whole envelope.
  private static func parseWeekdays(
    _ obj: [String: JSONValue], entity: String, entityId: String
  ) throws -> [WeekDay] {
    guard let raw = try ApplyJSON.optionalObjectArray(obj, "weekdays", entity: entity) else {
      return []
    }
    var out: [WeekDay] = []
    for entry in raw {
      guard case let .int(i) = entry, let wd = WeekDay(rawValue: Int(i)) else {
        throw ApplyError.invalidPayload(
          "habit \(entityId) weekdays entries must be integers 0…6 (Mon-first)")
      }
      out.append(wd)
    }
    return out
  }

  /// Parse the optional `day_of_month` payload field. Absent / null → `nil`; a
  /// present value outside `1…31` is a shape error.
  private static func optionalDayOfMonth(
    _ obj: [String: JSONValue], entityId: String
  ) throws -> Int? {
    guard let raw = try ApplyJSON.optionalInt64(obj, "day_of_month", entity: "habit") else {
      return nil
    }
    guard (1...31).contains(raw) else {
      throw ApplyError.invalidPayload("habit \(entityId) day_of_month must be between 1 and 31")
    }
    return Int(raw)
  }

  /// Parse the optional `milestone_target` payload field. Absent / null → `nil`;
  /// a present value at or below zero violates the `milestone_target > 0` schema
  /// CHECK and is a shape error.
  private static func optionalMilestoneTarget(
    _ obj: [String: JSONValue], entityId: String
  ) throws -> Int? {
    guard let raw = try ApplyJSON.optionalInt64(obj, "milestone_target", entity: "habit") else {
      return nil
    }
    guard raw > 0 else {
      throw ApplyError.invalidPayload("habit \(entityId) milestone_target must be positive")
    }
    return Int(raw)
  }

}

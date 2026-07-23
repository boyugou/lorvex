import Foundation
import GRDB
import LorvexDomain

/// Per-entity sync payload builders for "simple" (non-aggregate-with-embedded-
/// children) entity types. The single source of truth for the wire shape of
/// each entity's sync envelope payload across the seed scan and the runtime
/// per-id enqueue helpers.
///
/// Each builder returns a ``JSONValue`` tree whose field set, names, and value
/// encodings define the stable wire shape once routed through
/// ``canonicalizeJSON(_:)`` (which sorts keys, so insertion order does not
/// affect the emitted bytes).
///
/// Aggregate roots whose envelope embeds materialized child rows
/// (`current_focus`, `focus_schedule`, `daily_review`, `calendar_event`) are
/// NOT covered here — they flow through the aggregate payload builder.
public enum PayloadLoaders {

  // MARK: - Shared row helpers

  static func str(_ row: Row, _ index: Int) -> JSONValue { .string(row[index]) }
  static func optStr(_ row: Row, _ index: Int) -> JSONValue {
    (row[index] as String?).map(JSONValue.string) ?? .null
  }
  static func int(_ row: Row, _ index: Int) -> JSONValue { .int(row[index]) }
  static func bool(_ row: Row, _ index: Int) -> JSONValue {
    let v: Int64 = row[index]
    return .bool(v != 0)
  }

  // MARK: - calendar_series_cutover

  public static let calendarSeriesCutoverSelectColumns =
    "id, lineage_root_id, cutover_date, state, created_at, updated_at, version"

  static func calendarSeriesCutoverPayloadFromRow(_ row: Row) -> JSONValue {
    .object([
      "id": str(row, 0),
      "lineage_root_id": str(row, 1),
      "cutover_date": str(row, 2),
      "state": str(row, 3),
      "created_at": str(row, 4),
      "updated_at": str(row, 5),
      "version": str(row, 6),
    ])
  }

  public static func loadCalendarSeriesCutoverSyncPayload(
    _ db: Database, id: String
  ) throws -> JSONValue? {
    try Row.fetchOne(
      db,
      sql: "SELECT \(calendarSeriesCutoverSelectColumns) "
        + "FROM calendar_series_cutovers WHERE id = ?1",
      arguments: [id]
    ).map(calendarSeriesCutoverPayloadFromRow)
  }

  // MARK: - task_tag

  public static let taskTagSelectColumns = "task_id, tag_id, version, created_at"

  public static func taskTagPayload(
    taskId: String, tagId: String, version: String, createdAt: String
  ) -> JSONValue {
    .object([
      "task_id": .string(taskId),
      "tag_id": .string(tagId),
      "version": .string(version),
      "created_at": .string(createdAt),
    ])
  }

  static func taskTagPayloadFromRow(_ row: Row) -> JSONValue {
    .object([
      "task_id": str(row, 0),
      "tag_id": str(row, 1),
      "version": str(row, 2),
      "created_at": str(row, 3),
    ])
  }

  public static func loadTaskTagSyncPayload(
    _ db: Database, taskId: String, tagId: String
  ) throws -> JSONValue? {
    try Row.fetchOne(
      db,
      sql: "SELECT \(taskTagSelectColumns) FROM task_tags WHERE task_id = ?1 AND tag_id = ?2",
      arguments: [taskId, tagId]
    ).map(taskTagPayloadFromRow)
  }

  // MARK: - task_dependency

  public static let taskDependencySelectColumns =
    "task_id, depends_on_task_id, version, created_at"

  public static func taskDependencyPayload(
    taskId: String, dependsOnTaskId: String, version: String, createdAt: String
  ) -> JSONValue {
    .object([
      "task_id": .string(taskId),
      "depends_on_task_id": .string(dependsOnTaskId),
      "version": .string(version),
      "created_at": .string(createdAt),
    ])
  }

  static func taskDependencyPayloadFromRow(_ row: Row) -> JSONValue {
    .object([
      "task_id": str(row, 0),
      "depends_on_task_id": str(row, 1),
      "version": str(row, 2),
      "created_at": str(row, 3),
    ])
  }

  // MARK: - preference

  public static let preferenceUpsertSelectColumns = "key, value, updated_at"

  /// Build a preference upsert payload from the column triple. The `value`
  /// column is JSON-encoded TEXT; this helper parses it. A parse failure is a
  /// hard data-corruption signal (callers downstream of the writer have already
  /// canonicalized the JSON).
  public static func preferenceUpsertPayload(
    key: String, valueRaw: String, updatedAt: String
  ) throws -> JSONValue {
    guard let parsed = JSONValue.parse(valueRaw) else {
      throw StoreError.serialization("preference '\(key)' must be canonical JSON")
    }
    return .object([
      "key": .string(key),
      "value": parsed,
      "updated_at": .string(updatedAt),
    ])
  }

  public static func loadPreferenceSyncPayload(_ db: Database, key: String) throws -> JSONValue? {
    guard
      let row = try Row.fetchOne(
        db,
        sql: "SELECT \(preferenceUpsertSelectColumns) FROM preferences WHERE key = ?1",
        arguments: [key])
    else { return nil }
    return try preferenceUpsertPayload(key: row[0], valueRaw: row[1], updatedAt: row[2])
  }

  static let preferenceDeleteSelectColumns = "key, value, version, updated_at"

  static func preferenceDeleteSnapshotFromRow(_ row: Row) -> JSONValue {
    .object([
      "key": str(row, 0),
      "value": optStr(row, 1),
      "version": str(row, 2),
      "updated_at": str(row, 3),
    ])
  }

  public static func loadPreferenceDeleteSnapshot(_ db: Database, key: String) throws -> JSONValue? {
    try Row.fetchOne(
      db,
      sql: "SELECT \(preferenceDeleteSelectColumns) FROM preferences WHERE key = ?1",
      arguments: [key]
    ).map(preferenceDeleteSnapshotFromRow)
  }

  // MARK: - memory

  public static let memorySelectColumns = "id, key, content, version, updated_at"

  static func memoryPayloadFromRow(_ row: Row) -> JSONValue {
    .object([
      "id": str(row, 0),
      "key": str(row, 1),
      "content": str(row, 2),
      "version": str(row, 3),
      "updated_at": str(row, 4),
    ])
  }

  public static func loadMemorySyncPayload(_ db: Database, key: String) throws -> JSONValue? {
    try Row.fetchOne(
      db, sql: "SELECT \(memorySelectColumns) FROM memories WHERE key = ?1", arguments: [key]
    ).map(memoryPayloadFromRow)
  }

  /// Pre-delete tombstone payload for a memory row — reuses the upsert shape.
  public static func loadMemoryDeleteSnapshot(_ db: Database, key: String) throws -> JSONValue? {
    try loadMemorySyncPayload(db, key: key)
  }

  // MARK: - habit

  /// Dedicated habit wire shape. It intentionally omits `lookup_key`: peers
  /// re-derive that value from the validated habit name on apply. The `weekly`
  /// weekday set lives in the `habit_weekdays` child (joined in separately), not
  /// a column here. Generic row snapshots still include physical columns for
  /// local export/debug surfaces, so this loader is the sync contract for
  /// habit envelopes.
  public static let habitSelectColumns =
    "id, name, icon, color, cue, frequency_type, per_period_target, day_of_month, "
    + "target_count, milestone_target, archived, created_at, updated_at, version, position"

  static func habitPayloadFromRow(_ row: Row, weekdays: [WeekDay]) -> JSONValue {
    let dayOfMonth: Int64? = row[7]
    let milestoneTarget: Int64? = row[9]
    let archived: Int64 = row[10]
    let fields = HabitSyncFields(
      id: row[0],
      name: row[1],
      icon: row[2],
      color: row[3],
      cue: row[4],
      frequencyType: row[5],
      weekdays: weekdays,
      perPeriodTarget: row[6],
      dayOfMonth: dayOfMonth.map { Int($0) },
      targetCount: row[8],
      milestoneTarget: milestoneTarget.map { Int($0) },
      archived: archived != 0,
      createdAt: row[11],
      updatedAt: row[12],
      version: row[13],
      position: row[14])
    return habitSyncPayload(fields)
  }

  /// The `weekly` weekday set for a habit, Monday-first (0=Mon … 6=Sun), sorted
  /// ascending. Empty for every non-weekly cadence and for weekly-every-day.
  static func loadHabitWeekdays(_ db: Database, habitId: String) throws -> [WeekDay] {
    try Int64.fetchAll(
      db, sql: "SELECT weekday FROM habit_weekdays WHERE habit_id = ?1 ORDER BY weekday ASC",
      arguments: [habitId]
    ).compactMap { WeekDay(rawValue: Int($0)) }
  }

  public static func loadHabitSyncPayload(_ db: Database, habitId: String) throws -> JSONValue? {
    guard
      let row = try Row.fetchOne(
        db, sql: "SELECT \(habitSelectColumns) FROM habits WHERE id = ?1", arguments: [habitId])
    else { return nil }
    let weekdays = try loadHabitWeekdays(db, habitId: habitId)
    return habitPayloadFromRow(row, weekdays: weekdays)
  }

  // MARK: - habit_completion

  public static let habitCompletionSelectColumns =
    "habit_id, completed_date, value, note, version, created_at, updated_at"

  public static func habitCompletionPayload(
    habitId: String, completedDate: String, value: Int64, note: String?, version: String,
    createdAt: String, updatedAt: String
  ) -> JSONValue {
    .object([
      "habit_id": .string(habitId),
      "completed_date": .string(completedDate),
      "value": .int(value),
      "note": note.map(JSONValue.string) ?? .null,
      "version": .string(version),
      "created_at": .string(createdAt),
      "updated_at": .string(updatedAt),
    ])
  }

  static func habitCompletionPayloadFromRow(_ row: Row) -> JSONValue {
    .object([
      "habit_id": str(row, 0),
      "completed_date": str(row, 1),
      "value": int(row, 2),
      "note": optStr(row, 3),
      "version": str(row, 4),
      "created_at": str(row, 5),
      "updated_at": str(row, 6),
    ])
  }

  public static func loadHabitCompletionSyncPayload(
    _ db: Database, habitId: String, completedDate: String
  ) throws -> JSONValue? {
    try Row.fetchOne(
      db,
      sql:
        "SELECT \(habitCompletionSelectColumns) FROM habit_completions WHERE habit_id = ?1 AND completed_date = ?2",
      arguments: [habitId, completedDate]
    ).map(habitCompletionPayloadFromRow)
  }

  // MARK: - habit_reminder_policy

  public static let habitReminderPolicySelectColumns =
    "id, habit_id, reminder_time, enabled, version, created_at, updated_at"

  static func habitReminderPolicyPayloadFromRow(_ row: Row) -> JSONValue {
    .object([
      "id": str(row, 0),
      "habit_id": str(row, 1),
      "reminder_time": str(row, 2),
      "enabled": bool(row, 3),
      "version": str(row, 4),
      "created_at": str(row, 5),
      "updated_at": str(row, 6),
    ])
  }

  // MARK: - task_calendar_event_link

  public static let taskCalendarEventLinkSelectColumns =
    "task_id, calendar_event_id, version, created_at, updated_at"

  public static func taskCalendarEventLinkPayload(
    taskId: String, calendarEventId: String, version: String, createdAt: String, updatedAt: String
  ) -> JSONValue {
    .object([
      "task_id": .string(taskId),
      "calendar_event_id": .string(calendarEventId),
      "version": .string(version),
      "created_at": .string(createdAt),
      "updated_at": .string(updatedAt),
    ])
  }

  static func taskCalendarEventLinkPayloadFromRow(_ row: Row) -> JSONValue {
    .object([
      "task_id": str(row, 0),
      "calendar_event_id": str(row, 1),
      "version": str(row, 2),
      "created_at": str(row, 3),
      "updated_at": str(row, 4),
    ])
  }

  public static func loadTaskCalendarEventLinkSyncPayload(
    _ db: Database, taskId: String, calendarEventId: String
  ) throws -> JSONValue? {
    try Row.fetchOne(
      db,
      sql:
        "SELECT \(taskCalendarEventLinkSelectColumns) FROM task_calendar_event_links WHERE task_id = ?1 AND calendar_event_id = ?2",
      arguments: [taskId, calendarEventId]
    ).map(taskCalendarEventLinkPayloadFromRow)
  }

  // MARK: - task_checklist_item

  public static let taskChecklistItemSelectColumns =
    "id, task_id, position, text, completed_at, version, created_at, updated_at"

  static func taskChecklistItemPayloadFromRow(_ row: Row) -> JSONValue {
    .object([
      "id": str(row, 0),
      "task_id": str(row, 1),
      "position": int(row, 2),
      "text": str(row, 3),
      "completed_at": optStr(row, 4),
      "version": str(row, 5),
      "created_at": str(row, 6),
      "updated_at": str(row, 7),
    ])
  }

  public static func loadTaskChecklistItemSyncPayload(
    _ db: Database, itemId: String
  ) throws -> JSONValue? {
    try Row.fetchOne(
      db,
      sql: "SELECT \(taskChecklistItemSelectColumns) FROM task_checklist_items WHERE id = ?1",
      arguments: [itemId]
    ).map(taskChecklistItemPayloadFromRow)
  }

  // MARK: - task_reminder

  public static let taskReminderSelectColumns =
    "id, task_id, reminder_at, dismissed_at, cancelled_at, created_at, original_local_time, original_tz, version"

  static func taskReminderPayloadFromRow(_ row: Row) -> JSONValue {
    .object([
      "id": str(row, 0),
      "task_id": str(row, 1),
      "reminder_at": str(row, 2),
      "dismissed_at": optStr(row, 3),
      "cancelled_at": optStr(row, 4),
      "created_at": str(row, 5),
      "original_local_time": optStr(row, 6),
      "original_tz": optStr(row, 7),
      "version": str(row, 8),
    ])
  }

  // `ai_changelog` has no generic loader here. Its emit-on-write projection is
  // built by `ChangelogWrite.buildChangelogSyncPayload`, while inbound apply
  // parses the wire payload directly; neither path needs a table-wide payload
  // loader in this catalog.
}

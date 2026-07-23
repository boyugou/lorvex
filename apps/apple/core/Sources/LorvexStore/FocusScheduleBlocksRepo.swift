import Foundation
import GRDB
import LorvexDomain

/// Shared materialization for the `focus_schedule_blocks` sub-table plus the
/// `focus_schedule` parent-row upserts.
///
/// The single canonical DELETE-then-INSERT loop for materialized blocks lives
/// here; all callers (MCP, app, sync-apply, import) delegate instead of owning
/// independent SQL.
public enum FocusScheduleBlocksRepo {
  /// A normalized schedule block entry with times already converted to
  /// minute-of-day integers. Callers parse HH:MM strings or JSON into this
  /// intermediate representation before calling ``materializeScheduleBlocks``.
  public struct ScheduleBlockEntry: Sendable, Equatable {
    public var blockType: String
    public var startMinutes: Int64
    public var endMinutes: Int64
    public var taskId: String?
    public var calendarEventId: String?
    public var eventSource: FocusScheduleEventSource?
    public var title: String?

    public init(
      blockType: String,
      startMinutes: Int64,
      endMinutes: Int64,
      taskId: String? = nil,
      calendarEventId: String? = nil,
      eventSource: FocusScheduleEventSource? = nil,
      title: String? = nil
    ) {
      self.blockType = blockType
      self.startMinutes = startMinutes
      self.endMinutes = endMinutes
      self.taskId = taskId
      self.calendarEventId = calendarEventId
      self.eventSource = eventSource
      self.title = title
    }
  }

  /// Comparator used by sync-apply LWW upserts. Constrains the comparator
  /// surface to the only two semantically valid operators (a `&str`-shaped
  /// version would in principle let a misuse inject SQL into the WHERE
  /// clause). `greater` is the standard "newer wins" gate; `greaterOrEqual`
  /// is used by replay / shadow-promote paths where re-applying an envelope
  /// at the same version must be a silent rehydrate rather than a no-op.
  public enum SyncVersionCmp: Sendable, Equatable {
    case greater
    case greaterOrEqual

    var asSql: String {
      switch self {
      case .greater: return ">"
      case .greaterOrEqual: return ">="
      }
    }
  }

  /// Materialize schedule blocks for a given date.
  ///
  /// Deletes all existing blocks for `date`, then inserts `blocks`
  /// with sequential positions. Every block must be a non-empty interval inside
  /// `[0, 1440]`; invalid boundaries are rejected rather than silently changed.
  public static func materializeScheduleBlocks(
    _ db: Database,
    date: String,
    blocks: [ScheduleBlockEntry]
  ) throws {
    for block in blocks {
      try validateBlockIdentity(block)
      guard block.startMinutes >= 0, block.endMinutes <= 1440,
        block.endMinutes > block.startMinutes
      else {
        throw StoreError.validation(
          "focus schedule block must satisfy 0 <= start < end <= 1440")
      }
    }
    try db.execute(
      sql: "DELETE FROM focus_schedule_blocks WHERE date = ?1",
      arguments: [date])

    for (position, block) in blocks.enumerated() {
      try db.execute(
        sql: """
          INSERT INTO focus_schedule_blocks \
          (date, position, block_type, start_minutes, end_minutes, task_id, calendar_event_id, event_source, title) \
          VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
          """,
        arguments: [
          date, Int64(position), block.blockType, block.startMinutes, block.endMinutes,
          block.taskId, block.calendarEventId, block.eventSource?.rawValue, block.title,
        ])
    }
  }

  private static func validateBlockIdentity(_ block: ScheduleBlockEntry) throws {
    guard let blockType = FocusBlockType.parse(block.blockType) else {
      throw StoreError.validation("unknown focus schedule block type '\(block.blockType)'")
    }
    switch blockType {
    case .task:
      guard let taskId = block.taskId, SyncEntityId.isCanonicalUuid(taskId),
        block.calendarEventId == nil, block.eventSource == nil
      else {
        throw StoreError.validation(
          "task focus block requires a canonical task_id and no event identity/source")
      }
    case .event:
      guard block.taskId == nil else {
        throw StoreError.validation("event focus block must not set task_id")
      }
      switch block.eventSource {
      case .some(.canonical):
        guard let calendarEventId = block.calendarEventId,
          SyncEntityId.isCanonicalUuid(calendarEventId)
        else {
          throw StoreError.validation(
            "canonical focus event block requires a canonical calendar_event_id")
        }
      case .some(.provider), .some(.freeform):
        guard block.calendarEventId == nil else {
          throw StoreError.validation(
            "provider and freeform focus event blocks must not set calendar_event_id")
        }
      case .none:
        throw StoreError.validation("event focus block requires event_source")
      }
    case .buffer:
      guard block.taskId == nil, block.calendarEventId == nil, block.eventSource == nil else {
        throw StoreError.validation(
          "buffer focus block must not set task_id, calendar_event_id, or event_source")
      }
    }
  }

  /// Create or update the `focus_schedule` parent row.
  ///
  /// Timezone immutability: the ON CONFLICT clause omits `timezone`, so it is
  /// only set on initial INSERT and preserved on subsequent updates. The
  /// conflict UPDATE is gated on `excluded.version > focus_schedule.version`
  /// so a stale local stamp racing an in-flight peer write cannot regress the
  /// row's HLC. Returns `true` if a row was inserted or the LWW gate accepted
  /// the UPDATE; `false` if the existing row's version was strictly newer.
  @discardableResult
  public static func upsertFocusScheduleHeader(
    _ db: Database,
    date: String,
    rationale: String?,
    timezone: String,
    version: String,
    now: String
  ) throws -> Bool {
    // Local-write funnel only (sync applies through syncUpsertFocusSchedule):
    // the rationale byte budget keeps a locally-authored focus_schedule payload
    // provably under the sync byte cap (PayloadByteBudget).
    if let rationale,
      case .failure = PayloadByteBudget.validateEscapedBudget(
        rationale, field: "rationale", budget: PayloadByteBudget.dayPlanTextEscapedBytes)
    {
      throw StoreError.validation(
        "focus_schedule.rationale exceeds the maximum stored size of "
          + "\(PayloadByteBudget.dayPlanTextEscapedBytes) bytes")
    }
    try db.execute(
      sql: """
        INSERT INTO focus_schedule (date, rationale, timezone, version, created_at, updated_at) \
        VALUES (?1, ?2, ?3, ?4, ?5, ?6) \
        ON CONFLICT(date) DO UPDATE SET \
           rationale = excluded.rationale, \
           version = excluded.version, \
           updated_at = excluded.updated_at \
        WHERE excluded.version > focus_schedule.version
        """,
      arguments: [date, rationale, timezone, version, now, now])
    return db.changesCount > 0
  }

  /// Sync-mode upsert: full-entity replacement from another device.
  ///
  /// Unlike local writes, this overwrites `timezone` and `created_at` because
  /// the remote envelope is authoritative. Returns `true` if a row was
  /// inserted or updated, `false` if the existing row was newer (or equal,
  /// under ``SyncVersionCmp/greater``).
  @discardableResult
  public static func syncUpsertFocusSchedule(
    _ db: Database,
    date: String,
    rationale: String?,
    timezone: String?,
    version: String,
    createdAt: String,
    updatedAt: String,
    versionCmp: SyncVersionCmp
  ) throws -> Bool {
    let op = versionCmp.asSql
    try db.execute(
      sql: """
        INSERT INTO focus_schedule (date, rationale, timezone, version, created_at, updated_at) \
        VALUES (?1, ?2, ?3, ?4, ?5, ?6) \
        ON CONFLICT(date) DO UPDATE SET \
           rationale=excluded.rationale, timezone=excluded.timezone, \
           created_at=excluded.created_at, updated_at=excluded.updated_at, \
           version=excluded.version \
        WHERE excluded.version \(op) focus_schedule.version
        """,
      arguments: [date, rationale, timezone, version, createdAt, updatedAt])
    return db.changesCount > 0
  }
}

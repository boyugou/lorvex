import Foundation
import GRDB
import LorvexDomain

/// One row from the `daily_reviews` table plus its rebuilt link
/// projections (`linked_task_ids`, `linked_list_ids`). Field order matches
/// the SELECT column list (`DAILY_REVIEW_ROW_COLS`) used throughout this
/// module so positional row reads stay straight.
public struct DailyReviewRow: Sendable, Equatable {
  public let date: String
  public let summary: String
  public let mood: Int64?
  public let energyLevel: Int64?
  public let wins: String?
  public let blockers: String?
  public let learnings: String?
  public let timezone: String?
  public let version: String
  public let createdAt: String
  public let updatedAt: String
  public let linkedTaskIds: [String]
  public let linkedListIds: [String]
}

/// Window into the `daily_reviews` history table: ordered by `date DESC`,
/// optional inclusive date bounds, bounded by `limit` / `offset`.
public struct DailyReviewHistoryQuery: Sendable, Equatable {
  public let since: String?
  public let until: String?
  public let limit: Int
  public let offset: Int

  public init(since: String? = nil, until: String? = nil, limit: Int, offset: Int = 0) {
    self.since = since
    self.until = until
    self.limit = limit
    self.offset = offset
  }
}

/// One bounded page of ``DailyReviewRow`` plus the unbounded match count
/// (filtered by query bounds when set).
public struct DailyReviewHistoryPage: Sendable, Equatable {
  public let rows: [DailyReviewRow]
  public let totalMatching: Int64
}

/// Inputs to ``DailyReviewOpsRepo/upsertDailyReview(_:params:)``. This is a
/// complete replacement value: `nil` clears an optional field. Call
/// ``DailyReviewOpsRepo/amendDailyReview(_:params:)`` for patch semantics.
public struct UpsertDailyReviewParams: Sendable {
  public let date: String
  public let summary: String
  public let mood: Int64?
  public let energyLevel: Int64?
  public let wins: String?
  public let blockers: String?
  public let learnings: String?
  public let timezone: String
  public let version: String
  public let now: String

  public init(
    date: String,
    summary: String,
    mood: Int64? = nil,
    energyLevel: Int64? = nil,
    wins: String? = nil,
    blockers: String? = nil,
    learnings: String? = nil,
    timezone: String,
    version: String,
    now: String
  ) {
    self.date = date
    self.summary = summary
    self.mood = mood
    self.energyLevel = energyLevel
    self.wins = wins
    self.blockers = blockers
    self.learnings = learnings
    self.timezone = timezone
    self.version = version
    self.now = now
  }
}

/// Inputs to ``DailyReviewOpsRepo/amendDailyReview(_:params:)``. Only
/// non-nil fields participate in the UPDATE SET. `timezoneBackfill` is
/// applied only when the existing row's `timezone` is NULL (backfill,
/// not overwrite).
public struct AmendDailyReviewParams: Sendable {
  public let date: String
  public let summary: String?
  public let mood: Int64?
  public let energyLevel: Int64?
  public let wins: String?
  public let blockers: String?
  public let learnings: String?
  public let timezoneBackfill: String?
  public let version: String
  public let now: String

  public init(
    date: String,
    summary: String? = nil,
    mood: Int64? = nil,
    energyLevel: Int64? = nil,
    wins: String? = nil,
    blockers: String? = nil,
    learnings: String? = nil,
    timezoneBackfill: String? = nil,
    version: String,
    now: String
  ) {
    self.date = date
    self.summary = summary
    self.mood = mood
    self.energyLevel = energyLevel
    self.wins = wins
    self.blockers = blockers
    self.learnings = learnings
    self.timezoneBackfill = timezoneBackfill
    self.version = version
    self.now = now
  }
}

/// Shared parent-row operations for the `daily_reviews` table — the
/// canonical upsert with timezone immutability, the sync-apply replace,
/// the partial-field amend, and the link-projection materializers.
public enum DailyReviewOpsRepo {

  /// Canonical SELECT column list shared by every read. Order matches the
  /// ``DailyReviewRow`` field order so positional reads stay straight.
  public static let rowColumns = """
    date, summary, mood, energy_level, wins, blockers, \
    learnings, timezone, version, created_at, updated_at
    """

  // MARK: - Reads

  /// Fetch a single `daily_reviews` row by date, enriched with its
  /// rebuilt link projections. Returns `nil` when no row matches.
  public static func getDailyReviewRow(
    _ db: Database, date: String
  ) throws -> DailyReviewRow? {
    let sql = "SELECT \(rowColumns) FROM daily_reviews WHERE date = ?"
    guard let row = try Row.fetchOne(db, sql: sql, arguments: [date]) else {
      return nil
    }
    let base = decodeRow(row, taskIds: [], listIds: [])
    let (taskIds, listIds) = try fetchLinkIds(db, dates: [base.date])
    return DailyReviewRow(
      date: base.date,
      summary: base.summary,
      mood: base.mood,
      energyLevel: base.energyLevel,
      wins: base.wins,
      blockers: base.blockers,
      learnings: base.learnings,
      timezone: base.timezone,
      version: base.version,
      createdAt: base.createdAt,
      updatedAt: base.updatedAt,
      linkedTaskIds: taskIds[base.date] ?? [],
      linkedListIds: listIds[base.date] ?? [])
  }

  /// Paginate `daily_reviews` history ordered by `date DESC`. The page
  /// carries the unbounded match count (filtered by `since` when set) so
  /// callers can render a total alongside the windowed rows.
  public static func listDailyReviewRows(
    _ db: Database, query: DailyReviewHistoryQuery
  ) throws -> DailyReviewHistoryPage {
    var whereClauses: [String] = []
    var boundValues: [String] = []
    if let since = query.since {
      whereClauses.append("date >= ?")
      boundValues.append(since)
    }
    if let until = query.until {
      whereClauses.append("date <= ?")
      boundValues.append(until)
    }
    let whereSQL = whereClauses.isEmpty ? "" : " WHERE " + whereClauses.joined(separator: " AND ")

    let total = try Int64.fetchOne(
      db,
      sql: "SELECT COUNT(*) FROM daily_reviews\(whereSQL)",
      arguments: StatementArguments(boundValues)) ?? 0

    let limit = Int64(query.limit)
    let offset = Int64(query.offset)
    var pageArgs: [DatabaseValueConvertible] = boundValues
    pageArgs.append(limit)
    pageArgs.append(offset)
    let dates = try String.fetchAll(
      db,
      sql: "SELECT date FROM daily_reviews\(whereSQL) ORDER BY date DESC LIMIT ? OFFSET ?",
      arguments: StatementArguments(pageArgs))
    return DailyReviewHistoryPage(
      rows: try loadRowsForDates(db, dates: dates),
      totalMatching: total)
  }

  private struct BaseRow {
    let date: String
    let summary: String
    let mood: Int64?
    let energyLevel: Int64?
    let wins: String?
    let blockers: String?
    let learnings: String?
    let timezone: String?
    let version: String
    let createdAt: String
    let updatedAt: String
  }

  private static func decodeRow(_ row: Row, taskIds: [String], listIds: [String]) -> BaseRow {
    BaseRow(
      date: row[0],
      summary: row[1],
      mood: row[2],
      energyLevel: row[3],
      wins: row[4],
      blockers: row[5],
      learnings: row[6],
      timezone: row[7],
      version: row[8],
      createdAt: row[9],
      updatedAt: row[10])
  }

  private static func loadRowsForDates(
    _ db: Database, dates: [String]
  ) throws -> [DailyReviewRow] {
    if dates.isEmpty { return [] }
    let placeholders = Array(repeating: "?", count: dates.count).joined(separator: ", ")
    let sql = "SELECT \(rowColumns) FROM daily_reviews WHERE date IN (\(placeholders))"
    var rowsByDate: [String: BaseRow] = [:]
    let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(dates))
    for row in rows {
      let base = decodeRow(row, taskIds: [], listIds: [])
      rowsByDate[base.date] = base
    }
    let (taskIds, listIds) = try fetchLinkIds(db, dates: dates)
    return try dates.map { date in
      guard let base = rowsByDate[date] else {
        throw StoreError.validation(
          "daily review '\(date)' disappeared while loading history")
      }
      return DailyReviewRow(
        date: base.date,
        summary: base.summary,
        mood: base.mood,
        energyLevel: base.energyLevel,
        wins: base.wins,
        blockers: base.blockers,
        learnings: base.learnings,
        timezone: base.timezone,
        version: base.version,
        createdAt: base.createdAt,
        updatedAt: base.updatedAt,
        linkedTaskIds: taskIds[date] ?? [],
        linkedListIds: listIds[date] ?? [])
    }
  }

  /// Returns `(taskIdsByDate, listIdsByDate)` for `dates`.
  ///
  /// `daily_review_task_links.task_id` / `daily_review_list_links.list_id`
  /// carry no foreign key (only `review_date` cascades), so a task or list
  /// permanently deleted after the review linked it leaves a dangling link
  /// row. Each read EXISTS-filters against the live `tasks` / `lists` tables
  /// so a review never surfaces an id whose target no longer exists —
  /// matching the soft-ref filtering the sibling `current_focus_items` /
  /// `focus_schedule_blocks` reads apply.
  private static func fetchLinkIds(
    _ db: Database, dates: [String]
  ) throws -> ([String: [String]], [String: [String]]) {
    if dates.isEmpty { return ([:], [:]) }
    let placeholders = Array(repeating: "?", count: dates.count).joined(separator: ", ")

    var taskIds: [String: [String]] = [:]
    let taskSQL = """
      SELECT review_date, task_id FROM daily_review_task_links \
      WHERE review_date IN (\(placeholders)) \
      AND EXISTS (SELECT 1 FROM tasks WHERE tasks.id = daily_review_task_links.task_id) \
      ORDER BY review_date ASC, task_id ASC
      """
    let taskRows = try Row.fetchAll(db, sql: taskSQL, arguments: StatementArguments(dates))
    for row in taskRows {
      let date: String = row[0]
      let id: String = row[1]
      taskIds[date, default: []].append(id)
    }

    var listIds: [String: [String]] = [:]
    let listSQL = """
      SELECT review_date, list_id FROM daily_review_list_links \
      WHERE review_date IN (\(placeholders)) \
      AND EXISTS (SELECT 1 FROM lists WHERE lists.id = daily_review_list_links.list_id) \
      ORDER BY review_date ASC, list_id ASC
      """
    let listRows = try Row.fetchAll(db, sql: listSQL, arguments: StatementArguments(dates))
    for row in listRows {
      let date: String = row[0]
      let id: String = row[1]
      listIds[date, default: []].append(id)
    }
    return (taskIds, listIds)
  }

  // MARK: - Writes

  /// Sanitize a daily-review free-text field: strip invisible / bidi / control
  /// codepoints and NFC-normalize. Every local write funnel (upsert, amend) and
  /// the import surface run their free-text through this so a review's
  /// `summary` / `wins` / `blockers` / `learnings` cannot carry
  /// a rendering-attack payload into storage or across sync.
  public static func scrubReviewText(_ value: String) -> String {
    UnicodeHygiene.sanitizeUserText(value)
  }

  /// `nil`-preserving ``scrubReviewText(_:)`` for the optional review fields.
  public static func scrubReviewText(_ value: String?) -> String? {
    value.map(UnicodeHygiene.sanitizeUserText)
  }

  /// Reject a `mood` / `energy_level` outside the 1…5 scale (NULL passes) before
  /// the SQL bind. This is the single local write path every daily-review caller
  /// funnels through (`upsertDailyReview` / `amendDailyReview`), so no caller —
  /// interactive upsert, `importDailyReview`, or amend — can reach the raw
  /// `CHECK (mood/energy_level BETWEEN 1 AND 5)` and surface an opaque
  /// `SQLITE_CONSTRAINT`; an out-of-range value fails with a typed validation
  /// error instead. The sync-apply path validates separately at its own trust
  /// boundary (``syncUpsertDailyReview`` callers).
  static func validateMoodEnergyScale(mood: Int64?, energyLevel: Int64?) throws {
    for (field, value) in [("mood", mood), ("energy_level", energyLevel)] {
      guard let value else { continue }
      if !(ValidationLimits.moodMin...ValidationLimits.moodMax).contains(value) {
        throw StoreError.validation(
          "daily_reviews.\(field) must be between \(ValidationLimits.moodMin) and "
            + "\(ValidationLimits.moodMax) or null (got \(value))")
      }
    }
  }

  /// Reject a review text field above its canonical-escaped byte budget
  /// (``PayloadByteBudget/reviewTextEscapedBytes``). Four long-form fields ride
  /// one `daily_reviews` payload, so per-field budgets — not just codepoint
  /// caps — keep the whole payload provably under the sync byte cap. Shares
  /// the ``validateMoodEnergyScale(mood:energyLevel:)`` funnel position: both
  /// local write paths (`upsertDailyReview` / `amendDailyReview`) call it, so
  /// no interactive or import caller can bypass it.
  public static func validateReviewTextBudgets(
    summary: String?, wins: String?, blockers: String?, learnings: String?
  ) throws {
    for (field, value) in [
      ("summary", summary), ("wins", wins), ("blockers", blockers), ("learnings", learnings),
    ] {
      guard let value else { continue }
      if case .failure = PayloadByteBudget.validateEscapedBudget(
        value, field: field, budget: PayloadByteBudget.reviewTextEscapedBytes)
      {
        throw StoreError.validation(
          "daily_reviews.\(field) exceeds the maximum stored size of "
            + "\(PayloadByteBudget.reviewTextEscapedBytes) bytes")
      }
    }
  }

  /// Create or update a daily review.
  ///
  /// Timezone immutability: the ON CONFLICT clause intentionally excludes
  /// `timezone` and `created_at`, so both are only set on initial INSERT
  /// and preserved on subsequent updates. Optional fields (`mood`,
  /// `energy_level`, `wins`, `blockers`, `learnings`) are replaced exactly;
  /// a `nil` input clears the stored value. The separate amend operation owns
  /// partial-update semantics.
  ///
  /// LWW gate on the conflict UPDATE: `excluded.version > daily_reviews.version`.
  /// Returns `true` when a row was inserted or the LWW gate accepted the
  /// UPDATE; `false` when the existing row's version was strictly newer
  /// and the upsert became a no-op.
  @discardableResult
  public static func upsertDailyReview(
    _ db: Database, params: UpsertDailyReviewParams
  ) throws -> Bool {
    try validateMoodEnergyScale(mood: params.mood, energyLevel: params.energyLevel)
    try validateReviewTextBudgets(
      summary: params.summary, wins: params.wins, blockers: params.blockers,
      learnings: params.learnings)
    try db.execute(
      sql: """
        INSERT INTO daily_reviews \
        (date, summary, mood, energy_level, wins, blockers, learnings, \
         timezone, version, created_at, updated_at) \
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) \
        ON CONFLICT(date) DO UPDATE SET \
           summary = excluded.summary, \
           mood = excluded.mood, \
           energy_level = excluded.energy_level, \
           wins = excluded.wins, \
           blockers = excluded.blockers, \
           learnings = excluded.learnings, \
           version = excluded.version, \
           updated_at = excluded.updated_at \
        WHERE excluded.version > daily_reviews.version
        """,
      arguments: [
        params.date, scrubReviewText(params.summary), params.mood, params.energyLevel,
        scrubReviewText(params.wins), scrubReviewText(params.blockers),
        scrubReviewText(params.learnings),
        params.timezone, params.version, params.now, params.now,
      ])
    return db.changesCount > 0
  }

  /// Convert the bool no-op contract from ``upsertDailyReview`` into the
  /// typed stale-version error every local write boundary expects.
  public static func requireDailyReviewWriteApplied(_ applied: Bool, date: String) throws {
    if !applied {
      throw StoreError.staleVersion(entity: EntityName.dailyReview, id: date)
    }
  }

  /// Sync-mode upsert: full-entity replacement from another device's
  /// envelope. Unlike local writes, this overwrites `timezone` and
  /// `created_at` because the remote envelope is authoritative; it also
  /// performs direct field assignment (no COALESCE) since sync payloads
  /// carry the complete canonical state.
  ///
  /// `versionCmp` is `">"` for normal sync or `">="` when capability
  /// negotiation allows equal-version acceptance.
  @discardableResult
  public static func syncUpsertDailyReview(
    _ db: Database,
    date: String,
    summary: String,
    mood: Int64?,
    energyLevel: Int64?,
    wins: String?,
    blockers: String?,
    learnings: String?,
    timezone: String?,
    version: String,
    createdAt: String,
    updatedAt: String,
    versionCmp: String
  ) throws -> Bool {
    let op: String
    switch versionCmp {
    case ">": op = ">"
    case ">=": op = ">="
    default:
      throw DatabaseError(
        resultCode: .SQLITE_MISUSE,
        message:
          "syncUpsertDailyReview: versionCmp must be \">\" or \">=\", got \(versionCmp)")
    }
    let sql = """
      INSERT INTO daily_reviews \
      (date, summary, mood, energy_level, wins, blockers, learnings, \
       timezone, created_at, updated_at, version) \
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) \
      ON CONFLICT(date) DO UPDATE SET \
         summary=excluded.summary, mood=excluded.mood, energy_level=excluded.energy_level, \
         wins=excluded.wins, blockers=excluded.blockers, learnings=excluded.learnings, \
         timezone=excluded.timezone, \
         created_at=excluded.created_at, updated_at=excluded.updated_at, \
         version=excluded.version \
      WHERE excluded.version \(op) daily_reviews.version
      """
    try db.execute(
      sql: sql,
      arguments: [
        date, summary, mood, energyLevel, wins, blockers, learnings,
        timezone, createdAt, updatedAt, version,
      ])
    return db.changesCount > 0
  }

  /// Amend (partially update) an existing daily review row. Only fields
  /// that are non-nil in `params` are included in the UPDATE SET.
  /// `timezoneBackfill` is applied only when the existing row's
  /// `timezone` is NULL (backfill, never overwrite). Always sets
  /// `version` and `updated_at`. LWW-gated on `?version > version`.
  ///
  /// Returns `true` when a row was updated, `false` when no row exists
  /// for the date or the LWW gate rejected the write.
  @discardableResult
  public static func amendDailyReview(
    _ db: Database, params: AmendDailyReviewParams
  ) throws -> Bool {
    try validateMoodEnergyScale(mood: params.mood, energyLevel: params.energyLevel)
    try validateReviewTextBudgets(
      summary: params.summary, wins: params.wins, blockers: params.blockers,
      learnings: params.learnings)
    var setClauses: [String] = []
    var arguments: [DatabaseValueConvertible?] = []

    if let summary = params.summary {
      setClauses.append("summary = ?")
      arguments.append(scrubReviewText(summary))
    }
    if let mood = params.mood {
      setClauses.append("mood = ?")
      arguments.append(mood)
    }
    if let energy = params.energyLevel {
      setClauses.append("energy_level = ?")
      arguments.append(energy)
    }
    if let wins = params.wins {
      setClauses.append("wins = ?")
      arguments.append(scrubReviewText(wins))
    }
    if let blockers = params.blockers {
      setClauses.append("blockers = ?")
      arguments.append(scrubReviewText(blockers))
    }
    if let learnings = params.learnings {
      setClauses.append("learnings = ?")
      arguments.append(scrubReviewText(learnings))
    }
    if let tz = params.timezoneBackfill {
      setClauses.append("timezone = CASE WHEN timezone IS NULL THEN ? ELSE timezone END")
      arguments.append(tz)
    }
    // Always bump version + updated_at.
    setClauses.append("version = ?")
    arguments.append(params.version)
    setClauses.append("updated_at = ?")
    arguments.append(params.now)
    // WHERE: id, then LWW version guard.
    arguments.append(params.date)
    arguments.append(params.version)
    let sql = """
      UPDATE daily_reviews SET \(setClauses.joined(separator: ", ")) \
      WHERE date = ? AND ? > version
      """
    try db.execute(sql: sql, arguments: StatementArguments(arguments))
    return db.changesCount > 0
  }

  // MARK: - Child link materialization

  /// Materialize `daily_review_task_links` for `date`. DELETE-then-INSERT;
  /// `INSERT OR IGNORE` collapses duplicates against the PK.
  ///
  /// Orphan breadcrumbs belong to the app/runtime telemetry layer; this pure
  /// store helper only materializes the canonical link rows.
  /// Reject a locally-authored link set above the ``PayloadByteBudget`` count
  /// caps. Called by the LOCAL write funnel (the service's review-write
  /// finalizer) but deliberately not by the materializers below: the sync
  /// applier rebuilds links through them, and a peer's payload — bounded as a
  /// whole by the wire byte cap — must never wedge an inbound page on a local
  /// policy cap.
  public static func validateLocalReviewLinkCounts(
    taskIds: [String]?, listIds: [String]?
  ) throws {
    if let taskIds, taskIds.count > PayloadByteBudget.maxReviewLinkedTasks {
      throw StoreError.validation(
        "a daily review links at most \(PayloadByteBudget.maxReviewLinkedTasks) tasks "
          + "(got \(taskIds.count))")
    }
    if let listIds, listIds.count > PayloadByteBudget.maxReviewLinkedLists {
      throw StoreError.validation(
        "a daily review links at most \(PayloadByteBudget.maxReviewLinkedLists) lists "
          + "(got \(listIds.count))")
    }
  }

  public static func materializeReviewTaskLinks(
    _ db: Database, date: String, taskIds: [String]
  ) throws {
    try db.execute(
      sql: "DELETE FROM daily_review_task_links WHERE review_date = ?",
      arguments: [date])
    // These links are a set, not a user-ordered sequence. Canonicalize before
    // materializing so every device projects and re-emits identical arrays
    // regardless of input order, duplicate values, or local wall-clock timing.
    for taskId in Set(taskIds).sorted() {
      try db.execute(
        sql: """
          INSERT OR IGNORE INTO daily_review_task_links (review_date, task_id, created_at) \
          VALUES (?, ?, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
          """,
        arguments: [date, taskId])
    }
  }

  /// Materialize `daily_review_list_links` for `date`. Same DELETE-then-
  /// INSERT contract as ``materializeReviewTaskLinks(_:date:taskIds:)``.
  public static func materializeReviewListLinks(
    _ db: Database, date: String, listIds: [String]
  ) throws {
    try db.execute(
      sql: "DELETE FROM daily_review_list_links WHERE review_date = ?",
      arguments: [date])
    for listId in Set(listIds).sorted() {
      try db.execute(
        sql: """
          INSERT OR IGNORE INTO daily_review_list_links (review_date, list_id, created_at) \
          VALUES (?, ?, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
          """,
        arguments: [date, listId])
    }
  }
}

import Foundation
import GRDB

/// Test-fixture and benchmark-seeder helper for the FTS5 SQL over the
/// `tasks_fts_trigram` and `calendar_events_fts` indexes. In the product both
/// indexes are kept current entirely by the SQL triggers declared in
/// `schema/schema.sql`; this type packages the equivalent mutation and
/// trigger-install SQL for the benchmark seeder (`BenchmarkSeeder`) and the
/// store FTS tests, which drive the index directly.
///
/// Both tables are external-content FTS5 indexes, so a single-row update
/// is expressed as the canonical "tombstone then re-insert" idiom: the
/// `'delete'` command form removes the row's postings (using the row's
/// *previous* column values to invert the postings list), then a bare
/// insert re-projects the new column values. Passing NEW values or NULLs
/// to the tombstone leaks stale 3-grams into the index.
public enum FtsRepo {

  // MARK: - tasks_fts_trigram

  /// Tombstone SQL — pass the row's previous column values.
  public static let tasksTrigramTombstoneSQL = """
    INSERT INTO tasks_fts_trigram\
    (tasks_fts_trigram, rowid, title, body, ai_notes) \
    VALUES ('delete', ?, ?, ?, ?)
    """

  /// Bare-insert SQL.
  public static let tasksTrigramInsertSQL = """
    INSERT INTO tasks_fts_trigram\
    (rowid, title, body, ai_notes) \
    VALUES (?, ?, ?, ?)
    """

  /// Searchable column tuple for `tasks_fts_trigram`. Field order matches
  /// the FTS5 schema declaration order (`title`, `body`, `ai_notes`).
  public struct TasksTrigramColumns: Sendable, Equatable {
    public var title: String?
    public var body: String?
    public var aiNotes: String?

    public init(title: String? = nil, body: String? = nil, aiNotes: String? = nil) {
      self.title = title
      self.body = body
      self.aiNotes = aiNotes
    }
  }

  /// Tombstone the row's postings without re-inserting. Pass the *previous*
  /// column values; the `'delete'` command is a no-op when no matching
  /// postings exist.
  @discardableResult
  public static func tasksFtsTrigramDelete(
    _ db: Database, rowid: Int64, previous: TasksTrigramColumns
  ) throws -> Int {
    try db.execute(
      sql: tasksTrigramTombstoneSQL,
      arguments: [rowid, previous.title, previous.body, previous.aiNotes])
    return db.changesCount
  }

  /// Upsert a single `tasks_fts_trigram` row via the tombstone-then-insert
  /// idiom. On a fresh insert pass ``TasksTrigramColumns()`` for `previous` —
  /// the `'delete'` command is a no-op when no matching postings exist.
  public static func tasksFtsTrigramUpsert(
    _ db: Database,
    rowid: Int64,
    previous: TasksTrigramColumns,
    next: TasksTrigramColumns
  ) throws {
    try db.execute(
      sql: tasksTrigramTombstoneSQL,
      arguments: [rowid, previous.title, previous.body, previous.aiNotes])
    try db.execute(
      sql: tasksTrigramInsertSQL,
      arguments: [rowid, next.title, next.body, next.aiNotes])
  }

  /// `CREATE TRIGGER IF NOT EXISTS` DDL kept in lockstep with `schema/schema.sql`,
  /// re-installed by tests/benchmarks after they dropped the triggers to drive
  /// the index by hand.
  static let tasksTrigramTriggersSQL = """
    CREATE TRIGGER IF NOT EXISTS tasks_fts_trigram_insert AFTER INSERT ON tasks BEGIN
        INSERT INTO tasks_fts_trigram(rowid, title, body, ai_notes)
        VALUES (new.rowid, new.title, new.body, new.ai_notes);
    END;

    CREATE TRIGGER IF NOT EXISTS tasks_fts_trigram_update AFTER UPDATE OF title, body, ai_notes ON tasks BEGIN
        INSERT INTO tasks_fts_trigram(tasks_fts_trigram, rowid, title, body, ai_notes)
        VALUES ('delete', old.rowid, old.title, old.body, old.ai_notes);
        INSERT INTO tasks_fts_trigram(rowid, title, body, ai_notes)
        VALUES (new.rowid, new.title, new.body, new.ai_notes);
    END;

    CREATE TRIGGER IF NOT EXISTS tasks_fts_trigram_delete AFTER DELETE ON tasks BEGIN
        INSERT INTO tasks_fts_trigram(tasks_fts_trigram, rowid, title, body, ai_notes)
        VALUES ('delete', old.rowid, old.title, old.body, old.ai_notes);
    END;
    """

  static let tasksTrigramDropTriggersSQL = """
    DROP TRIGGER IF EXISTS tasks_fts_trigram_insert;
    DROP TRIGGER IF EXISTS tasks_fts_trigram_update;
    DROP TRIGGER IF EXISTS tasks_fts_trigram_delete;
    """

  static let tasksTrigramRebuildSQL =
    "INSERT INTO tasks_fts_trigram(tasks_fts_trigram) VALUES('rebuild');"

  /// Install the `tasks_fts_trigram_*` triggers (idempotent).
  public static func installTasksTrigramTriggers(_ db: Database) throws {
    try db.execute(sql: tasksTrigramTriggersSQL)
  }

  /// Drop the `tasks_fts_trigram_*` triggers so a caller can populate the index
  /// by hand (used by the benchmark seeder and FTS tests).
  public static func dropTasksTrigramTriggers(_ db: Database) throws {
    try db.execute(sql: tasksTrigramDropTriggersSQL)
  }

  /// Repopulate the trigram index from the backing `tasks` table.
  public static func rebuildTasksTrigram(_ db: Database) throws {
    try db.execute(sql: tasksTrigramRebuildSQL)
  }

  // MARK: - tasks_fts (full-content)

  /// Clear-and-reproject SQL for the full-content `tasks_fts` index: delete every
  /// row, then re-insert one row per `tasks` row with the aggregated `tags`
  /// column recomputed exactly as the `tasks_fts_*` triggers do.
  ///
  /// `tasks_fts` is a full-content table (no `content='tasks'`) because its
  /// `tags` column has no 1:1 backing column on `tasks`, so FTS5's `'rebuild'`
  /// command cannot serve it. A ground-up rebuild is therefore an explicit
  /// `DELETE` followed by a re-projecting `INSERT ... SELECT`.
  public static let tasksFtsRebuildSQL = """
    DELETE FROM tasks_fts;
    INSERT INTO tasks_fts(rowid, title, body, ai_notes, tags)
    SELECT t.rowid, t.title, t.body, t.ai_notes,
           (SELECT GROUP_CONCAT(dn, ' ') FROM (SELECT tg.display_name AS dn FROM task_tags tt JOIN tags tg ON tg.id = tt.tag_id WHERE tt.task_id = t.id ORDER BY tg.lookup_key ASC))
      FROM tasks t;
    """

  /// Clear the full-content `tasks_fts` index and re-project it from `tasks`.
  public static func rebuildTasksFts(_ db: Database) throws {
    try db.execute(sql: tasksFtsRebuildSQL)
  }

  // MARK: - calendar_events_fts

  /// Tombstone SQL — pass the row's previous column values.
  public static let calendarEventsFtsTombstoneSQL = """
    INSERT INTO calendar_events_fts\
    (calendar_events_fts, rowid, title, description, location) \
    VALUES ('delete', ?, ?, ?, ?)
    """

  /// Bare-insert SQL.
  public static let calendarEventsFtsInsertSQL = """
    INSERT INTO calendar_events_fts\
    (rowid, title, description, location) \
    VALUES (?, ?, ?, ?)
    """

  /// Searchable column tuple for `calendar_events_fts`. Field order matches
  /// the FTS5 schema declaration order (`title`, `description`, `location`).
  public struct CalendarEventsColumns: Sendable, Equatable {
    public var title: String?
    public var description: String?
    public var location: String?

    public init(title: String? = nil, description: String? = nil, location: String? = nil) {
      self.title = title
      self.description = description
      self.location = location
    }
  }

  /// Upsert a single `calendar_events_fts` row via the tombstone-then-insert
  /// idiom.
  public static func calendarEventsFtsUpsert(
    _ db: Database,
    rowid: Int64,
    previous: CalendarEventsColumns,
    next: CalendarEventsColumns
  ) throws {
    try db.execute(
      sql: calendarEventsFtsTombstoneSQL,
      arguments: [rowid, previous.title, previous.description, previous.location])
    try db.execute(
      sql: calendarEventsFtsInsertSQL,
      arguments: [rowid, next.title, next.description, next.location])
  }

  static let calendarEventsFtsTriggersSQL = """
    CREATE TRIGGER IF NOT EXISTS calendar_events_fts_insert AFTER INSERT ON calendar_events BEGIN
        INSERT INTO calendar_events_fts(rowid, title, description, location)
        VALUES (new.rowid, new.title, new.description, new.location);
    END;

    CREATE TRIGGER IF NOT EXISTS calendar_events_fts_update AFTER UPDATE OF title, description, location ON calendar_events BEGIN
        INSERT INTO calendar_events_fts(calendar_events_fts, rowid, title, description, location)
        VALUES ('delete', old.rowid, old.title, old.description, old.location);
        INSERT INTO calendar_events_fts(rowid, title, description, location)
        VALUES (new.rowid, new.title, new.description, new.location);
    END;

    CREATE TRIGGER IF NOT EXISTS calendar_events_fts_delete AFTER DELETE ON calendar_events BEGIN
        INSERT INTO calendar_events_fts(calendar_events_fts, rowid, title, description, location)
        VALUES ('delete', old.rowid, old.title, old.description, old.location);
    END;
    """

  static let calendarEventsFtsDropTriggersSQL = """
    DROP TRIGGER IF EXISTS calendar_events_fts_insert;
    DROP TRIGGER IF EXISTS calendar_events_fts_update;
    DROP TRIGGER IF EXISTS calendar_events_fts_delete;
    """

  static let calendarEventsFtsRebuildSQL =
    "INSERT INTO calendar_events_fts(calendar_events_fts) VALUES('rebuild');"

  /// SQL that asks FTS5 to compact accumulated segments.
  public static let calendarEventsFtsOptimizeSQL =
    "INSERT INTO calendar_events_fts(calendar_events_fts) VALUES('optimize');"

  /// Install the `calendar_events_fts_*` triggers (idempotent).
  public static func installCalendarEventsFtsTriggers(_ db: Database) throws {
    try db.execute(sql: calendarEventsFtsTriggersSQL)
  }

  /// Drop the `calendar_events_fts_*` triggers.
  public static func dropCalendarEventsFtsTriggers(_ db: Database) throws {
    try db.execute(sql: calendarEventsFtsDropTriggersSQL)
  }

  /// Repopulate the index from the backing `calendar_events` table.
  public static func rebuildCalendarEventsFts(_ db: Database) throws {
    try db.execute(sql: calendarEventsFtsRebuildSQL)
  }
}

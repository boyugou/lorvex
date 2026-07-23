import Foundation
import GRDB

/// Entry point for the SQLite-backed Apple core store.
///
/// Wraps a GRDB `DatabaseQueue`/`DatabasePool` and applies the authoritative
/// SQLite schema verbatim at open time. The schema is supplied by the caller as
/// a DDL string (read from the root `schema/schema.sql` in production) so this
/// module has no embedded second copy of the schema. The packaged Apple app
/// supplies its byte-verified resource copy of the canonical Apple authority.
public final class LorvexStore: @unchecked Sendable {
  /// The underlying GRDB writer. Exposed so repositories living in this module
  /// can issue queries; external callers should go through repository APIs.
  public let writer: any DatabaseWriter

  /// Set when `open(at:schemaSQL:)` could not open the existing file because it
  /// was unreadable / not a database / structurally incompatible, and therefore
  /// quarantined it and started fresh. `nil` on a normal open. The host reads
  /// this once after opening to surface a "your previous data was set aside"
  /// notice; the renamed file is never deleted, so the data stays recoverable.
  public private(set) var recovery: DatabaseRecovery?

  private init(writer: any DatabaseWriter) {
    self.writer = writer
  }

  /// Describes a one-time quarantine performed at open time: the original
  /// database was renamed aside and an empty one created in its place.
  public struct DatabaseRecovery: Sendable, Equatable {
    /// Where the unreadable/incompatible database (and any `-wal`/`-shm`
    /// sidecars) were moved. The data is preserved here, never deleted.
    public let backupURL: URL
    /// Human-readable reason the original could not be opened.
    public let reason: String
  }

  /// Raised when an existing on-disk database does not match the current
  /// schema. Two causes, resolved differently by the `open` path:
  ///
  /// - ``Kind/checksumMismatch``: a readable, versioned database (or a
  ///   registered numbered migration) whose recorded checksum differs from the
  ///   expected one. This almost always means a broken or tampered build rather
  ///   than corrupt user data, so `open` FAILS CLOSED — it re-throws and leaves
  ///   the file untouched, never quarantining healthy data into an empty app.
  /// - ``Kind/missingBookkeeping``: a data-bearing database carrying no
  ///   `schema_migrations` row to verify against. Unverifiable against the
  ///   current schema, so `open` quarantines the file and starts fresh.
  public struct SchemaMismatch: Error, Equatable {
    /// Why the on-disk database does not match, and thus how `open` resolves it
    /// (fail-closed re-throw vs quarantine-and-recreate).
    public enum Kind: Sendable, Equatable {
      /// A recorded checksum differs from the expected one on an otherwise
      /// readable database or numbered migration. Fail-closed: re-throw.
      case checksumMismatch
      /// A data-bearing database carries no bookkeeping row to verify.
      /// Quarantine the file and start fresh.
      case missingBookkeeping
    }

    /// Which cause fired, and thus the open path's resolution.
    public let kind: Kind
    /// The checksum recorded in the DB (or a placeholder when absent).
    public let recorded: String
    /// The checksum the current schema expects.
    public let expected: String

    public init(kind: Kind, recorded: String, expected: String) {
      self.kind = kind
      self.recorded = recorded
      self.expected = expected
    }
  }

  /// Raised by the managed-open completeness probe when a database opened and
  /// passed checksum verification but its LIVE structure is unusable: one or
  /// more load-bearing tables are absent from `sqlite_master`, or `PRAGMA
  /// quick_check` reported page-level corruption. The recorded checksum is only
  /// a hash of the schema TEXT the build carries, not proof the tables were ever
  /// realized, so a stamped-but-tableless file passes checksum verification and
  /// would then fail every read/write with `no such table`. The open path routes
  /// this into the same quarantine-and-recreate recovery as a data-bearing file
  /// with no bookkeeping row (see ``shouldQuarantineAndRecreate(_:)``): the file
  /// is set aside and a fresh, fully-seeded database replaces it.
  public struct SchemaIncomplete: Error, Equatable, CustomStringConvertible {
    /// Load-bearing tables the probe found missing from `sqlite_master`. Empty
    /// when ``integrityFailure`` is what fired instead.
    public let missingTables: [String]
    /// The first `PRAGMA quick_check` failure line, or `nil` when a missing
    /// table (not an integrity scan) is what failed the probe.
    public let integrityFailure: String?

    public init(missingTables: [String], integrityFailure: String? = nil) {
      self.missingTables = missingTables
      self.integrityFailure = integrityFailure
    }

    public var description: String {
      if !missingTables.isEmpty {
        return "incomplete managed database (missing load-bearing tables: "
          + missingTables.joined(separator: ", ") + ")"
      }
      return "managed database failed quick_check (\(integrityFailure ?? "unknown"))"
    }
  }

  /// Open an on-disk store at `url`, applying `schemaSQL` and (when
  /// `schemaChecksum` is supplied) enforcing the shared `schema_migrations`
  /// bookkeeping contract, then running the versioned-migration ladder
  /// (`migrations`, versions 2+; the production caller loads it from the
  /// bundled copies of the canonical `schema/migrations/` directory).
  ///
  /// Bookkeeping (only when `schemaChecksum != nil`, i.e. the production path):
  /// a fresh database has the baseline applied and is stamped with
  /// `(version 1, name 'schema', checksum)`; an existing versioned database is
  /// verified against that checksum and then left to the numbered-migration
  /// ladder — the frozen baseline is NEVER replayed, so a post-launch
  /// destructive migration (DROP/RENAME) is not undone on the next open. A
  /// checksum mismatch, or a data-bearing database with no bookkeeping row to
  /// verify, raises ``SchemaMismatch``. With `schemaChecksum == nil` (tests /
  /// in-memory) the baseline is applied idempotently on every open with no
  /// verification.
  ///
  /// Resilience: if the file at `url` cannot be opened because it is not a
  /// database, is corrupt, or is a data-bearing file with no bookkeeping row to
  /// verify (``SchemaMismatch`` of kind ``SchemaMismatch/Kind/missingBookkeeping``),
  /// the file (and its `-wal`/`-shm` sidecars) is renamed to a timestamped
  /// `…​.incompatible-<stamp>.bak` and a fresh empty database is created in its
  /// place; the resulting store's ``recovery`` describes what happened. This
  /// never fires for transient/environmental failures (the file being locked,
  /// busy, unreadable for permission reasons, or the disk being full) — those
  /// re-throw so a momentary glitch can never discard good data. A database
  /// written by a NEWER build (``SchemaDowngrade``), a broken shipped migration
  /// (``SchemaMigrationFailed``), and a checksum mismatch on a readable database
  /// (``SchemaMismatch`` of kind ``SchemaMismatch/Kind/checksumMismatch``)
  /// likewise re-throw rather than quarantining: the data is healthy, the build
  /// is what's wrong.
  ///
  /// `managed` (production Lorvex-managed store only; `false` for in-memory,
  /// test, and dev-injected stores) additionally runs a post-`applySchema`
  /// completeness probe and an idempotent inbox-row ensure. The app layer passes
  /// `true` only for the resolved managed store. The probe verifies the LIVE
  /// structure — a matching text checksum does not prove the tables were
  /// realized — so a stamped-but-tableless (or quick_check-failing) file is
  /// routed into the same quarantine-and-recreate recovery as
  /// ``SchemaMismatch/Kind/missingBookkeeping`` (see ``SchemaIncomplete``). It
  /// can never fire on the healthy fresh-create path, which applies the full
  /// baseline and seeds before the probe runs.
  ///
  /// `onFaultQuarantine` governs the fault branch. When `true` (default), a
  /// quarantine-recoverable fault (see ``isQuarantineRecoverable(_:)``) sets the
  /// file aside and recreates it in-process. When `false`, that same fault is
  /// RE-THROWN unchanged instead of quarantined, so a caller that must serialize
  /// quarantine across processes can hold an exclusive lifecycle lock and drive
  /// recovery itself: the managed store opens with `false` under only a shared
  /// cutover lock (the healthy fast path never acquires an exclusive lock), and a
  /// surfaced fault is escalated by the caller to a re-open with
  /// `onFaultQuarantine: true` under an exclusive lock — where the re-open RE-
  /// CHECKS the file and quarantines only if it is STILL faulted, so a peer that
  /// already recreated a healthy file in the window is found healthy and never
  /// moved. A non-recoverable fault (checksum mismatch, downgrade, a
  /// transient/environmental error) re-throws regardless of this flag.
  public static func open(
    at url: URL, schemaSQL: String, schemaChecksum: String? = nil,
    migrations: [SchemaMigration] = [], managed: Bool = false,
    onFaultQuarantine: Bool = true
  ) throws
    -> LorvexStore
  {
    do {
      return try openOnce(
        at: url, schemaSQL: schemaSQL, schemaChecksum: schemaChecksum, migrations: migrations,
        managed: managed)
    } catch {
      guard onFaultQuarantine,
        shouldQuarantineAndRecreate(error),
        FileManager.default.fileExists(atPath: url.path)
      else { throw error }
      let reason = describe(error)
      let backupURL = try quarantineDatabaseFile(at: url)
      let store = try openOnce(
        at: url, schemaSQL: schemaSQL, schemaChecksum: schemaChecksum, migrations: migrations,
        managed: managed)
      store.recovery = DatabaseRecovery(backupURL: backupURL, reason: reason)
      return store
    }
  }

  /// Single open attempt: create the queue and apply the schema, with no
  /// recovery. The public `open` wraps this with quarantine-and-retry.
  ///
  /// When `managed` is true this also runs the managed-only post-open
  /// guarantees AFTER `applySchema`: the completeness probe (which throws the
  /// recoverable ``SchemaIncomplete`` the caller quarantines on) and the
  /// idempotent inbox-row ensure. Both are skipped for in-memory / test /
  /// dev-injected stores, which carry no managed self-heal contract.
  private static func openOnce(
    at url: URL, schemaSQL: String, schemaChecksum: String?, migrations: [SchemaMigration],
    managed: Bool
  ) throws
    -> LorvexStore
  {
    var config = Configuration()
    config.foreignKeysEnabled = true
    config.busyMode = .timeout(5)
    // Begin every `write {}` block with BEGIN IMMEDIATE rather than the GRDB
    // default DEFERRED. A deferred block reads first (taking a WAL snapshot)
    // then writes, so a commit by the MCP host in between returns
    // SQLITE_BUSY_SNAPSHOT immediately — the busy handler can't help a stale
    // snapshot. Acquiring the write lock up front lets the busy timeout absorb
    // the contention, the product's primary write pattern (app + assistant).
    config.defaultTransactionKind = .immediate
    let queue = try DatabaseQueue(path: url.path, configuration: config)
    try applySchema(queue, sql: schemaSQL, schemaChecksum: schemaChecksum, migrations: migrations)
    if managed {
      try verifyManagedCompleteness(queue)
      try ensureInboxListRow(queue)
    }
    // Seed planner statistics for this long-lived connection: mask 0x10002
    // makes `PRAGMA optimize` run ANALYZE on every table that has none yet, so
    // the partial/composite index fleet is costed from real row distributions
    // instead of compiled-in defaults. Subsequent refreshes ride the retention
    // sweep's plain `PRAGMA optimize` step. Best-effort: statistics improve
    // plans but are never required for correctness.
    try? queue.write { db in try db.execute(sql: "PRAGMA optimize=0x10002") }
    return LorvexStore(writer: queue)
  }

  /// Open an in-memory store. Primarily for tests; `:memory:` databases are not
  /// shared across connections. Bookkeeping/verification is skipped (no file to
  /// recover, no cross-process identity to assert).
  public static func openInMemory(
    schemaSQL: String, migrations: [SchemaMigration] = []
  ) throws -> LorvexStore {
    var config = Configuration()
    config.foreignKeysEnabled = true
    config.busyMode = .timeout(5)
    config.defaultTransactionKind = .immediate
    let queue = try DatabaseQueue(configuration: config)
    try applySchema(queue, sql: schemaSQL, schemaChecksum: nil, migrations: migrations)
    return LorvexStore(writer: queue)
  }

  /// Version + name of the single consolidated schema migration — the
  /// `(version 1, name "schema")` bookkeeping row.
  private static let schemaMigrationVersion = 1
  private static let schemaMigrationName = "schema"

  /// Apply the schema to a writer and reconcile the `schema_migrations`
  /// bookkeeping, then run the versioned-migration ladder (versions 2+, see
  /// ``SchemaMigrationRunner``). Internal to keep the open paths the only
  /// entry points; callers must not mutate the schema out of band.
  ///
  /// The baseline is applied only when authoring the schema: a fresh database
  /// (production or test) and any drift-reconciling replay on the checksum-less
  /// test/in-memory path. A production (`schemaChecksum != nil`) database that
  /// already carries the version-1 bookkeeping row is verified against the
  /// recorded checksum and then handed straight to the ladder — the frozen
  /// baseline is NOT replayed. Replaying it would re-run every `CREATE … IF NOT
  /// EXISTS` the baseline declares, resurrecting any object a post-launch
  /// destructive migration removed (and breaking the next open when the
  /// baseline still references a dropped column). The numbered ladder is the
  /// sole author of post-baseline schema change.
  ///
  /// Runs WITHOUT an enclosing transaction: `schema.sql` opens with
  /// `PRAGMA journal_mode = WAL`, which SQLite refuses to change inside a
  /// transaction (the failure was masked on in-memory databases, where WAL is
  /// silently ignored). `writeWithoutTransaction` lets the journal-mode pragma
  /// and the subsequent DDL each execute at autocommit, matching how a `.sql`
  /// dump is applied by the sqlite CLI; each version-2+ migration wraps its own
  /// `BEGIN IMMEDIATE`.
  private static func applySchema(
    _ writer: any DatabaseWriter, sql: String, schemaChecksum: String?,
    migrations: [SchemaMigration]
  ) throws {
    try writer.writeWithoutTransaction { db in
      try ensureSchemaMigrationsTable(db)
      // Refuse a database written by a newer build BEFORE touching its schema:
      // its data is healthy and must never be quarantined or partially
      // re-stamped by an older binary.
      try SchemaMigrationRunner.checkDowngrade(
        db, migrations: migrations, baselineVersion: schemaMigrationVersion)
      if let recorded = try recordedSchemaMigration(db) {
        if let expected = schemaChecksum {
          // Production: verify the recorded baseline checksum, then STOP —
          // never replay the baseline (that would undo a post-launch
          // destructive migration). The ladder below is the sole author of
          // any post-baseline schema change.
          if recorded.name != schemaMigrationName || recorded.checksum != expected {
            throw SchemaMismatch(
              kind: .checksumMismatch,
              recorded: "name=\(recorded.name); checksum=\(recorded.checksum)",
              expected: "name=\(schemaMigrationName); checksum=\(expected)")
          }
        } else {
          // Tests / in-memory: no checksum to verify against, so replay the
          // idempotent baseline DDL to reconcile any drift.
          try db.execute(sql: sql)
        }
      } else if try tableExists(db, "tasks") {
        // A data-bearing database with no bookkeeping row cannot be verified
        // against the current schema. In production (`schemaChecksum != nil`)
        // this is unverifiable, so the recovery path sets it aside; tests pass
        // no checksum and keep the lenient idempotent apply.
        if let expected = schemaChecksum {
          throw SchemaMismatch(
            kind: .missingBookkeeping, recorded: "(no schema_migrations row)", expected: expected)
        }
        try db.execute(sql: sql)
      } else {
        // Fresh database: apply the schema and stamp the bookkeeping row.
        try db.execute(sql: sql)
        if let expected = schemaChecksum {
          try stampSchemaMigration(db, checksum: expected)
        }
      }
      try SchemaMigrationRunner.run(db, migrations: migrations)
    }
  }

  /// Create the `schema_migrations` bookkeeping table if absent. The DDL
  /// matches the Apple migration-runner contract so every Apple app version can
  /// verify and advance one durable ladder.
  static func ensureSchemaMigrationsTable(_ db: Database) throws {
    try db.execute(
      sql: """
        CREATE TABLE IF NOT EXISTS schema_migrations (
            version  INTEGER PRIMARY KEY,
            name     TEXT NOT NULL,
            checksum TEXT NOT NULL,
            applied_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
        ) STRICT;
        """)
  }

  static func recordedSchemaChecksum(_ db: Database) throws -> String? {
    try recordedSchemaMigration(db)?.checksum
  }

  private struct RecordedSchemaMigration {
    let name: String
    let checksum: String
  }

  private static func recordedSchemaMigration(
    _ db: Database
  ) throws -> RecordedSchemaMigration? {
    try Row.fetchOne(
      db,
      sql: "SELECT name, checksum FROM schema_migrations WHERE version = ?",
      arguments: [schemaMigrationVersion]
    ).map {
      RecordedSchemaMigration(name: $0["name"], checksum: $0["checksum"])
    }
  }

  /// Stamp the `(version 1, name "schema", checksum)` bookkeeping row.
  ///
  /// `applySchema` runs at autocommit (the leading `PRAGMA journal_mode = WAL`
  /// can't run inside a transaction), so two processes opening a brand-new
  /// database can both observe no bookkeeping row and both reach here. The loser
  /// hits a primary-key `SQLITE_CONSTRAINT`. That is NOT corruption — treat it as
  /// a concurrent stamp: re-read the recorded checksum and accept it when it
  /// matches, so the open path doesn't quarantine a perfectly healthy database.
  /// A genuinely different recorded checksum is still surfaced as `SchemaMismatch`.
  static func stampSchemaMigration(_ db: Database, checksum: String) throws {
    do {
      try db.execute(
        sql: "INSERT INTO schema_migrations (version, name, checksum) VALUES (?, ?, ?)",
        arguments: [schemaMigrationVersion, schemaMigrationName, checksum])
    } catch let error as DatabaseError where error.resultCode == .SQLITE_CONSTRAINT {
      let recorded = try recordedSchemaChecksum(db)
      guard recorded == checksum else {
        throw SchemaMismatch(
          kind: .checksumMismatch, recorded: recorded ?? "(no schema_migrations row)",
          expected: checksum)
      }
    }
  }

  private static func tableExists(_ db: Database, _ table: String) throws -> Bool {
    try Bool.fetchOne(
      db,
      sql: "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?)",
      arguments: [table]
    ) ?? false
  }

  // MARK: - Managed-only post-open guarantees

  /// The load-bearing tables the managed completeness probe requires. Their
  /// absence means the file is structurally unusable even though it stamped a
  /// matching checksum, so every real read/write would fail with `no such
  /// table`. A deliberately small set — enough to prove the baseline was truly
  /// realized, not a full table inventory (the schema-freeze gate owns the
  /// exhaustive contract):
  /// - `lists` / `tasks`: the core task-management tables every workspace read
  ///   and `create_task` FK depends on.
  /// - `error_logs`: the diagnostics ring every failure path writes to; its loss
  ///   would silently swallow the very errors that diagnose the incomplete open.
  /// - `sync_checkpoints`: holds the device identity every write stamps and every
  ///   sync cycle reads.
  /// - `sync_cloudkit_account_binding` / authority witness / generation ledger /
  ///   traversal progress / witness / corruption fences: durable proof that
  ///   gates CloudKit outbound and terminal restore against restored,
  ///   generation-rolled-back, partially-traversed, or dropped remote state.
  /// - `preferences`: backs `default_list_id` and the app's persisted settings.
  private static let requiredLoadBearingTables = [
    "lists", "tasks", "error_logs", "sync_checkpoints",
    "sync_cloudkit_account_binding", "sync_cloudkit_authority_witness",
    "sync_cloudkit_generation_descriptor",
    "sync_cloudkit_traversal_progress",
    "sync_cloudkit_traversal_witness", "sync_cloudkit_incremental_cursor",
    "sync_cloudkit_corrupt_record_fences", "preferences",
  ]

  /// Managed-open completeness probe: assert the load-bearing tables are present
  /// and the file passes `PRAGMA quick_check`. A matching schema checksum only
  /// proves the DDL TEXT the build carries hashes as expected — NOT that the
  /// tables were ever realized — so a stamped-but-tableless file otherwise
  /// reaches normal operation and fails every write. Throws ``SchemaIncomplete``
  /// (which the open path quarantines on) rather than returning a bool, so the
  /// caller routes it straight into recovery.
  ///
  /// `quick_check` is the page-structure integrity scan (far cheaper than the
  /// full `integrity_check`; it skips per-index and FTS content re-validation),
  /// bounded to a single reported failure. It runs on every managed open, so its
  /// cost scales with the database; on a corruption hit it self-heals through the
  /// same quarantine-and-recreate path a `SQLITE_CORRUPT` open-throw already uses.
  static func verifyManagedCompleteness(_ writer: any DatabaseWriter) throws {
    try writer.read { db in
      var missing: [String] = []
      for table in requiredLoadBearingTables where try !tableExists(db, table) {
        missing.append(table)
      }
      guard missing.isEmpty else {
        throw SchemaIncomplete(missingTables: missing)
      }
      let result = try String.fetchOne(db, sql: "PRAGMA quick_check(1)")
      if let result, result != "ok" {
        throw SchemaIncomplete(missingTables: [], integrityFailure: result)
      }
    }
  }

  /// Idempotently ensure the canonical `inbox` list row exists, mirroring the
  /// `schema/schema.sql` baseline seed byte-for-byte (fixed id `inbox`, the
  /// `0000…` sentinel HLC version that keeps a resurrected row strictly older
  /// than any real edit). The baseline — and its seed — is applied only once at
  /// first create and never replayed, so without this a missing `inbox` row
  /// (e.g. after a sync-driven delete) would make implicit `create_task`
  /// (`list_id = 'inbox'`) hit the `lists` `ON DELETE RESTRICT` FK. Run on every
  /// managed open; `INSERT OR IGNORE` no-ops when the row is present, including
  /// on a fresh recreate that already seeded it. `inbox` matches ``inboxListId``.
  static func ensureInboxListRow(_ writer: any DatabaseWriter) throws {
    try writer.write { db in
      try db.execute(
        sql: """
          INSERT OR IGNORE INTO lists (id, name, icon, version, created_at, updated_at)
          VALUES ('inbox', 'Inbox', '📥', '0000000000000_0000_0000000000000000',
                  '1970-01-01T00:00:00.000Z', '1970-01-01T00:00:00.000Z')
          """)
    }
  }

  // MARK: - Recovery from an unreadable / incompatible database

  /// Whether an error thrown by ``open(at:schemaSQL:schemaChecksum:migrations:managed:onFaultQuarantine:)``
  /// is one the quarantine-and-recreate recovery resolves (a corrupt / not-a-
  /// database / structurally-incompatible file, a data-bearing file with no
  /// bookkeeping row, or a ``SchemaIncomplete`` completeness-probe failure) as
  /// opposed to one that must fail closed (a checksum mismatch, a newer-build
  /// downgrade, a broken shipped migration, or a transient/environmental error).
  ///
  /// A caller opening with `onFaultQuarantine: false` calls this on the surfaced
  /// error to decide whether to escalate to an exclusive-locked re-check +
  /// quarantine, or re-throw the fault untouched. It classifies the error alone;
  /// the file-still-present check the in-process quarantine additionally makes
  /// stays inside `open`.
  public static func isQuarantineRecoverable(_ error: Error) -> Bool {
    shouldQuarantineAndRecreate(error)
  }

  /// Whether `open` should set the existing file aside and start fresh: either
  /// a genuinely-unreadable database (corruption / not-a-database / structural
  /// conflict) or a data-bearing file with no bookkeeping row to verify
  /// (``SchemaMismatch`` of kind ``SchemaMismatch/Kind/missingBookkeeping``).
  ///
  /// A ``SchemaIncomplete`` (the managed completeness probe found a stamped file
  /// missing load-bearing tables, or failing `quick_check`) returns `true`: it is
  /// structurally unusable, so it is set aside and recreated exactly like the
  /// missing-bookkeeping case.
  ///
  /// A checksum-mismatch ``SchemaMismatch`` (``SchemaMismatch/Kind/checksumMismatch``)
  /// returns `false`: a readable database whose recorded checksum disagrees with
  /// the build almost always means a broken/tampered binary, not corrupt user
  /// data, so it FAILS CLOSED (re-throws untouched) like ``SchemaDowngrade`` and
  /// ``SchemaMigrationFailed``. Transient and environmental failures also return
  /// `false` so they re-throw untouched.
  private static func shouldQuarantineAndRecreate(_ error: Error) -> Bool {
    if error is SchemaIncomplete { return true }
    if let mismatch = error as? SchemaMismatch {
      return mismatch.kind == .missingBookkeeping
    }
    return isUnrecoverableDatabaseError(error)
  }

  /// Whether `error` means the file is genuinely not a usable Lorvex database
  /// (corrupt, not a database, or structurally incompatible with the schema)
  /// — as opposed to a transient/environmental condition where the data is
  /// fine and retrying later would succeed.
  ///
  /// Recoverable (→ quarantine + start fresh): `SQLITE_NOTADB`, `SQLITE_CORRUPT`,
  /// `SQLITE_FORMAT`, and the `SQLITE_ERROR`/`SQLITE_CONSTRAINT`/`SQLITE_MISMATCH`
  /// raised while applying the schema to an incompatible existing structure.
  ///
  /// NOT recoverable (→ re-throw, never touch the file): `SQLITE_BUSY`,
  /// `SQLITE_LOCKED`, `SQLITE_CANTOPEN`, `SQLITE_IOERR`, `SQLITE_PERM`,
  /// `SQLITE_AUTH`, `SQLITE_READONLY`, `SQLITE_FULL`, `SQLITE_NOMEM`.
  static func isUnrecoverableDatabaseError(_ error: Error) -> Bool {
    guard let dbError = error as? DatabaseError else { return false }
    switch dbError.resultCode.primaryResultCode {
    case .SQLITE_NOTADB, .SQLITE_CORRUPT, .SQLITE_FORMAT,
      .SQLITE_ERROR, .SQLITE_CONSTRAINT, .SQLITE_MISMATCH, .SQLITE_SCHEMA:
      return true
    default:
      return false
    }
  }

  private static func describe(_ error: Error) -> String {
    if let incomplete = error as? SchemaIncomplete {
      return incomplete.description
    }
    if let mismatch = error as? SchemaMismatch {
      return "schema mismatch (recorded \(mismatch.recorded), expected \(mismatch.expected))"
    }
    if let dbError = error as? DatabaseError {
      let code = dbError.resultCode.primaryResultCode
      if let message = dbError.message {
        return "\(code): \(message)"
      }
      return "\(code)"
    }
    return String(describing: error)
  }

  /// Rename the database file (and its `-wal`/`-shm` sidecars) to a timestamped
  /// `…​.incompatible-<stamp>.bak` alongside the original, and return the backup
  /// URL of the main file. The data is preserved, never deleted.
  private static func quarantineDatabaseFile(at url: URL) throws -> URL {
    let fm = FileManager.default
    let backupURL = uniqueQuarantineURL(for: url, fm: fm)

    // Move the main file first; mirror the same suffix onto the sidecars so a
    // later restore keeps the WAL set together.
    try moveIfExists(at: url, to: backupURL, fm: fm)
    for sidecar in ["-wal", "-shm"] {
      let from = URL(fileURLWithPath: url.path + sidecar)
      let to = URL(fileURLWithPath: backupURL.path + sidecar)
      try moveIfExists(at: from, to: to, fm: fm)
    }
    return backupURL
  }

  /// A `…​.incompatible-<stamp>.bak` URL (with its `-wal`/`-shm` sidecar slots)
  /// that does not yet exist. The stamp carries millisecond resolution, and if a
  /// backup with the same stamp is already present — two quarantines racing
  /// within one tick, or a re-quarantine — a `-N` uniquifier is appended so an
  /// earlier set-aside database is never overwritten (the point of quarantine is
  /// that the data stays recoverable).
  private static func uniqueQuarantineURL(for url: URL, fm: FileManager) -> URL {
    let stamp = recoveryTimestamp()
    func isFree(_ candidate: URL) -> Bool {
      !fm.fileExists(atPath: candidate.path)
        && !fm.fileExists(atPath: candidate.path + "-wal")
        && !fm.fileExists(atPath: candidate.path + "-shm")
    }
    let base = url.appendingPathExtension("incompatible-\(stamp).bak")
    if isFree(base) { return base }
    var counter = 2
    while true {
      let candidate = url.appendingPathExtension("incompatible-\(stamp)-\(counter).bak")
      if isFree(candidate) { return candidate }
      counter += 1
    }
  }

  private static func moveIfExists(at from: URL, to: URL, fm: FileManager) throws {
    guard fm.fileExists(atPath: from.path) else { return }
    if fm.fileExists(atPath: to.path) {
      try fm.removeItem(at: to)
    }
    try fm.moveItem(at: from, to: to)
  }

  /// Filesystem-safe `yyyyMMdd-HHmmss-SSS` (millisecond-resolution) stamp for
  /// quarantine filenames, so two quarantines in the same UTC second do not
  /// collide on the same `.bak` name.
  private static func recoveryTimestamp() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
    return formatter.string(from: Date())
  }
}

/// Convenience: dump the realized sqlite_master rows in a stable order for
/// realized-schema drift comparisons across Apple processes / runs.
///
/// Excludes `sqlite_*` internal objects. The result is suitable for hashing
/// (`SHA-256`) and comparing against the authoritative `schema/schema.sql` to
/// detect drift in the realized SQLite schema.
public enum SchemaIntrospection {
  /// One sqlite_master entry — kept stable-ordered + selective-fielded for
  /// hashable parity.
  public struct Entry: Sendable, Hashable {
    public let type: String  // "table", "index", "trigger", "view"
    public let name: String
    public let tblName: String
    public let sql: String?
  }

  /// Returns sqlite_master entries excluding internal `sqlite_*` rows, sorted
  /// by `(type, name)` so the order is reproducible.
  public static func dump(_ store: LorvexStore) throws -> [Entry] {
    try store.writer.read { db in
      let rows = try Row.fetchAll(
        db,
        sql: """
        SELECT type, name, tbl_name, sql
        FROM sqlite_master
        WHERE name NOT LIKE 'sqlite_%'
        ORDER BY type, name
        """)
      return rows.map { row in
        Entry(
          type: row["type"] as String,
          name: row["name"] as String,
          tblName: row["tbl_name"] as String,
          sql: row["sql"] as String?)
      }
    }
  }
}

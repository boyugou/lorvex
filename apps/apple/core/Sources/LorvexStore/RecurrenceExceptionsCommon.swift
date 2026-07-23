import Foundation
import GRDB
import LorvexDomain

/// Recurrence-exception (EXDATE) validation and mutation engine for tasks.
///
/// The validation pipeline routes the proposed exception date through
/// ``CalendarRecurrence/recursOnDate(recurrenceJson:baseDateYmd:targetDateYmd:)``
/// so weekday/month-day alignment and UNTIL/COUNT termination are all honored.
public enum RecurrenceExceptionsCommon {

  /// `selectAnchorSQL` loads `(recurrence, exceptions_json, anchor)` for one
  /// id (bind `?1 = id`); the exceptions blob is rebuilt from the per-entity
  /// child table by a correlated `json_group_array` subquery so the
  /// validation pipeline reads the same JSON wire form regardless of the
  /// normalized storage. `bumpVersionSQL` is the LWW-gated UPDATE touching
  /// only `version`/`updated_at` (binds `?1 = version`, `?2 = now`,
  /// `?3 = id`).
  public struct ExceptionTableConfig: Sendable {
    public let entity: String
    public let entityNoun: String
    public let anchorLabel: String
    public let selectAnchorSQL: String
    public let bumpVersionSQL: String

    public init(
      entity: String, entityNoun: String, anchorLabel: String,
      selectAnchorSQL: String, bumpVersionSQL: String
    ) {
      self.entity = entity
      self.entityNoun = entityNoun
      self.anchorLabel = anchorLabel
      self.selectAnchorSQL = selectAnchorSQL
      self.bumpVersionSQL = bumpVersionSQL
    }
  }

  /// Row data loaded from the owning table for exception validation.
  private struct AnchorRow {
    let recurrence: String?
    let recurrenceExceptions: String?
    let anchor: String?
  }

  private static func loadAnchorRow(
    _ db: Database, _ cfg: ExceptionTableConfig, id: String
  ) throws -> AnchorRow {
    guard let row = try Row.fetchOne(db, sql: cfg.selectAnchorSQL, arguments: [id]) else {
      throw StoreError.notFound(entity: cfg.entity, id: id)
    }
    return AnchorRow(
      recurrence: row[0],
      recurrenceExceptions: row[1],
      anchor: row[2])
  }

  /// Run the LWW-gated UPDATE bumping `version`/`updated_at` on the parent
  /// row, then rewrite the per-entity exception child table with `newDates`.
  private static func executeExceptionsUpdate(
    _ db: Database, _ cfg: ExceptionTableConfig, id: String,
    newDates: [String], version: String, now: String
  ) throws {
    try RecurrenceExceptionsRepo.validateLocalExceptionCount(newDates.count)
    try db.execute(
      sql: cfg.bumpVersionSQL,
      arguments: ["version": version, "now": now, "id": id])
    if db.changesCount == 0 {
      throw StoreError.staleVersion(entity: cfg.entity, id: id)
    }
    try RecurrenceExceptionsRepo.replaceTaskExceptions(db, taskId: id, dates: newDates)
  }

  /// Parse a `YYYY-MM-DD` storage date; map any failure onto
  /// `StoreError.validation` with the canonical "invalid date format" wording.
  private static func parseStorageDate(_ date: String) throws {
    if IsoDate.parse(date) == nil {
      throw StoreError.validation("invalid date format: \(date)")
    }
  }

  private static func validateExceptionDate(
    _ cfg: ExceptionTableConfig, _ row: AnchorRow, id: String, date: String
  ) throws {
    try parseStorageDate(date)

    guard let recurrenceJson = row.recurrence else {
      throw StoreError.validation("\(cfg.entityNoun) \(id) is not recurring")
    }
    guard let anchor = row.anchor else {
      throw StoreError.validation("\(cfg.entityNoun) \(id) is not recurring")
    }
    try parseStorageDate(anchor)

    if date < anchor {
      throw StoreError.validation("exception date \(date) is before \(cfg.anchorLabel)")
    }

    let recurs: Bool
    do {
      recurs = try CalendarRecurrence.recursOnDate(
        recurrenceJson: recurrenceJson, baseDateYmd: anchor, targetDateYmd: date)
    } catch let e as StoreError {
      throw StoreError.validation("invalid recurrence rule: \(storeErrorMessage(e))")
    }
    if !recurs {
      throw StoreError.validation(
        "date \(date) is not a valid occurrence of the recurrence pattern")
    }
  }

  /// Add an exception. Wraps the SELECT → mutate → UPDATE sequence in an
  /// immediate transaction when the connection is in autocommit.
  public static func addException(
    _ writer: any DatabaseWriter, _ cfg: ExceptionTableConfig,
    id: String, exceptionDate: String, version: String, now: String
  ) throws -> String {
    try StoreTransactions.withImmediateTransaction(writer) { db in
      try addExceptionInner(db, cfg, id: id, exceptionDate: exceptionDate, version: version, now: now)
    }
  }

  public static func addExceptionInner(
    _ db: Database, _ cfg: ExceptionTableConfig,
    id: String, exceptionDate: String, version: String, now: String
  ) throws -> String {
    if version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      throw StoreError.validation("version must not be empty")
    }
    let row = try loadAnchorRow(db, cfg, id: id)
    try validateExceptionDate(cfg, row, id: id, date: exceptionDate)

    var exceptions = try RecurrenceExceptionsRepo.parseExceptionDates(row.recurrenceExceptions)
    if exceptions.contains(exceptionDate) {
      throw StoreError.validation("Exception already exists for date \(exceptionDate)")
    }
    exceptions.append(exceptionDate)
    exceptions.sort()

    let json = try RecurrenceExceptionsRepo.encodeDates(exceptions)
    try executeExceptionsUpdate(
      db, cfg, id: id, newDates: exceptions, version: version, now: now)
    return json
  }

  /// Remove an exception. Returns the updated JSON array, or `nil` once the
  /// list is empty.
  public static func removeException(
    _ writer: any DatabaseWriter, _ cfg: ExceptionTableConfig,
    id: String, exceptionDate: String, version: String, now: String
  ) throws -> String? {
    try StoreTransactions.withImmediateTransaction(writer) { db in
      try removeExceptionInner(
        db, cfg, id: id, exceptionDate: exceptionDate, version: version, now: now)
    }
  }

  public static func removeExceptionInner(
    _ db: Database, _ cfg: ExceptionTableConfig,
    id: String, exceptionDate: String, version: String, now: String
  ) throws -> String? {
    if version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      throw StoreError.validation("version must not be empty")
    }
    try parseStorageDate(exceptionDate)

    let row = try loadAnchorRow(db, cfg, id: id)
    var exceptions = try RecurrenceExceptionsRepo.parseExceptionDates(row.recurrenceExceptions)

    let beforeLen = exceptions.count
    exceptions.removeAll { $0 == exceptionDate }
    if exceptions.count == beforeLen {
      throw StoreError.validation("Date \(exceptionDate) is not in the exceptions list")
    }

    let jsonVal: String? = try exceptions.isEmpty ? nil : RecurrenceExceptionsRepo.encodeDates(exceptions)
    try executeExceptionsUpdate(
      db, cfg, id: id, newDates: exceptions, version: version, now: now)
    return jsonVal
  }

  // -- helpers ------------------------------------------------------------

  private static func storeErrorMessage(_ e: StoreError) -> String {
    switch e {
    case let .validation(m): return m
    case let .serialization(m): return m
    case let .invariant(m): return m
    case let .notFound(entity, id): return "\(entity) \(id) not found"
    case let .staleVersion(entity, id): return "stale version for \(entity) \(id)"
    case let .versionSuperseded(entity, id, attempted, existing):
      return "superseded version for \(entity) \(id): attempted \(attempted), existing \(existing)"
    }
  }
}

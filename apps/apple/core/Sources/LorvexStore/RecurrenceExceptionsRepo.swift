import Foundation
import GRDB
import LorvexDomain

/// Recurrence-exception (EXDATE) storage helpers for recurring tasks.
///
/// EXDATE membership is normalized into per-date rows in
/// `task_recurrence_exceptions`, keyed by `(task_id, exception_date)`. The sync envelope wire form
/// remains a JSON array of `YYYY-MM-DD` strings: parsers accept it and
/// load helpers re-emit it.
///
/// `None` / blank / empty array all clear the registry. Empty registries
/// are represented as `nil` JSON (sync envelopes treat missing-array and
/// empty-array equivalently).
public enum RecurrenceExceptionsRepo {

  /// Parse a JSON array of date strings (`["2026-04-01","2026-04-08"]`)
  /// into a `[String]`. `nil` and blank input both return the empty array.
  /// Invalid JSON surfaces as ``StoreError/validation(_:)``.
  public static func parseExceptionDates(_ raw: String?) throws -> [String] {
    guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return []
    }
    guard let data = raw.data(using: .utf8) else {
      throw StoreError.validation("invalid recurrence_exceptions JSON: not UTF-8")
    }
    do {
      let parsed = try JSONSerialization.jsonObject(with: data, options: [])
      guard let arr = parsed as? [Any] else {
        throw StoreError.validation("invalid recurrence_exceptions JSON: expected array")
      }
      var out: [String] = []
      out.reserveCapacity(arr.count)
      for v in arr {
        guard let s = v as? String else {
          throw StoreError.validation("invalid recurrence_exceptions JSON: array entries must be strings")
        }
        out.append(s)
      }
      return out
    } catch let e as StoreError {
      throw e
    } catch {
      throw StoreError.validation("invalid recurrence_exceptions JSON: \(error.localizedDescription)")
    }
  }

  /// ``parseExceptionDates(_:)`` collected into a `Set<String>` at the
  /// allocation boundary, for callers that only need membership testing.
  public static func parseExceptionDatesAsSet(_ raw: String?) throws -> Set<String> {
    Set(try parseExceptionDates(raw))
  }

  /// Read every EXDATE registered against `task_id`, ascending date order
  /// (matches the canonical sort the JSON blob carries).
  public static func loadTaskExceptionDates(_ db: Database, taskId: String) throws -> [String] {
    try String.fetchAll(
      db,
      sql: """
        SELECT exception_date FROM task_recurrence_exceptions \
        WHERE task_id = ? ORDER BY exception_date ASC
        """,
      arguments: [taskId])
  }

  /// Build the JSON wire form (`["2026-04-01","2026-04-08"]`) of the task's
  /// EXDATE registry. Returns `nil` when the registry is empty so the sync
  /// envelope stays equality-roundtrip-stable.
  public static func loadTaskExceptionsJSON(_ db: Database, taskId: String) throws -> String? {
    let dates = try loadTaskExceptionDates(db, taskId: taskId)
    return dates.isEmpty ? nil : try encodeDates(dates)
  }

  /// Reject a locally-authored EXDATE registry above
  /// ``PayloadByteBudget/maxRecurrenceExceptions`` dates. Called by the LOCAL
  /// growth paths (the add-exception mutation and the bulk recurrence set) but
  /// deliberately not by ``replaceTaskExceptions(_:taskId:dates:)`` itself: the
  /// sync applier replaces registries through that shared choke point, and a
  /// peer's payload — bounded as a whole by the wire byte cap — must never
  /// wedge an inbound page on a local policy cap.
  public static func validateLocalExceptionCount(_ count: Int) throws {
    guard count <= PayloadByteBudget.maxRecurrenceExceptions else {
      throw StoreError.validation(
        "a recurring task holds at most \(PayloadByteBudget.maxRecurrenceExceptions) "
          + "recurrence exceptions (got \(count))")
    }
  }

  /// Replace the task's full EXDATE registry with `dates`. DELETE-then-
  /// INSERT in one transaction step; `INSERT OR IGNORE` collapses
  /// duplicate dates against the composite PK.
  public static func replaceTaskExceptions(
    _ db: Database, taskId: String, dates: [String]
  ) throws {
    try validateStorageDates(dates)
    try db.execute(
      sql: "DELETE FROM task_recurrence_exceptions WHERE task_id = ?",
      arguments: [taskId])
    for date in dates {
      try db.execute(
        sql: """
          INSERT OR IGNORE INTO task_recurrence_exceptions (task_id, exception_date) \
          VALUES (?, ?)
          """,
        arguments: [taskId, date])
    }
  }

  /// Replace the task's EXDATE registry from a wire-form JSON array.
  /// `nil` / blank JSON clears the registry.
  public static func replaceTaskExceptionsFromJSON(
    _ db: Database, taskId: String, json: String?
  ) throws {
    let dates = try parseExceptionDates(json)
    try replaceTaskExceptions(db, taskId: taskId, dates: dates)
  }

  // -- helpers ------------------------------------------------------------

  /// Reject any value that is not the canonical byte-exact `YYYY-MM-DD` storage
  /// form before it reaches the exception child table. This is the storage choke
  /// point every EXDATE write funnels through, so enforcing it here keeps every
  /// stored date — and therefore the unescaped JSON wire form built by
  /// ``encodeDates(_:)`` — JSON-safe by construction, without a table-rebuilding
  /// SQLite CHECK constraint.
  private static func validateStorageDates(_ dates: [String]) throws {
    for d in dates where IsoDate.parse(d) == nil {
      throw StoreError.validation("invalid date format: \(d)")
    }
  }

  /// The single module-internal encoder for the EXDATE JSON wire form: a compact
  /// JSON array with no whitespace separators (`["a","b"]`) for the date-string
  /// array shape. This byte shape is a synced cross-app contract; keep it
  /// stable. Every load and exception-mutation path routes through here.
  static func encodeDates(_ dates: [String]) throws -> String {
    var s = "["
    for (i, d) in dates.enumerated() {
      // Kept as a raw concat so the compact byte shape stays stable (the EXDATE
      // JSON is a synced cross-app contract, so a general JSON encoder's
      // formatting could diverge). The storage choke points already constrain
      // dates to YYYY-MM-DD; this guard is the last line of defense so a stray
      // quote / backslash / control character can't forge malformed JSON through
      // this unescaped concat.
      guard
        !d.unicodeScalars.contains(where: { $0 == "\"" || $0 == "\\" || $0.value < 0x20 })
      else {
        throw StoreError.validation(
          "recurrence exception date contains JSON-unsafe characters: \(d)")
      }
      if i > 0 { s += "," }
      s += "\""
      s += d
      s += "\""
    }
    s += "]"
    return s
  }
}

import Foundation
import GRDB
import LorvexRuntime
import LorvexStore

/// Turns a raw thrown error into a category the alert layer can present without
/// leaking internal detail, and preserves the original technical detail so a
/// host can log it to `error_logs`.
///
/// The problem it solves: `LorvexCoreError.unsupportedOperation` is a catch-all
/// carrying three distinct flavors of message — user-appropriate *validation*
/// ("Mood must be between 1 and 5."), *not-found* text that interpolates a raw
/// UUIDv7 entity id ("Habit 'a1b2…' not found."), and internal *invariant*
/// post-conditions ("Habit 'a1b2…' missing after insert."). A raw GRDB
/// ``DatabaseError`` (embedded SQL / file paths) can travel the same alert path.
/// None of the raw id / SQL / invariant strings should ever reach a human alert.
///
/// This maps any error to one of four categories:
///
/// - ``Category/validation`` — the bound message is already a clean, human
///   sentence with no raw identifier or internal marker; the host shows it.
/// - ``Category/notFound`` — an entity lookup missed; the host shows a generic
///   localized "no longer exists" line instead of the id-bearing text.
/// - ``Category/generic`` — a TRANSIENT storage failure (a locked / busy
///   database), internal invariant, or opaque error; the host shows a generic
///   localized "try again" line, because retrying may succeed.
/// - ``Category/unrecoverable`` — a PERMANENTLY-fatal storage failure (a schema
///   mismatch / downgrade / failed migration, an unresolvable managed location,
///   or a fatal SQLite result code such as `SQLITE_FULL` / `SQLITE_CORRUPT`).
///   Retrying will not help, so the host shows distinct non-retry copy — and,
///   for a database written by a newer build, an "update Lorvex" line.
///
/// Classification runs on the core's error messages, which are authored in
/// English at the throw sites, so the marker checks are matched against a known
/// source language rather than localized copy. The mapping is deliberately
/// conservative: anything it cannot vouch for as a clean validation sentence is
/// treated as ``Category/generic`` so no raw internal string can slip through.
///
/// This layer is human-alert-only. The MCP tool-result envelope reads the
/// specific `errorDescription` directly and is unaffected.
public enum UserFacingError {
  /// The four presentation buckets an alert surface distinguishes. `notFound`,
  /// `generic`, and `unrecoverable` are shown as host-supplied localized copy;
  /// `validation` shows the bound message verbatim.
  public enum Category: Sendable, Equatable {
    case validation
    case notFound
    /// A transient / retryable failure — the "please try again" copy.
    case generic
    /// A permanently-fatal storage failure. The associated ``Fatal`` selects
    /// which non-retry copy the host shows.
    case unrecoverable(Fatal)
  }

  /// Which fatal-storage copy an ``Category/unrecoverable`` classification maps
  /// to. Never carries the raw error detail — that stays in
  /// ``Classification/technicalDetail`` for the diagnostics ring.
  public enum Fatal: Sendable, Equatable {
    /// A generic fatal storage failure (a schema mismatch / failed migration, an
    /// unresolvable managed location, or a fatal SQLite code — out of space,
    /// I/O error, can't-open, not-a-database, corrupt, or read-only).
    case storageUnavailable
    /// The database was written by a NEWER build of Lorvex; the fix is to update
    /// the app, so this maps to the "update Lorvex" copy.
    case databaseNewer
  }

  /// The result of classifying an error: the presentation category, the clean
  /// message to display for ``Category/validation`` (`nil` otherwise, since the
  /// host substitutes localized copy), and the raw technical detail to route to
  /// `error_logs` (never shown to the user).
  public struct Classification: Sendable, Equatable {
    public let category: Category
    /// The user-appropriate sentence to display for ``Category/validation``;
    /// `nil` for ``Category/notFound`` / ``Category/generic``, whose copy the
    /// host supplies localized.
    public let displayMessage: String?
    /// The original message / description (may contain a raw UUID, SQL, or an
    /// internal invariant) for the diagnostics ring. Never presented.
    public let technicalDetail: String

    public init(category: Category, displayMessage: String?, technicalDetail: String) {
      self.category = category
      self.displayMessage = displayMessage
      self.technicalDetail = technicalDetail
    }
  }

  /// Localized copy for the host-supplied categories, injected by each host from
  /// its own string catalog (the `fallbackBody` / notification-title pattern —
  /// core stays platform-neutral and never localizes).
  public struct Copy: Sendable {
    /// Shown for ``Category/notFound`` (e.g. "That item no longer exists.").
    public let itemNoLongerExists: String
    /// Shown for ``Category/generic`` (e.g. "Something went wrong. Please try again.").
    public let somethingWentWrong: String
    /// Shown for ``Category/unrecoverable`` with ``Fatal/storageUnavailable``
    /// (e.g. "Lorvex can't access its data storage, so this couldn't be
    /// completed. Please restart Lorvex.").
    public let storageUnavailable: String
    /// Shown for ``Category/unrecoverable`` with ``Fatal/databaseNewer`` (e.g.
    /// "This database was created by a newer version of Lorvex. Please update
    /// Lorvex to open it.").
    public let databaseNewer: String

    public init(
      itemNoLongerExists: String, somethingWentWrong: String,
      storageUnavailable: String, databaseNewer: String
    ) {
      self.itemNoLongerExists = itemNoLongerExists
      self.somethingWentWrong = somethingWentWrong
      self.storageUnavailable = storageUnavailable
      self.databaseNewer = databaseNewer
    }
  }

  /// Classify `error` into a presentation category plus the raw detail to log.
  public static func classify(_ error: Error) -> Classification {
    // Permanently-fatal storage failures escalate to `unrecoverable` with
    // non-retry copy, BEFORE the transient-DatabaseError branch below (fatal
    // SQLite codes are `DatabaseError`s too). `displayMessage` stays nil so only
    // host-supplied localized copy shows; the raw detail routes to `error_logs`.
    if let fatal = fatalStorageClassification(error) {
      return fatal
    }

    // A GRDB failure carries SQL text and, in the "database is locked" case, an
    // on-disk file path. A non-fatal code (locked / busy / and any other code
    // not enumerated as fatal) is transient: generic "try again", regardless of
    // wording.
    if let dbError = error as? DatabaseError {
      return Classification(
        category: .generic, displayMessage: nil, technicalDetail: String(describing: dbError))
    }

    if let coreError = error as? LorvexCoreError {
      switch coreError {
      case .taskNotFound:
        return Classification(
          category: .notFound, displayMessage: nil,
          technicalDetail: coreError.errorDescription ?? "taskNotFound")
      case .notFound:
        // A typed lookup miss: present the generic "no longer exists" copy while
        // keeping the id-bearing description (`errorDescription`) for diagnostics.
        // Matches the classification the string path produces for the equivalent
        // "<Noun> '<uuid>' not found." message.
        return Classification(
          category: .notFound, displayMessage: nil,
          technicalDetail: coreError.errorDescription ?? "notFound")
      case .emptyTitle:
        let message = coreError.errorDescription ?? "A task title is required."
        return Classification(
          category: .validation, displayMessage: message, technicalDetail: message)
      case .validation(_, let message):
        // A typed validation failure carries a clean, user-appropriate sentence;
        // show it verbatim, as the string path does for a marker-free message.
        return Classification(
          category: .validation, displayMessage: message, technicalDetail: message)
      case .conflict(let message):
        // A uniqueness collision carries a clean, user-appropriate sentence (the
        // colliding name + recommended action, no raw id); show it verbatim, the
        // same presentation the string path gives its marker-free message.
        return Classification(
          category: .validation, displayMessage: message, technicalDetail: message)
      case .unsupportedOperation(let message):
        return classifyMessage(message)
      case .malformedCoreData:
        // An internal core→app decode-contract break: not user-actionable, so
        // show the generic surface while logging the exact field path/reason.
        return Classification(
          category: .generic, displayMessage: nil,
          technicalDetail: coreError.errorDescription ?? "malformedCoreData")
      }
    }

    // Any other `LocalizedError` with wording: inspect it — a clean sentence
    // (e.g. an EventKit permission message) passes through, while anything
    // carrying a raw id / SQL / invariant is genericized.
    if let localized = error as? LocalizedError, let description = localized.errorDescription {
      return classifyMessage(description)
    }

    // An opaque error whose `String(describing:)` we cannot vouch for.
    return Classification(
      category: .generic, displayMessage: nil, technicalDetail: String(describing: error))
  }

  /// Resolve a classification to the string an alert should present, using
  /// host-supplied localized `copy` for every category except `validation`.
  public static func message(for classification: Classification, copy: Copy) -> String {
    switch classification.category {
    case .validation:
      return classification.displayMessage ?? copy.somethingWentWrong
    case .notFound:
      return copy.itemNoLongerExists
    case .generic:
      return copy.somethingWentWrong
    case .unrecoverable(let fatal):
      switch fatal {
      case .storageUnavailable:
        return copy.storageUnavailable
      case .databaseNewer:
        return copy.databaseNewer
      }
    }
  }

  // MARK: - Fatal-storage classification

  /// Classify the permanently-unrecoverable storage failures, or `nil` when
  /// `error` is not one. These originate in the store's open path (a schema
  /// mismatch / downgrade / failed migration, an unresolvable managed location)
  /// or are a `DatabaseError` carrying a fatal SQLite result code; each escalates
  /// to ``Category/unrecoverable`` with non-retry copy. The raw detail is kept in
  /// `technicalDetail` for `error_logs` and never shown.
  static func fatalStorageClassification(_ error: Error) -> Classification? {
    // A database written by a NEWER Lorvex: the one actionable fix is to update.
    if let downgrade = error as? LorvexStore.SchemaDowngrade {
      return Classification(
        category: .unrecoverable(.databaseNewer), displayMessage: nil,
        technicalDetail: String(describing: downgrade))
    }
    // A schema mismatch / structural incompleteness / failed shipped migration:
    // the build or on-disk structure is wrong, not transiently busy.
    if let mismatch = error as? LorvexStore.SchemaMismatch {
      return Classification(
        category: .unrecoverable(.storageUnavailable), displayMessage: nil,
        technicalDetail: String(describing: mismatch))
    }
    if let incomplete = error as? LorvexStore.SchemaIncomplete {
      return Classification(
        category: .unrecoverable(.storageUnavailable), displayMessage: nil,
        technicalDetail: incomplete.description)
    }
    if let migrationFailed = error as? LorvexStore.SchemaMigrationFailed {
      return Classification(
        category: .unrecoverable(.storageUnavailable), displayMessage: nil,
        technicalDetail: String(describing: migrationFailed))
    }
    // No safe managed-storage location (e.g. the App Group container is
    // unavailable on a sandboxed build): opening cannot proceed.
    if let location = error as? DbLocationError {
      return Classification(
        category: .unrecoverable(.storageUnavailable), displayMessage: nil,
        technicalDetail: location.description)
    }
    // A fatal SQLite result code — out of space, I/O error, can't-open,
    // not-a-database, corrupt, read-only. BUSY / LOCKED and any other code fall
    // through to the transient generic branch.
    if let dbError = error as? DatabaseError, isFatalDatabaseError(dbError) {
      return Classification(
        category: .unrecoverable(.storageUnavailable), displayMessage: nil,
        technicalDetail: String(describing: dbError))
    }
    return nil
  }

  /// Whether a `DatabaseError`'s result code is one of the enumerated FATAL,
  /// non-retryable codes. Extended codes fold onto their primary code, so e.g.
  /// `SQLITE_IOERR_*` and `SQLITE_READONLY_*` are covered. `SQLITE_BUSY` /
  /// `SQLITE_LOCKED` (and every code not listed) are treated as transient.
  static func isFatalDatabaseError(_ error: DatabaseError) -> Bool {
    switch error.resultCode.primaryResultCode {
    case .SQLITE_FULL, .SQLITE_IOERR, .SQLITE_CANTOPEN, .SQLITE_NOTADB,
      .SQLITE_CORRUPT, .SQLITE_READONLY:
      return true
    default:
      return false
    }
  }

  // MARK: - Message inspection

  /// Classify a bound English message. A message is treated as clean validation
  /// only when it carries no internal-invariant marker, no storage marker, and
  /// no raw entity identifier; otherwise it is genericized so the raw detail
  /// stays out of the alert.
  static func classifyMessage(_ message: String) -> Classification {
    let lowered = message.lowercased()

    // Internal post-conditions ("missing after insert", "not found after
    // mutation") are developer-facing invariants — always generic.
    if invariantMarkers.contains(where: lowered.contains) {
      return Classification(category: .generic, displayMessage: nil, technicalDetail: message)
    }

    // Storage-layer wording that could carry SQL / schema names.
    if storageMarkers.contains(where: lowered.contains) {
      return Classification(category: .generic, displayMessage: nil, technicalDetail: message)
    }

    // A raw UUIDv7 entity id must never surface. A lookup miss reads as "no
    // longer exists"; anything else id-bearing is generic.
    if containsRawIdentifier(message) {
      let category: Category = notFoundPhrases.contains(where: lowered.contains) ? .notFound : .generic
      return Classification(category: category, displayMessage: nil, technicalDetail: message)
    }

    // No raw id, no internal markers: a clean, human validation sentence.
    return Classification(category: .validation, displayMessage: message, technicalDetail: message)
  }

  /// True when `message` contains a canonical hyphenated UUID (any version),
  /// the shape of every `EntityID` / typed id in the store.
  static func containsRawIdentifier(_ message: String) -> Bool {
    message.range(of: uuidPattern, options: [.regularExpression, .caseInsensitive]) != nil
  }

  private static let uuidPattern =
    "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"

  private static let invariantMarkers = [
    "missing after",
    "after insert",
    "after import",
    "after mutation",
    "after update",
    "after upsert",
    "after restore",
    "after exception",
  ]

  private static let storageMarkers = [
    "sqlite",
    "no such table",
    "no such column",
    "database is locked",
    "database disk image",
    "constraint failed",
    "foreign key constraint",
  ]

  private static let notFoundPhrases = [
    "not found",
    "no longer",
    "does not exist",
    "doesn't exist",
  ]
}

import Foundation
import GRDB
import LorvexRuntime
import LorvexStore
import Testing

@testable import LorvexCore

/// The alert-layer error mapping: raw UUIDs, SQL, and internal invariants are
/// classified into generic categories (never shown), while clean validation
/// sentences pass through. The raw detail is always retained for `error_logs`.
@Suite("UserFacingError classification")
struct UserFacingErrorTests {
  private let copy = UserFacingError.Copy(
    itemNoLongerExists: "That item no longer exists.",
    somethingWentWrong: "Something went wrong. Please try again.",
    storageUnavailable: "Storage unavailable.",
    databaseNewer: "Update Lorvex.")

  @Test("a not-found error surfaces the generic message, never the raw UUID")
  func notFoundHidesRawIdentifier() {
    let uuid = "0192f3a1-7c4b-7def-9abc-1234567890ab"
    let error = LorvexCoreError.unsupportedOperation("Habit '\(uuid)' not found.")

    let classification = UserFacingError.classify(error)
    #expect(classification.category == .notFound)

    let message = UserFacingError.message(for: classification, copy: copy)
    #expect(message == "That item no longer exists.")
    #expect(!message.contains(uuid))
    // The raw detail is preserved for diagnostics, not discarded.
    #expect(classification.technicalDetail.contains(uuid))
  }

  @Test("taskNotFound maps to the generic not-found message")
  func taskNotFoundIsGeneric() {
    let classification = UserFacingError.classify(LorvexCoreError.taskNotFound)
    #expect(classification.category == .notFound)
    #expect(UserFacingError.message(for: classification, copy: copy) == "That item no longer exists.")
  }

  @Test("a GRDB error surfaces the generic message and logs the SQL detail")
  func grdbErrorIsGenericAndLogged() {
    let error = DatabaseError(
      resultCode: .SQLITE_ERROR,
      message: "no such table: tasks",
      sql: "SELECT * FROM tasks WHERE id = ?",
      arguments: ["0192f3a1-7c4b-7def-9abc-1234567890ab"])

    let classification = UserFacingError.classify(error)
    #expect(classification.category == .generic)

    let message = UserFacingError.message(for: classification, copy: copy)
    #expect(message == "Something went wrong. Please try again.")
    #expect(!message.contains("SELECT"))
    // The SQL / table name must reach the diagnostics detail for triage.
    #expect(classification.technicalDetail.contains("tasks"))
  }

  @Test("an internal invariant is genericized even though it carries an id")
  func invariantIsGeneric() {
    let uuid = "0192f3a1-7c4b-7def-9abc-1234567890ab"
    let error = LorvexCoreError.unsupportedOperation("Habit '\(uuid)' missing after insert.")

    let classification = UserFacingError.classify(error)
    #expect(classification.category == .generic)
    #expect(!UserFacingError.message(for: classification, copy: copy).contains(uuid))
    #expect(classification.technicalDetail.contains("missing after insert"))
  }

  @Test("a validation message passes through verbatim")
  func validationPassesThrough() {
    let error = LorvexCoreError.unsupportedOperation("Mood must be between 1 and 5.")

    let classification = UserFacingError.classify(error)
    #expect(classification.category == .validation)
    #expect(
      UserFacingError.message(for: classification, copy: copy) == "Mood must be between 1 and 5.")
  }

  @Test("emptyTitle passes through as a validation message")
  func emptyTitleIsValidation() {
    let classification = UserFacingError.classify(LorvexCoreError.emptyTitle)
    #expect(classification.category == .validation)
    #expect(UserFacingError.message(for: classification, copy: copy) == "A task title is required.")
  }

  @Test("an opaque non-localized error is generic")
  func opaqueErrorIsGeneric() {
    struct Opaque: Error {}
    let classification = UserFacingError.classify(Opaque())
    #expect(classification.category == .generic)
    #expect(
      UserFacingError.message(for: classification, copy: copy)
        == "Something went wrong. Please try again.")
  }

  @Test("a typed .notFound surfaces the generic message and hides the raw id")
  func typedNotFoundIsGeneric() {
    let uuid = "0192f3a1-7c4b-7def-9abc-1234567890ab"
    let classification = UserFacingError.classify(
      LorvexCoreError.notFound(entity: .list, id: uuid))
    #expect(classification.category == .notFound)
    let message = UserFacingError.message(for: classification, copy: copy)
    #expect(message == "That item no longer exists.")
    #expect(!message.contains(uuid))
    // The id-bearing description is still retained for diagnostics.
    #expect(classification.technicalDetail.contains(uuid))
    #expect(classification.technicalDetail == "List '\(uuid)' not found.")
  }

  @Test("a typed .notFound classifies identically to its string predecessor")
  func typedNotFoundMatchesStringPath() {
    let uuid = "0192f3a1-7c4b-7def-9abc-1234567890ab"
    for (entity, noun) in [
      (LorvexEntityKind.list, "List"),
      (LorvexEntityKind.habit, "Habit"),
      (LorvexEntityKind.calendarEvent, "Calendar event"),
      (LorvexEntityKind.calendarSeries, "Calendar series"),
    ] {
      let typed = UserFacingError.classify(LorvexCoreError.notFound(entity: entity, id: uuid))
      let legacy = UserFacingError.classify(
        LorvexCoreError.unsupportedOperation("\(noun) '\(uuid)' not found."))
      #expect(typed == legacy, "typed vs string classification diverged for \(noun)")
      #expect(typed.category == .notFound)
    }
  }

  @Test("a typed .validation passes through verbatim")
  func typedValidationPassesThrough() {
    let classification = UserFacingError.classify(
      LorvexCoreError.validation(field: "mood", message: "Mood must be between 1 and 5."))
    #expect(classification.category == .validation)
    #expect(
      UserFacingError.message(for: classification, copy: copy) == "Mood must be between 1 and 5.")
  }

  @Test("a migrated App-Intents validation classifies identically to its string predecessor")
  func typedValidationMatchesStringPath() {
    // Each of these messages was thrown as `unsupportedOperation(message)` before
    // the App-Intents validators migrated to `.validation(field:message:)`. The
    // alert layer must present them identically: the typed case and the raw string
    // both land in `.validation` with the message shown verbatim, so no user-facing
    // wording moves. `field` is deliberately varied to prove it never affects the
    // classification.
    let cases: [(field: String?, message: String)] = [
      ("task_id", "A task ID is required."),
      ("priority", "Task priority must be 1, 2, or 3."),
      ("estimated_minutes", "Estimated minutes must be non-negative."),
      ("status", "Unsupported task status filter."),
      (nil, "A tag is required."),
    ]
    for (field, message) in cases {
      let typed = UserFacingError.classify(LorvexCoreError.validation(field: field, message: message))
      let legacy = UserFacingError.classify(LorvexCoreError.unsupportedOperation(message))
      #expect(typed == legacy, "typed vs string classification diverged for \(message)")
      #expect(typed.category == .validation)
      #expect(UserFacingError.message(for: typed, copy: copy) == message)
    }
  }

  @Test("a migrated core-service validation classifies as validation, matching its string path")
  func coreServiceValidationClassifiesAsValidation() {
    // Core-service caller-input guards (e.g. milestone_target) throw typed
    // `.validation`. The alert layer presents the typed case and the equivalent
    // raw string identically — both land in `.validation` with the message shown
    // verbatim — so promoting the MCP dispatch code moved no user-facing wording.
    let message = "milestone_target must be a positive number."
    let typed = UserFacingError.classify(
      LorvexCoreError.validation(field: "milestone_target", message: message))
    let stringPath = UserFacingError.classify(LorvexCoreError.unsupportedOperation(message))
    #expect(typed == stringPath)
    #expect(typed.category == .validation)
    #expect(UserFacingError.message(for: typed, copy: copy) == message)
  }

  @Test("a typed .conflict classifies as validation, matching its string path")
  func typedConflictClassifiesAsValidation() {
    // A uniqueness collision (rename a tag / memory onto an existing name) carries
    // a clean, id-free sentence. The alert layer must present the typed `.conflict`
    // and the equivalent raw string identically — both land in `.validation` with
    // the message shown verbatim — so promoting the MCP dispatch code to `conflict`
    // moved no user-facing wording.
    let message =
      "A tag named 'errands' already exists. Re-tag those tasks onto it "
        + "instead of renaming 'chores' into it."
    let typed = UserFacingError.classify(LorvexCoreError.conflict(message: message))
    let stringPath = UserFacingError.classify(LorvexCoreError.unsupportedOperation(message))
    #expect(typed == stringPath)
    #expect(typed.category == .validation)
    #expect(UserFacingError.message(for: typed, copy: copy) == message)
  }

  // MARK: - Fatal-storage classification (unrecoverable)

  @Test("SchemaDowngrade classifies as unrecoverable with the update-Lorvex copy")
  func schemaDowngradeYieldsUpdateCopy() {
    let error = LorvexStore.SchemaDowngrade(binaryMaxVersion: 1, dbMaxVersion: 2)
    let classification = UserFacingError.classify(error)
    #expect(classification.category == .unrecoverable(.databaseNewer))
    #expect(UserFacingError.message(for: classification, copy: copy) == "Update Lorvex.")
    // The raw detail is preserved for diagnostics, but never shown.
    #expect(!classification.technicalDetail.isEmpty)
  }

  @Test("a schema mismatch classifies as unrecoverable storage, not retryable")
  func schemaMismatchIsUnrecoverable() {
    let error = LorvexStore.SchemaMismatch(
      kind: .checksumMismatch, recorded: "old", expected: "new")
    let classification = UserFacingError.classify(error)
    #expect(classification.category == .unrecoverable(.storageUnavailable))
    #expect(UserFacingError.message(for: classification, copy: copy) == "Storage unavailable.")
  }

  @Test("an incomplete-schema failure classifies as unrecoverable storage")
  func schemaIncompleteIsUnrecoverable() {
    let error = LorvexStore.SchemaIncomplete(missingTables: ["tasks", "lists"])
    let classification = UserFacingError.classify(error)
    #expect(classification.category == .unrecoverable(.storageUnavailable))
    let message = UserFacingError.message(for: classification, copy: copy)
    #expect(message == "Storage unavailable.")
    // No raw table names leak into the shown copy; they stay in the detail.
    #expect(!message.contains("tasks"))
    #expect(classification.technicalDetail.contains("tasks"))
  }

  @Test("a failed shipped migration classifies as unrecoverable storage")
  func schemaMigrationFailedIsUnrecoverable() {
    struct Underlying: Error {}
    let error = LorvexStore.SchemaMigrationFailed(
      version: 2, name: "add_widgets", underlying: Underlying())
    let classification = UserFacingError.classify(error)
    #expect(classification.category == .unrecoverable(.storageUnavailable))
    #expect(UserFacingError.message(for: classification, copy: copy) == "Storage unavailable.")
  }

  @Test("an unresolvable managed location classifies as unrecoverable storage")
  func dbLocationErrorIsUnrecoverable() {
    let error = DbLocationError.appGroupContainerUnavailable(appGroupIdentifier: "group.lorvex")
    let classification = UserFacingError.classify(error)
    #expect(classification.category == .unrecoverable(.storageUnavailable))
    let message = UserFacingError.message(for: classification, copy: copy)
    #expect(message == "Storage unavailable.")
    // The App Group identifier is diagnostic detail, never shown to the user.
    #expect(!message.contains("group.lorvex"))
    #expect(classification.technicalDetail.contains("group.lorvex"))
  }

  @Test("each fatal SQLite result code classifies as unrecoverable, not generic")
  func fatalDatabaseCodesAreUnrecoverable() {
    let fatal: [ResultCode] = [
      .SQLITE_FULL, .SQLITE_IOERR, .SQLITE_CANTOPEN, .SQLITE_NOTADB,
      .SQLITE_CORRUPT, .SQLITE_READONLY,
    ]
    for code in fatal {
      let error = DatabaseError(
        resultCode: code, message: "no such table: tasks",
        sql: "SELECT * FROM tasks", arguments: ["0192f3a1-7c4b-7def-9abc-1234567890ab"])
      let classification = UserFacingError.classify(error)
      #expect(
        classification.category == .unrecoverable(.storageUnavailable),
        "\(code) should escalate to unrecoverable storage")
      let message = UserFacingError.message(for: classification, copy: copy)
      #expect(message == "Storage unavailable.")
      // No SQL / raw id leaks into the shown copy; it stays in the detail.
      #expect(!message.contains("SELECT"))
      #expect(classification.technicalDetail.contains("tasks"))
    }
  }

  @Test("SQLITE_BUSY / SQLITE_LOCKED stay retryable (generic), not unrecoverable")
  func busyAndLockedStayRetryable() {
    for code in [ResultCode.SQLITE_BUSY, .SQLITE_LOCKED] {
      let error = DatabaseError(resultCode: code, message: "database is locked")
      let classification = UserFacingError.classify(error)
      #expect(
        classification.category == .generic,
        "\(code) is transient and must keep the retryable generic copy")
      #expect(
        UserFacingError.message(for: classification, copy: copy)
          == "Something went wrong. Please try again.")
    }
  }

  @Test("an un-migrated name-keyed not-found still classifies via the string path")
  func nameKeyedNotFoundStaysValidation() {
    // Some name-keyed not-found throws stay `unsupportedOperation` to preserve an
    // actionable guidance sentence (e.g. the `merge_tags` not-found). Their id is a
    // human name, not a raw UUID, so the string path shows the message verbatim as
    // validation — distinct from a typed `.notFound`, which genericizes to the
    // "no longer exists" copy.
    let classification = UserFacingError.classify(
      LorvexCoreError.unsupportedOperation("Tag 'work' not found."))
    #expect(classification.category == .validation)
    #expect(
      UserFacingError.message(for: classification, copy: copy) == "Tag 'work' not found.")
  }
}

import Foundation
import GRDB
import LorvexDomain
import LorvexRuntime
import LorvexStore
import LorvexSync
import LorvexWorkflow
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

  @Test("an empty title reads as the title-required reason")
  func emptyTitleIsTheTitleRequiredReason() {
    for error: Error in [LorvexCoreError.emptyTitle, ValidationError.empty("title")] {
      let classification = UserFacingError.classify(error)
      #expect(classification.category == .validation)
      #expect(classification.reason == .titleRequired)
      #expect(
        UserFacingError.message(for: classification, copy: copy)
          == UserFacingError.Reason.titleRequired.localizedMessage)
    }
    #expect(
      UserFacingError.classify(LorvexCoreError.emptyTitle).technicalDetail
        == "A task title is required.")
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

  // MARK: - Reasons the app words itself

  @Test("an over-long field shows the app's own sentence for that field")
  func tooLongFieldClassifiesToItsReason() {
    let cases: [(field: String, reason: UserFacingError.Reason)] = [
      ("title", .titleTooLong), ("body", .notesTooLong), ("tag", .tagTooLong),
      ("tags", .tagTooLong), ("raw_input", .textTooLong), ("ai_notes", .textTooLong),
    ]
    for (field, reason) in cases {
      let error = ValidationError.tooLong(field: field, max: 10, actual: 12)
      let classification = UserFacingError.classify(error)
      #expect(classification.reason == reason, "field \(field)")
      #expect(classification.category == .validation)
      #expect(UserFacingError.message(for: classification, copy: copy) == reason.localizedMessage)
      // The core's English sentence stays the detail `error_logs` records.
      #expect(classification.technicalDetail == error.description)
    }
  }

  @Test("a tag or memory rename collision shows the app's own sentence")
  func renameCollisionClassifiesToItsReason() {
    let tagMessage = "A tag named 'errands' already exists."
    let tag = UserFacingError.classify(LorvexCoreError.conflict(message: tagMessage, entity: .tag))
    #expect(tag.reason == .tagNameTaken)
    #expect(tag.category == .validation)
    #expect(
      UserFacingError.message(for: tag, copy: copy)
        == UserFacingError.Reason.tagNameTaken.localizedMessage)
    #expect(tag.technicalDetail == tagMessage)

    let memory = UserFacingError.classify(
      LorvexCoreError.conflict(message: "Memory 'b' already exists.", entity: .memory))
    #expect(memory.reason == .memoryNameTaken)

    // A collision on an entity the app has no sentence for keeps the verbatim
    // message, exactly as an untagged collision does.
    let list = UserFacingError.classify(
      LorvexCoreError.conflict(message: "That list already exists.", entity: .list))
    #expect(list.reason == nil)
    #expect(UserFacingError.message(for: list, copy: copy) == "That list already exists.")
  }

  @Test("an event starting inside a daylight-saving gap shows the app's own sentence")
  func skippedStartTimeClassifiesToItsReason() {
    let error = CalendarEventOpError.startTimeSkipped(
      time: "02:30", date: "2027-03-14", timezone: "America/New_York")
    let classification = UserFacingError.classify(error)
    #expect(classification.reason == .calendarTimeSkipped)
    #expect(classification.category == .validation)
    #expect(classification.technicalDetail == error.description)
    // The MCP boundary keeps the core's sentence, which names the gap.
    #expect(error.description.contains("02:30 on 2027-03-14 does not exist in America/New_York"))
  }

  @Test("a blocked start and a duplicate reminder time show the app's own sentences")
  func dataRefusalsClassifyToTheirReasons() {
    let blocked = TaskLifecycleError.startBlockedByDependencies(
      taskId: "0192f3a1-7c4b-7def-9abc-1234567890ab",
      blockerIds: ["0192f3a1-7c4b-7def-9abc-1234567890ac"])
    let start = UserFacingError.classify(blocked)
    #expect(start.reason == .taskStartBlocked)
    #expect(start.category == .validation)
    #expect(
      UserFacingError.message(for: start, copy: copy)
        == UserFacingError.Reason.taskStartBlocked.localizedMessage)
    // The id-bearing sentence stays out of the alert but reaches error_logs.
    #expect(start.technicalDetail == blocked.description)

    let duplicate = HabitReminderError.timeTaken(
      habitId: "0192f3a1-7c4b-7def-9abc-1234567890ad", time: "08:00")
    let reminder = UserFacingError.classify(duplicate)
    #expect(reminder.reason == .habitReminderTimeTaken)
    #expect(
      UserFacingError.message(for: reminder, copy: copy)
        == UserFacingError.Reason.habitReminderTimeTaken.localizedMessage)
  }

  @Test("a refused status change shows the app's own sentence for that change")
  func refusedStatusChangesClassifyToTheirReasons() {
    let id = "0192f3a1-7c4b-7def-9abc-1234567890ab"
    let cases: [(TaskLifecycleError, UserFacingError.Reason)] = [
      (.startRequiresOpenTask(status: .completed), .startingDoneTask),
      (.startRequiresOpenTask(status: .cancelled), .startingCanceledTask),
      (.startRequiresOpenTask(status: .someday), .startingSomedayTask),
      (.finishedTaskTransition(taskId: id, from: .cancelled, to: .completed), .completingCanceledTask),
      (.finishedTaskTransition(taskId: id, from: .completed, to: .cancelled), .cancelingDoneTask),
      (.pauseRequiresStartedTask(status: .completed), .pausingUnstartedTask),
      (.pauseRequiresStartedTask(status: .someday), .pausingUnstartedTask),
      (.reopenBlockedByAdvancedSuccessor(taskId: id, successorId: id), .reopeningAdvancedRepeat),
      (.completeBlockedByAdvancedSuccessor(taskId: id, successorId: id), .completingAdvancedRepeat),
    ]
    for (error, reason) in cases {
      let classification = UserFacingError.classify(error)
      #expect(classification.reason == reason, "\(error)")
      #expect(classification.category == .validation)
      #expect(UserFacingError.message(for: classification, copy: copy) == reason.localizedMessage)
      // The core's sentence (which may carry the task id) stays the logged detail.
      #expect(classification.technicalDetail == error.description)
    }

    // The MCP boundary keeps the core's English sentences unchanged.
    #expect(
      TaskLifecycleError.startRequiresOpenTask(status: .completed).description
        == "Cannot start a completed task; reopen it to open first.")
    #expect(
      TaskLifecycleError.pauseRequiresStartedTask(status: .open).description
        == "Cannot pause a open task; only an in-progress task can be paused.")
    #expect(
      TaskLifecycleError.finishedTaskTransition(taskId: id, from: .cancelled, to: .completed)
        .description == "Cannot transition task \(id) from cancelled to completed; reopen it first")
    #expect(
      TaskLifecycleError.reopenBlockedByAdvancedSuccessor(taskId: id, successorId: "next")
        .description
        == "Cannot reopen task \(id): recurrence successor next has already advanced")
    #expect(
      TaskLifecycleError.completeBlockedByAdvancedSuccessor(taskId: id, successorId: "next")
        .description == "Cannot re-complete task \(id): successor next has already advanced")
  }

  @Test("a classification survives an encode and decode unchanged")
  func classificationRoundTripsThroughJSON() throws {
    let samples = [
      UserFacingError.classify(TaskLifecycleError.startRequiresOpenTask(status: .someday)),
      UserFacingError.classify(LorvexCoreError.taskNotFound),
      UserFacingError.classify(LorvexStore.SchemaDowngrade(binaryMaxVersion: 3, dbMaxVersion: 9)),
      UserFacingError.classify(message: "Notifications are not allowed for this app."),
    ]
    for classification in samples {
      let data = try JSONEncoder().encode(classification)
      #expect(try JSONDecoder().decode(UserFacingError.Classification.self, from: data) == classification)
    }
  }

  @Test("other validation failures keep their own sentence, as when the core wrapped them")
  func otherValidationFailuresKeepTheirSentence() {
    let error = ValidationError.outOfRange(field: "estimated_minutes", min: 1, max: 1440, actual: 0)
    let bare = UserFacingError.classify(error)
    let wrapped = UserFacingError.classify(StoreError.validation(error.description))
    #expect(bare == wrapped)
    #expect(bare.reason == nil)
    #expect(UserFacingError.message(for: bare, copy: copy) == error.description)
    // `localizedDescription` reads the same sentence, never Cocoa's generic one.
    #expect(error.localizedDescription == error.description)
  }

  @Test("a record too long to sync shows its own sentence; the detail keeps the sizes")
  func recordTooLongToSyncIsWorded() throws {
    let service = try SwiftLorvexCoreService.inMemory()
    let error = service.mapWriteError(EnqueueError.canonicalization(.payloadTooLarge(sizeBytes: 70_000)))
    let classification = UserFacingError.classify(error)
    #expect(classification.reason == .recordTooLongToSync)
    #expect(
      UserFacingError.message(for: classification, copy: copy)
        == UserFacingError.Reason.recordTooLongToSync.localizedMessage)
    // The MCP envelope and the diagnostics log keep the English sentence.
    #expect(classification.technicalDetail.contains("70000 bytes"))
    #expect((error as? LorvexCoreError)?.errorDescription?.contains("too large to sync") == true)
  }

  @Test("every reason has its own sentence, translated in the LorvexCore bundle")
  func reasonSentencesShipTranslated() throws {
    let reasons = UserFacingError.Reason.allCases
    let sentences = reasons.map(\.localizedMessage)
    #expect(Set(sentences).count == reasons.count, "two reasons share a sentence")
    #expect(sentences.allSatisfy { !$0.hasPrefix("error.reason.") })

    let keys = [
      "error.reason.title_required",
      "error.reason.title_too_long", "error.reason.notes_too_long",
      "error.reason.tag_too_long", "error.reason.text_too_long",
      "error.reason.tag_name_taken", "error.reason.memory_name_taken",
      "error.reason.calendar_time_skipped", "error.reason.task_start_blocked",
      "error.reason.habit_reminder_time_taken", "error.reason.starting_done_task",
      "error.reason.starting_canceled_task", "error.reason.starting_someday_task",
      "error.reason.completing_canceled_task", "error.reason.canceling_done_task",
      "error.reason.pausing_unstarted_task", "error.reason.record_too_long_to_sync",
      "error.reason.reopening_advanced_repeat", "error.reason.completing_advanced_repeat",
    ]
    #expect(keys.count == reasons.count, "a reason is missing from this key list")
    let lproj = try #require(CoreL10n.bundle.url(forResource: "zh-Hans", withExtension: "lproj"))
    let chinese = try #require(Bundle(url: lproj))
    for key in keys {
      let value = chinese.localizedString(forKey: key, value: nil, table: "Localizable")
      #expect(value != key, "\(key) has no zh-Hans translation")
      #expect(value.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }, "\(key): \(value)")
    }
  }

  @Test("the standard copy reads the LorvexCore catalog, which translates it")
  func standardCopyIsTranslated() throws {
    let standard = UserFacingError.Copy.standard
    let sentences = [
      standard.itemNoLongerExists, standard.somethingWentWrong,
      standard.storageUnavailable, standard.databaseNewer,
    ]
    #expect(Set(sentences).count == 4)
    #expect(sentences.allSatisfy { !$0.hasPrefix("error.") })

    let lproj = try #require(CoreL10n.bundle.url(forResource: "zh-Hans", withExtension: "lproj"))
    let chinese = try #require(Bundle(url: lproj))
    for key in ["error.item_gone", "error.generic", "error.storage_unavailable", "error.database_newer"] {
      let value = chinese.localizedString(forKey: key, value: nil, table: "Localizable")
      #expect(value != key, "\(key) has no zh-Hans translation")
      #expect(value.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }, "\(key): \(value)")
    }
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

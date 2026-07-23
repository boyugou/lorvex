import Foundation

/// Backend capability for the native (per-category JSON/ZIP) import path:
/// id-preserving restore of every export category `LorvexDataImporter` replays.
/// `SwiftLorvexCoreService` is the sole conformer and `LorvexDataImporter` the
/// sole consumer, reached by conformance downcast (`core as? any
/// LorvexNativeImportServicing`) because these id-preserving restore entries are
/// not part of the canonical ``LorvexCoreServicing`` write contract.
///
/// The methods fall into three families:
///
/// - **Atomic record imports** — the `import…IfAbsent` entry points and the two
///   `import…RecordTransactionally` methods. Each runs its presence check,
///   tombstone guard, and write in ONE `BEGIN IMMEDIATE` transaction, so a bulk
///   restore never overwrites a row a concurrent create landed in the gap between
///   a separate presence read and the write, and never resurrects an entity the
///   user deleted after the backup was taken (a fresh dominating import HLC would
///   otherwise beat the death version and re-propagate the row fleet-wide). The
///   `…IfAbsent` methods report whether they wrote (`imported`) or skipped; the
///   multi-part `…Transactionally` methods additionally roll the whole record —
///   and every sync-outbox envelope it enqueued — back on any failure.
/// - **Item / child replays** — tag, focus, habit completion, task child, habit
///   reminder policy, task↔calendar-event link, and the revision-replay memory
///   overload. Each restores one exported item preserving its exported identity.
///   Categories with a single write per record are already atomic through their
///   own transaction and are imported through these directly.
/// - **Unlink** — remove the canonical task↔calendar-event link.
///
/// One complete `create_task`-surface row of a task-record create: the plain
/// draft fields plus the id-preserving `originalID`, a requested lifecycle
/// `status`, historical `createdAt` / `completedAt` timestamps, and an ordered
/// initial checklist. `reference` is the caller's per-row handle for failure
/// reporting (its `original_id`, else its title, else an index reference) and is
/// never persisted.
public struct TaskRecordCreateSpec: Sendable {
  public var reference: String
  public var originalID: String?
  public var title: String
  public var notes: String
  public var rawInput: String?
  public var listID: String?
  public var priority: LorvexTask.Priority
  public var estimatedMinutes: Int?
  public var dueDate: Date?
  public var plannedDate: Date?
  public var availableFrom: Date?
  public var tags: [String]?
  public var dependsOn: [String]?
  public var status: LorvexTask.Status?
  public var createdAt: String?
  public var completedAt: String?
  public var checklistTexts: [String]

  public init(
    reference: String, originalID: String? = nil, title: String, notes: String = "",
    rawInput: String? = nil, listID: String? = nil, priority: LorvexTask.Priority = .p2,
    estimatedMinutes: Int? = nil, dueDate: Date? = nil, plannedDate: Date? = nil,
    availableFrom: Date? = nil, tags: [String]? = nil, dependsOn: [String]? = nil,
    status: LorvexTask.Status? = nil, createdAt: String? = nil, completedAt: String? = nil,
    checklistTexts: [String] = []
  ) {
    self.reference = reference
    self.originalID = originalID
    self.title = title
    self.notes = notes
    self.rawInput = rawInput
    self.listID = listID
    self.priority = priority
    self.estimatedMinutes = estimatedMinutes
    self.dueDate = dueDate
    self.plannedDate = plannedDate
    self.availableFrom = availableFrom
    self.tags = tags
    self.dependsOn = dependsOn
    self.status = status
    self.createdAt = createdAt
    self.completedAt = completedAt
    self.checklistTexts = checklistTexts
  }
}

/// Per-row outcome of ``LorvexNativeImportServicing/batchCreateTaskRecords(_:)``,
/// in input order. A failed row carries its spec's `reference` and the error
/// that rolled its savepoint back; the surrounding transaction and the other
/// rows are unaffected.
public enum TaskRecordCreateOutcome: Sendable {
  case created(LorvexTask)
  case failed(reference: String, error: any Error)
}

/// Exact row-version witness returned by a portable task restore's create
/// transaction. Deferred dependency/lifecycle/metadata work may proceed only
/// while the task still carries this version; any intervening UI, MCP, intent,
/// or sync edit makes the witness stale instead of letting backup fields win.
public struct ImportedTaskRecordCreationWitness: Sendable, Equatable {
  let taskID: LorvexTask.ID
  let rowVersion: String
}

public enum ImportedTaskRecordFinalizeStep: String, Sendable, Equatable {
  case dependencies
  case lifecycle
  case metadata
}

public struct ImportedTaskRecordFinalizeFailure: Sendable, Equatable {
  public var step: ImportedTaskRecordFinalizeStep
  public var message: String

  public init(step: ImportedTaskRecordFinalizeStep, message: String) {
    self.step = step
    self.message = message
  }
}

public struct ImportedTaskRecordFinalizeResult: Sendable, Equatable {
  public var matchedCreationWitness: Bool
  public var failures: [ImportedTaskRecordFinalizeFailure]

  public init(
    matchedCreationWitness: Bool,
    failures: [ImportedTaskRecordFinalizeFailure] = []
  ) {
    self.matchedCreationWitness = matchedCreationWitness
    self.failures = failures
  }
}

/// One umbrella protocol (rather than one per category) because every real
/// backend that supports native import supports all of these together, and the
/// importer treats "native import available" as a single capability.
public protocol LorvexNativeImportServicing: Sendable {

  // MARK: - Atomic record imports (presence + tombstone guarded, in one tx)

  /// Restore one exported list, id-preserving, only when no live row and no
  /// delete tombstone already claim its id. Returns the imported list and `true`
  /// on a write; `(nil, false)` when a live `lists` row with this id already
  /// exists (a concurrent create won the gap) or the id is tombstoned (the user
  /// deleted the list after the backup). The presence check and insert share one
  /// transaction, so the decision cannot race a concurrent write.
  func importListIfAbsent(
    id: String,
    name: String,
    description: String?,
    color: String?,
    icon: String?,
    aiNotes: String?,
    archivedAt: String?,
    position: Int64?
  ) async throws -> (LorvexList?, Bool)

  /// Restore one exported tag, resolving its id by exported id first then by
  /// `lookup_key` (merge-by-name), only when neither resolution finds a live row
  /// and the resolved id is not tombstoned. Returns `true` on a write, `false` on
  /// a skip. Presence and insert share one transaction.
  func importTagIfAbsent(_ tag: ExportTag) async throws -> Bool

  /// Restore one exported calendar event, id-preserving, only when no live row
  /// and no tombstone claim its id. Returns the imported event and `true` on a
  /// write; `(nil, false)` on a skip. Presence and insert share one transaction.
  func importCalendarEventIfAbsent(
    id: String,
    title: String,
    startDate: String,
    startTime: String?,
    endDate: String?,
    endTime: String?,
    allDay: Bool,
    location: String?,
    notes: String?,
    url: String?,
    color: String?,
    eventType: String?,
    personName: String?,
    attendees: [CalendarEventAttendee]?,
    timezone: String?,
    recurrence: String?,
    seriesId: String?,
    recurrenceInstanceDate: String?,
    occurrenceState: String?,
    recurrenceGeneration: String?,
    seriesCutoverId: String?
  ) async throws -> (CalendarTimelineEvent?, Bool)

  /// Restore the canonical calendar bundle in one transaction. Durable series
  /// boundaries are validated against their segment events before either side
  /// is written; a failure in any event rolls the boundaries and all previously
  /// applied event rows back. Deleted boundaries use the same absorbing
  /// remove-wins join as sync. Counts include user-visible event rows only.
  func importCalendarBundle(
    cutovers: [ExportCalendarSeriesCutover], events: [ExportCalendarEvent]
  ) async throws -> NativeCalendarImportResult

  /// Restore one exported daily review (a singleton per `date`) only when no live
  /// row for that date and no tombstone claim it. Returns `true` on a write,
  /// `false` on a skip. Presence and upsert share one transaction.
  func importDailyReviewIfAbsent(
    date: String,
    summary: String,
    mood: Int?,
    energyLevel: Int?,
    wins: String?,
    blockers: String?,
    learnings: String?,
    timezone: String?,
    updatedAt: String?,
    linkedTaskIDs: [String]?,
    linkedListIDs: [String]?
  ) async throws -> Bool

  /// Restore one exported current-focus plan (a singleton per `date`) only when
  /// no live row for that date and no tombstone claim it. Returns `true` on a
  /// write, `false` on a skip. Presence and write share one transaction.
  func importCurrentFocusIfAbsent(_ focus: ExportCurrentFocus) async throws -> Bool

  /// Restore one exported focus schedule (a singleton per `date`) only when no
  /// live row for that date and no tombstone claim it. Returns `true` on a write,
  /// `false` on a skip. Presence and write share one transaction.
  func importFocusScheduleIfAbsent(_ schedule: ExportFocusSchedule) async throws -> Bool

  /// Restore one exported memory entry (keyed by its human `key`, a UNIQUE
  /// column) only when no live row holds that key and the resolved opaque memory
  /// id is not tombstoned. Returns the imported entry and `true` on a write;
  /// `(nil, false)` on a skip. Presence and write share one transaction.
  func importMemoryEntryIfAbsent(_ entry: ExportMemoryEntry) async throws -> (MemoryEntry?, Bool)

  /// Restore one exported task and its owned children (list membership,
  /// checklist, reminders, recurrence) atomically in one transaction. The parsed
  /// `priority` and date fields are supplied by the caller, which owns
  /// parse-error reporting. `dependenciesToApply` is normally empty for a bulk
  /// archive restore because dependency edges may forward-reference a task that
  /// appears later in the archive; an id-preserving single-record create can pass
  /// already-existing dependency ids and commit them with the task. Cancelled /
  /// in-progress state and exact metadata are applied by the caller after this
  /// record transaction. Returns an exact creation witness when the task was
  /// imported, `nil` when
  /// a task with the same id already existed or the id is tombstoned (import
  /// never overwrites or resurrects a task). Throws on any failure, having rolled
  /// the record back.
  func importTaskRecordTransactionally(
    _ task: ExportTask, priority: LorvexTask.Priority, dueDate: Date?, plannedDate: Date?,
    availableFrom: Date?, dependenciesToApply: [LorvexTask.ID]
  ) async throws -> ImportedTaskRecordCreationWitness?

  /// Complete a portable task restore only if the row is still exactly the one
  /// created by ``importTaskRecordTransactionally``. Dependency attachment is a
  /// dependency-only patch; it never rewrites title/body/schedule fields from a
  /// stale export object. The witness check and every successful deferred step
  /// share one write transaction, so a post-create edit either wins in full or
  /// cannot interleave. Independent step failures are returned for the import
  /// summary while their savepoints roll back only that step.
  func finalizeImportedTaskRecordTransactionally(
    _ task: ExportTask,
    creationWitness: ImportedTaskRecordCreationWitness
  ) async throws -> ImportedTaskRecordFinalizeResult

  /// Create every spec'd task record — id-preserving import or plain create,
  /// plus its requested lifecycle transition, historical timestamps, and initial
  /// checklist — in ONE `BEGIN IMMEDIATE` transaction with one SAVEPOINT per
  /// row. A bad row rolls back only its own savepoint and is reported in its
  /// outcome; the other rows still land. Because the whole batch is one
  /// transaction, a keyed MCP call's durable idempotency claim is exact: a crash
  /// before commit applies nothing and frees the key, a crash after commit
  /// applied everything. Outcomes are returned in input order.
  func batchCreateTaskRecords(
    _ specs: [TaskRecordCreateSpec]
  ) async throws -> [TaskRecordCreateOutcome]

  /// Restore an exported task's exact lifecycle state after all task identities
  /// and dependency edges have materialized. This import-only funnel preserves a
  /// legal `in_progress` task that later acquired an unresolved dependency;
  /// replaying the interactive `startTask` command would reject that historical
  /// state and silently degrade the backup to `open`.
  func restoreImportedTaskLifecycleState(
    id: LorvexTask.ID, status: LorvexTask.Status
  ) async throws

  /// Restore one exported habit and all of its completions and reminder policies
  /// atomically in one transaction. Returns `true` when the habit was imported,
  /// `false` when a habit with the same id already existed (a concurrent create
  /// won the gap) or the id is tombstoned (the user deleted it after the backup).
  /// Throws on any failure, having rolled the record back.
  func importHabitRecordTransactionally(_ habit: ExportHabit) async throws -> Bool

  // MARK: - Item / child replays

  func importTag(_ tag: ExportTag) async throws

  func importCurrentFocus(_ focus: ExportCurrentFocus) async throws
  func importFocusSchedule(_ schedule: ExportFocusSchedule) async throws

  func importHabitCompletion(
    habitID: String,
    completion: ExportHabitCompletion
  ) async throws

  func importHabitReminderPolicy(
    habitID: String,
    policy: ExportHabitReminderPolicy
  ) async throws

  func importTaskChecklistItem(
    taskID: String,
    item: ExportChecklistItem
  ) async throws

  func importTaskReminder(
    taskID: String,
    reminder: ExportTaskReminder
  ) async throws

  /// Create the canonical (synced) task↔calendar-event link, id-preserving.
  /// Returns `true` when a link exists after the call — a fresh link was created,
  /// or the pair was already linked (a true no-op). Returns `false` only when the
  /// call refused to resurrect a link the user deleted after the backup: a
  /// tombstone skip that applies solely under an import-context restore
  /// (``SwiftLorvexCoreService/currentInitiator`` bound to `import`). An explicit
  /// assistant relink (`assistant` initiator) falls through the tombstone and
  /// re-creates the edge.
  @discardableResult
  func importTaskCalendarEventLink(_ link: ExportTaskCalendarEventLink) async throws -> Bool

  /// Normalize a base/replacement calendar address to the series-level endpoint
  /// used by the synced canonical task-event edge.
  func resolveTaskCalendarEventLinkTarget(calendarEventID: String) async throws -> String

  /// Remove the canonical (synced) task↔calendar-event link. Returns whether a
  /// row was actually removed (`false` on a no-op unlink of an absent pair).
  @discardableResult
  func unlinkTaskCalendarEventLink(taskID: String, calendarEventID: String) async throws -> Bool

  /// Upsert one memory state (content + timestamp), used to seed preview data
  /// with a plain state-write.
  func importMemoryEntry(
    key: String,
    content: String,
    updatedAt: String?
  ) async throws -> MemoryEntry

  /// Restore a full exported memory entry: the exported id plus its latest
  /// content and timestamp. The data importer's memory apply path uses this for
  /// an overwrite-on-reimport.
  func importMemoryEntry(_ entry: ExportMemoryEntry) async throws -> MemoryEntry
}

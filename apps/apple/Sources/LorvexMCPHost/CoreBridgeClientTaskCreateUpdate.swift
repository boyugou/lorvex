import Foundation
import LorvexCore
import LorvexDomain
import MCP

extension CoreBridgeClient {
  func createTask(arguments: [String: Value], title: String) async throws -> Value {
    Self.taskValue(from: try await createTaskModel(arguments: arguments, title: title))
  }

  /// Create one task from raw MCP `arguments`, shared by `create_task` and each
  /// row of `batch_create_tasks`.
  ///
  /// When `original_id` is supplied the task is restored id-preserving through
  /// the native importer's atomic skip-if-present/tombstoned record path, so
  /// every exported cross-reference (depends_on, task↔event links, review
  /// `linked_ids`, focus `task_ids`) resolves without an old→new id map; the
  /// ordinary server-assigns-the-id create path runs without `original_id`.
  ///
  /// The optional `status` (open/in_progress/someday/completed/cancelled), the
  /// historical `created_at` / `completed_at` timestamps, and the ordered
  /// initial `checklist` are all part of the same record create: the whole row —
  /// create, lifecycle transition, timestamps, checklist — commits in one
  /// service-side transaction (``LorvexNativeImportServicing/batchCreateTaskRecords(_:)``
  /// with a single spec), so a crash never leaves a task with a partial
  /// checklist or an unapplied requested status behind a consumed idempotency
  /// claim.
  func createTaskModel(arguments: [String: Value], title: String) async throws -> LorvexTask {
    let spec = try taskRecordSpec(arguments: arguments, title: title, reference: title)
    let outcomes = try await taskRecordService().batchCreateTaskRecords([spec])
    switch outcomes.first {
    case .created(let task):
      return task
    case .failed(_, let error):
      throw error
    case .none:
      throw LorvexCoreError.unsupportedOperation("Task record creation returned no outcome.")
    }
  }

  /// The backend's transactional record-create surface. Every production
  /// backend is `SwiftLorvexCoreService`, which conforms; the throw mirrors the
  /// record surface's other capability guards.
  func taskRecordService() throws -> any LorvexNativeImportServicing {
    guard let recordService = service as? any LorvexNativeImportServicing else {
      throw LorvexCoreError.unsupportedOperation(
        "This backend does not support transactional task record creation.")
    }
    return recordService
  }

  /// Parse one `create_task`-shaped argument object into a complete
  /// ``TaskRecordCreateSpec``. Every field is validated here — a malformed row
  /// fails before any service call, which is what lets `batch_create_tasks`
  /// report it in `skipped` while the valid rows land.
  func taskRecordSpec(
    arguments: [String: Value], title: String, reference: String
  ) throws -> TaskRecordCreateSpec {
    let tagsValue = arguments["tags"] ?? arguments["tags_set"]
    let tags = try StrictArgumentArray.optionalStrings(tagsValue, field: "tags")
    let dependsOn = try StrictArgumentArray.optionalStrings(
      arguments["depends_on"], field: "depends_on")
    let originalID = try Self.strictImportOriginalID(arguments["original_id"], field: "original_id")
    if let originalID {
      try Self.validateImportOriginalID(originalID, kind: .task)
    }
    return TaskRecordCreateSpec(
      reference: reference,
      originalID: originalID,
      title: title,
      notes: try StrictScalarArguments.string(arguments["notes"], field: "notes", default: ""),
      rawInput: try StrictScalarArguments.optionalString(
        arguments["raw_input"], field: "raw_input"),
      listID: try StrictScalarArguments.optionalString(arguments["list_id"], field: "list_id"),
      priority: try Self.priority(from: arguments["priority"]) ?? .p2,
      estimatedMinutes: try StrictScalarArguments.optionalInt(
        arguments["estimated_minutes"], field: "estimated_minutes"),
      dueDate: try Self.resolveOptionalPlannedDate(
        try StrictScalarArguments.optionalString(arguments["due_date"], field: "due_date")),
      plannedDate: try Self.resolveOptionalPlannedDate(
        try StrictScalarArguments.optionalString(arguments["planned_date"], field: "planned_date")),
      availableFrom: try Self.resolveOptionalPlannedDate(
        try StrictScalarArguments.optionalString(
          arguments["available_from"], field: "available_from")),
      tags: tags,
      dependsOn: dependsOn,
      status: try Self.taskStatus(from: arguments["status"]),
      createdAt: try Self.strictImportOriginalID(arguments["created_at"], field: "created_at"),
      completedAt: try Self.strictImportOriginalID(
        arguments["completed_at"], field: "completed_at"),
      checklistTexts: try Self.initialChecklistTexts(from: arguments["checklist"]))
  }

  /// Parse and validate the optional `checklist` create argument into ordered
  /// item texts. Each entry must be a non-empty string within the checklist
  /// text-length bound, and the array must fit the per-task item cap
  /// (``maxTaskChecklistItems``) — validated here so a malformed checklist fails
  /// the create before any row is written. Absent or JSON null → no items.
  static func initialChecklistTexts(from value: Value?) throws -> [String] {
    guard let texts = try StrictArgumentArray.optionalStrings(value, field: "checklist") else {
      return []
    }
    try validateTaskChecklistItemCount(texts.count)
    for text in texts {
      try validateTaskChecklistItemText(text)
    }
    return texts
  }

  /// Trimmed, non-empty value of an `original_id` / timestamp argument, or nil
  /// when the caller omitted it (blank collapses to nil rather than a bogus id).
  /// Lenient about a wrong-typed value (→ nil); write-path spec parsing uses
  /// ``strictImportOriginalID(_:field:)`` instead — this variant remains only
  /// for display-label extraction where no meaning rides on the value.
  static func importOriginalID(_ value: Value?) -> String? {
    guard let raw = value?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
      !raw.isEmpty
    else { return nil }
    return raw
  }

  /// Strict counterpart of ``importOriginalID(_:)`` for meaning-bearing spec
  /// fields: a present wrong-typed value rejects instead of collapsing to nil
  /// (which would silently convert an id-preserving re-create into a fresh
  /// create, or drop an import timestamp).
  static func strictImportOriginalID(_ value: Value?, field: String) throws -> String? {
    guard
      let raw = try StrictScalarArguments.optionalString(value, field: field)?
        .trimmingCharacters(in: .whitespacesAndNewlines),
      !raw.isEmpty
    else { return nil }
    return raw
  }

  /// Reject a caller-supplied `original_id` that is not the canonical id form for
  /// its entity kind, at the create/import boundary.
  ///
  /// An id-preserving re-create writes this value straight into the row's primary
  /// key. Any `:` in it would later break composite-edge id splitting
  /// (`left:right` — see ``CompositeEdge/splitCompositeEdgeId``) once the row
  /// appears in a tag / dependency / task↔event-link / habit-completion edge,
  /// rejecting those edges `invalidPayload` on peer apply. Enforcing the same
  /// canonical shape the sync layer already requires for the kind (a hyphenated
  /// lowercase UUID; the `inbox` sentinel is also valid for a list) refuses a
  /// malformed id cleanly here as a `{code:"validation"}` tool error instead of
  /// letting it corrupt sync downstream.
  static func validateImportOriginalID(_ id: String, kind: EntityKind) throws {
    if case .failure = SyncEntityId.validateForKind(kind, id) {
      throw ValidationError.invalidFormat(
        field: "original_id",
        expected: kind == .list
          ? "a canonical lowercase UUID (or 'inbox')" : "a canonical lowercase UUID",
        actual: "\"\(id)\"")
    }
  }

  /// Parse an optional `status` argument into a ``LorvexTask/Status``. Absent or
  /// null → nil (the create default, `open`). An unrecognized value throws
  /// rather than silently coercing to open, matching the reject-clean handling
  /// of `priority`.
  static func taskStatus(from value: Value?) throws -> LorvexTask.Status? {
    guard let value, value != .null else { return nil }
    if let raw = value.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
      let status = LorvexTask.Status(rawValue: raw)
    {
      return status
    }
    throw ValidationError.invalidFormat(
      field: "status", expected: "open, in_progress, someday, completed, or cancelled",
      actual: value.stringValue.map { "\"\($0)\"" } ?? "a non-string value")
  }

  /// Applies a partial task update, preserving fields the caller omitted.
  ///
  /// Builds a per-field ``Patch`` draft straight from the raw tool `arguments`
  /// and routes it through the lost-update-safe `updateTask(_:)` core entry: an
  /// absent key becomes `.unset` (the column is never written, so a concurrent
  /// writer's change to it survives), while a present key — even with a
  /// null/empty value — applies the caller's intent (`.set` / `.clear`). This
  /// avoids the read-modify-write race of loading the task, filling omitted
  /// fields from that snapshot, and force-setting every column at a higher HLC.
  ///
  /// `title` is `nil` when the caller omitted it (existing title kept). A
  /// present-but-invalid `priority` is rejected upstream in the tool handler,
  /// so `priority` here is a valid 1/2/3 or nil (omitted → keep existing).
  /// `due_date` (external deadline), `planned_date` (intended work day), and
  /// `available_from` (hide-until / not-before) are independent columns, each
  /// patched from its own key.
  func updateTask(
    id: String,
    title: String?,
    priority: Int?,
    tags: [String]?,
    dependsOn: [String]?,
    arguments: [String: Value]
  ) async throws -> Value {
    let resolvedPriority: LorvexTask.Priority? =
      switch priority {
      case 1: .p1
      case 2: .p2
      case 3: .p3
      default: nil
      }
    let draft = TaskUpdateDraft(
      id: id,
      title: title,
      notes: arguments.keys.contains("notes")
        ? (try StrictScalarArguments.optionalString(arguments["notes"], field: "notes") ?? "")
        : nil,
      priority: resolvedPriority,
      estimatedMinutes: try Self.intPatch(from: arguments, key: "estimated_minutes"),
      dueDate: try Self.datePatch(from: arguments, key: "due_date"),
      plannedDate: try Self.datePatch(from: arguments, key: "planned_date"),
      availableFrom: try Self.datePatch(from: arguments, key: "available_from"),
      tags: tags,
      dependsOn: dependsOn,
      rawInput: try Self.stringPatch(from: arguments, key: "raw_input"))
    let task = try await service.updateTask(draft)
    return Self.taskValue(from: task)
  }
}

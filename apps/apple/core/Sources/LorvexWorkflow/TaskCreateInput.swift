import Foundation
import LorvexDomain

/// Pure data shapes for the task-create workflow surface:
///
/// - Every nullable scalar field is ``Patch`` so the wire shape matches
///   ``TaskUpdateInput``. At create time ``Patch/unset`` and ``Patch/clear``
///   collapse to the same NULL-on-insert; the writer consumes the lowered
///   ``Optional`` form.
/// - Collection-shaped fields (`tags`, `dependsOn`, `reminders`) stay as plain
///   `Optional<Array>` — patch-shapes for these are tracked separately.
/// - `title` is a bare `String`: create has no row to fall back to.
public struct TaskCreateInput: Sendable {
  public var title: String
  public var listId: Patch<String>
  public var priority: Patch<UInt8>
  public var dueDate: Patch<String>
  public var estimatedMinutes: Patch<UInt32>
  public var tags: [String]?
  public var body: Patch<String>
  public var rawInput: Patch<String>
  public var aiNotes: Patch<String>
  public var dependsOn: [String]?
  public var reminders: [String]?
  public var recurrenceJson: Patch<String>
  public var plannedDate: Patch<String>
  public var availableFrom: Patch<String>
  public var completed: Bool?
  /// Optional initial status. ``Patch/unset`` / ``Patch/clear`` → ``open``.
  /// The only other accepted value is ``someday``; any other value is rejected
  /// with a typed validation error.
  public var status: Patch<String>

  public init(
    title: String,
    listId: Patch<String> = .unset,
    priority: Patch<UInt8> = .unset,
    dueDate: Patch<String> = .unset,
    estimatedMinutes: Patch<UInt32> = .unset,
    tags: [String]? = nil,
    body: Patch<String> = .unset,
    rawInput: Patch<String> = .unset,
    aiNotes: Patch<String> = .unset,
    dependsOn: [String]? = nil,
    reminders: [String]? = nil,
    recurrenceJson: Patch<String> = .unset,
    plannedDate: Patch<String> = .unset,
    availableFrom: Patch<String> = .unset,
    completed: Bool? = nil,
    status: Patch<String> = .unset
  ) {
    self.title = title
    self.listId = listId
    self.priority = priority
    self.dueDate = dueDate
    self.estimatedMinutes = estimatedMinutes
    self.tags = tags
    self.body = body
    self.rawInput = rawInput
    self.aiNotes = aiNotes
    self.dependsOn = dependsOn
    self.reminders = reminders
    self.recurrenceJson = recurrenceJson
    self.plannedDate = plannedDate
    self.availableFrom = availableFrom
    self.completed = completed
    self.status = status
  }

  /// Canonical field set accepted by this input, used by repo-governance
  /// tests that pin every write surface to the same wire shape across create
  /// and update.
  public static let fields: [String] = [
    "title", "list_id", "priority", "due_date",
    "estimated_minutes", "tags", "body", "raw_input", "ai_notes",
    "depends_on", "reminders", "recurrence_json", "planned_date",
    "available_from", "completed", "status",
  ]
}

/// Top-level argument for ``TaskCreate/createTask(_:hlc:input:deviceId:)``.
public struct CreateTaskInput: Sendable {
  public var id: String?
  public var task: TaskCreateInput
  public var includeAdvice: Bool

  public init(id: String? = nil, task: TaskCreateInput, includeAdvice: Bool = false) {
    self.id = id
    self.task = task
    self.includeAdvice = includeAdvice
  }
}

public struct CreateTaskSpawnedSuccessor: Sendable {
  public let successorId: TaskId
  public let summary: String
  public let afterTask: JSONValue
}

public struct CreateTaskFocusRewireAudit: Sendable {
  public let parentTaskId: TaskId
  public let successorId: TaskId
  public let focusScheduleDates: [String]
  public let currentFocusDates: [String]
}

/// Sync-effect accumulator for the task-create flow. Every consumer surface
/// drives this envelope into its outbox enqueue path.
public struct CreateTaskSyncEffects: Sendable {
  public var taskUpsertIds: [String] = []
  public var reminderUpsertIds: [String] = []
  public var cancelledReminderIds: [String] = []
  public var dependencyEdgeUpsertIds: [String] = []
  public var tagUpsertIds: [String] = []
  public var taskTagEdgeUpsertIds: [String] = []
  public var spawnedSuccessors: [CreateTaskSpawnedSuccessor] = []
  public var spawnedSuccessorTagEdges: [CopiedTagEdge] = []
  public var spawnedSuccessorChecklistItemIds: [String] = []
  public var spawnedSuccessorReminderIds: [String] = []
  public var focusRewireAudits: [CreateTaskFocusRewireAudit] = []
  public var rewiredFocusScheduleDates: [String] = []
  public var rewiredCurrentFocusDates: [String] = []

  public init() {}
}

/// Tag-edge fan-out sub-effect. Returned by ``TaskCreateChildInserts/insertTaskTags``.
public struct TaskTagSyncEffects: Sendable {
  public var tagUpsertIds: [String] = []
  public var taskTagEdgeUpsertIds: [String] = []
  public init() {}
}

/// Result of a successful ``TaskCreate/createTask(_:hlc:input:deviceId:)``.
public struct CreateTaskResult: Sendable {
  public let taskId: TaskId
  public let task: JSONValue
  public let advice: [JSONValue]
  public let payload: JSONValue
  public let summary: String
  public let syncEffects: CreateTaskSyncEffects
}

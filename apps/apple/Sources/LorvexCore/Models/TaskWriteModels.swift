import Foundation
import LorvexDomain

public struct TaskCreateDraft: Equatable, Sendable {
  public var title: String
  public var notes: String
  public var listID: LorvexList.ID?
  public var priority: LorvexTask.Priority
  public var estimatedMinutes: Int?
  public var dueDate: Date?
  public var plannedDate: Date?
  /// The task's time on ``plannedDate`` in minutes since midnight; needs a
  /// planned date.
  public var plannedTime: Range<Int>?
  public var availableFrom: Date?
  public var tags: [String]?
  public var dependsOn: [LorvexTask.ID]?
  /// The user's verbatim original capture text, stored alongside the
  /// AI-parsed `title`/`notes`. `nil` records no raw capture.
  public var rawInput: String?
  /// How the task repeats. A repeating task needs a due day; without one the
  /// core uses the logical today as its first occurrence.
  public var recurrence: TaskRecurrenceRule?

  public init(
    title: String,
    notes: String = "",
    listID: LorvexList.ID? = nil,
    priority: LorvexTask.Priority = .p2,
    estimatedMinutes: Int? = nil,
    dueDate: Date? = nil,
    plannedDate: Date? = nil,
    plannedTime: Range<Int>? = nil,
    availableFrom: Date? = nil,
    tags: [String]? = nil,
    dependsOn: [LorvexTask.ID]? = nil,
    rawInput: String? = nil,
    recurrence: TaskRecurrenceRule? = nil
  ) {
    self.title = title
    self.notes = notes
    self.listID = listID
    self.priority = priority
    self.estimatedMinutes = estimatedMinutes
    self.dueDate = dueDate
    self.plannedDate = plannedDate
    self.plannedTime = plannedTime
    self.availableFrom = availableFrom
    self.tags = tags
    self.dependsOn = dependsOn
    self.rawInput = rawInput
    self.recurrence = recurrence
  }
}

public struct TaskUpdateDraft: Equatable, Sendable {
  public var id: LorvexTask.ID
  public var title: String?
  public var notes: String?
  public var listID: LorvexList.ID?
  public var priority: LorvexTask.Priority?
  public var estimatedMinutes: Patch<Int>
  public var dueDate: Patch<Date>
  public var plannedDate: Patch<Date>
  /// The task's time on its planned day, in minutes since midnight: `.set`
  /// needs a planned date, set in the same draft or already stored; `.clear`
  /// removes the time; `.unset` leaves it. A draft that moves the task to
  /// another day without setting a time clears the time.
  public var plannedTime: Patch<Range<Int>>
  public var availableFrom: Patch<Date>
  public var tags: [String]?
  public var dependsOn: [LorvexTask.ID]?
  /// Three-state patch for the verbatim `raw_input` capture column. `.unset`
  /// leaves it untouched, `.set` writes it, `.clear` nulls it. Consumed by the
  /// singular `updateTask(_:)` path (which surfaces `raw_input` in its tool
  /// schema); `batchUpdateTasks` leaves it `.unset`.
  public var rawInput: Patch<String>
  /// True clears the task's priority (`priority` is then ignored); false, the
  /// default, leaves it to `priority`, where nil means unchanged.
  public var clearsPriority: Bool

  public init(
    id: LorvexTask.ID,
    title: String? = nil,
    notes: String? = nil,
    listID: LorvexList.ID? = nil,
    priority: LorvexTask.Priority? = nil,
    estimatedMinutes: Patch<Int> = .unset,
    dueDate: Patch<Date> = .unset,
    plannedDate: Patch<Date> = .unset,
    plannedTime: Patch<Range<Int>> = .unset,
    availableFrom: Patch<Date> = .unset,
    tags: [String]? = nil,
    dependsOn: [LorvexTask.ID]? = nil,
    rawInput: Patch<String> = .unset,
    clearsPriority: Bool = false
  ) {
    self.id = id
    self.title = title
    self.notes = notes
    self.listID = listID
    self.priority = priority
    self.estimatedMinutes = estimatedMinutes
    self.dueDate = dueDate
    self.plannedDate = plannedDate
    self.plannedTime = plannedTime
    self.availableFrom = availableFrom
    self.tags = tags
    self.dependsOn = dependsOn
    self.rawInput = rawInput
    self.clearsPriority = clearsPriority
  }
}

public struct TaskBatchCancelByIdResult: Equatable, Sendable {
  public var cancelled: [LorvexTask]
  public var skipped: [LorvexTask.ID]

  public init(cancelled: [LorvexTask], skipped: [LorvexTask.ID]) {
    self.cancelled = cancelled
    self.skipped = skipped
  }
}

public struct TaskBatchLifecycleResult: Equatable, Sendable {
  public var snapshot: TodaySnapshot
  public var changedIDs: [LorvexTask.ID]
  /// The full mutated tasks, enriched and captured inside the same write
  /// transaction as the mutation (parallel to `changedIDs`). Callers return
  /// these directly instead of re-reading each id after commit, where a
  /// concurrent delete could drop a task the batch actually changed.
  public var changedTasks: [LorvexTask]
  public var skipped: [LorvexTask.ID]

  public init(
    snapshot: TodaySnapshot,
    changedIDs: [LorvexTask.ID],
    changedTasks: [LorvexTask] = [],
    skipped: [LorvexTask.ID]
  ) {
    self.snapshot = snapshot
    self.changedIDs = changedIDs
    self.changedTasks = changedTasks
    self.skipped = skipped
  }
}

public struct TaskBatchMoveResult: Equatable, Sendable {
  public var moved: [LorvexTask]
  /// Ids that matched no task, or whose move a newer stored version refused.
  public var skipped: [LorvexTask.ID]
  /// Tasks that were already in the target list, returned as they are.
  public var alreadyInList: [LorvexTask]

  public init(
    moved: [LorvexTask], skipped: [LorvexTask.ID], alreadyInList: [LorvexTask] = []
  ) {
    self.moved = moved
    self.skipped = skipped
    self.alreadyInList = alreadyInList
  }
}

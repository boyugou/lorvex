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
  public var availableFrom: Date?
  public var tags: [String]?
  public var dependsOn: [LorvexTask.ID]?
  /// The user's verbatim original capture text, stored alongside the
  /// AI-parsed `title`/`notes`. `nil` records no raw capture.
  public var rawInput: String?

  public init(
    title: String,
    notes: String = "",
    listID: LorvexList.ID? = nil,
    priority: LorvexTask.Priority = .p2,
    estimatedMinutes: Int? = nil,
    dueDate: Date? = nil,
    plannedDate: Date? = nil,
    availableFrom: Date? = nil,
    tags: [String]? = nil,
    dependsOn: [LorvexTask.ID]? = nil,
    rawInput: String? = nil
  ) {
    self.title = title
    self.notes = notes
    self.listID = listID
    self.priority = priority
    self.estimatedMinutes = estimatedMinutes
    self.dueDate = dueDate
    self.plannedDate = plannedDate
    self.availableFrom = availableFrom
    self.tags = tags
    self.dependsOn = dependsOn
    self.rawInput = rawInput
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
  public var availableFrom: Patch<Date>
  public var tags: [String]?
  public var dependsOn: [LorvexTask.ID]?
  /// Three-state patch for the verbatim `raw_input` capture column. `.unset`
  /// leaves it untouched, `.set` writes it, `.clear` nulls it. Consumed by the
  /// singular `updateTask(_:)` path (which surfaces `raw_input` in its tool
  /// schema); `batchUpdateTasks` leaves it `.unset`.
  public var rawInput: Patch<String>

  public init(
    id: LorvexTask.ID,
    title: String? = nil,
    notes: String? = nil,
    listID: LorvexList.ID? = nil,
    priority: LorvexTask.Priority? = nil,
    estimatedMinutes: Patch<Int> = .unset,
    dueDate: Patch<Date> = .unset,
    plannedDate: Patch<Date> = .unset,
    availableFrom: Patch<Date> = .unset,
    tags: [String]? = nil,
    dependsOn: [LorvexTask.ID]? = nil,
    rawInput: Patch<String> = .unset
  ) {
    self.id = id
    self.title = title
    self.notes = notes
    self.listID = listID
    self.priority = priority
    self.estimatedMinutes = estimatedMinutes
    self.dueDate = dueDate
    self.plannedDate = plannedDate
    self.availableFrom = availableFrom
    self.tags = tags
    self.dependsOn = dependsOn
    self.rawInput = rawInput
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
  public var skipped: [LorvexTask.ID]

  public init(moved: [LorvexTask], skipped: [LorvexTask.ID]) {
    self.moved = moved
    self.skipped = skipped
  }
}

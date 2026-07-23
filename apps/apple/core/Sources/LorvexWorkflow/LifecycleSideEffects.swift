import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Recurrence-spawn / successor-cancel return shape — what the
/// orchestrator needs from a real spawn implementation to assemble the
/// transition result.
public struct SpawnedRecurrenceSuccessor: Sendable, Equatable {
  public let successorId: String
  public let copiedTagEdges: [CopiedTagEdge]
  public let copiedChecklistItemIds: [String]
  public let copiedReminderIds: [String]
  public let rewiredFocusScheduleDates: [String]
  public let rewiredCurrentFocusDates: [String]

  public init(
    successorId: String,
    copiedTagEdges: [CopiedTagEdge],
    copiedChecklistItemIds: [String],
    copiedReminderIds: [String],
    rewiredFocusScheduleDates: [String],
    rewiredCurrentFocusDates: [String]
  ) {
    self.successorId = successorId
    self.copiedTagEdges = copiedTagEdges
    self.copiedChecklistItemIds = copiedChecklistItemIds
    self.copiedReminderIds = copiedReminderIds
    self.rewiredFocusScheduleDates = rewiredFocusScheduleDates
    self.rewiredCurrentFocusDates = rewiredCurrentFocusDates
  }
}

public struct SuccessorCancelOutcome: Sendable, Equatable {
  public let ids: [String]
  public let sideEffects: SuccessorCancelSideEffects

  public init(ids: [String], sideEffects: SuccessorCancelSideEffects) {
    self.ids = ids
    self.sideEffects = sideEffects
  }
}

/// Injection point for the recurrence-handling halves of the lifecycle
/// orchestrator: spawn-next-occurrence (on `→ completed` / non-series
/// `→ cancelled`) and cancel-recurring-successors (on `→ open` from
/// `completed`). Every entry point defaults to the production
/// ``LifecycleRecurrenceSpawnHandler``; the protocol keeps the seam
/// injectable so a caller can substitute an alternate handler.
public protocol RecurrenceSpawnHandler: Sendable {
  /// Spawn the next recurrence occurrence after `taskId` was
  /// completed-or-skip-cancelled. Returns `nil` when the rule resolves
  /// to "no more occurrences". The orchestrator only invokes this when
  /// `snapshot.recurrence` is non-nil and non-empty.
  func spawnRecurrenceSuccessor(
    _ db: Database,
    taskId: TaskId,
    snapshot: LifecycleTaskSnapshot,
    activeReminderTimes: [String],
    now: String,
    reminderVersion: String
  ) throws -> SpawnedRecurrenceSuccessor?

  /// Cancel the exact direct successor authorized by `taskId` (used when
  /// reopening a previously-terminal recurring parent). A successor that has
  /// itself advanced rejects the rewind rather than forking the chain.
  func cancelRecurringSuccessors(
    _ db: Database,
    taskId: TaskId,
    snapshot: LifecycleTaskSnapshot,
    now: String,
    reminderVersion: String
  ) throws -> SuccessorCancelOutcome
}

/// Internal input shape for ``LifecycleSideEffects/apply(_:input:handler:)``.
struct LifecycleSideEffectsInput {
  let taskId: TaskId
  let oldStatus: TaskStatus
  let newStatus: TaskStatus
  let now: String
  let reminderVersion: String
  let snapshot: LifecycleTaskSnapshot?
  let preTransitionActiveReminderTimes: [String]
}

/// Lifecycle side-effect orchestration: data-layer changes (reminders /
/// deps via ``StatusSideEffects``), recurrence spawn on completion or
/// skip-cancel, successor cancellation on reopen-from-completed.
enum LifecycleSideEffects {
  /// Apply lifecycle side effects WITHOUT writing the status column.
  static func apply(
    _ db: Database,
    input: LifecycleSideEffectsInput,
    handler: RecurrenceSpawnHandler
  ) throws -> LifecycleTransitionResult {
    let sideEffects = try StatusSideEffects.applyStatusTransitionSideEffects(
      db, taskId: input.taskId,
      oldStatus: input.oldStatus, newStatus: input.newStatus,
      now: input.now, reminderVersion: input.reminderVersion)

    var spawnedSuccessorId: String? = nil
    var spawnedTagEdges: [CopiedTagEdge] = []
    var spawnedChecklistItemIds: [String] = []
    var spawnedReminderIds: [String] = []
    var rewiredFocusScheduleDates: [String] = []
    var rewiredCurrentFocusDates: [String] = []
    var cancelledSuccessorIds: [String] = []
    var successorCancelSideEffects: SuccessorCancelSideEffects = .empty

    let becameCompleted =
      input.newStatus == .completed && input.oldStatus != .completed
    let becameCancelled =
      input.newStatus == .cancelled && input.oldStatus != .cancelled

    // Recurrence spawn on completion or skip-cancel.
    if becameCompleted || becameCancelled {
      if let snap = input.snapshot,
        let rule = snap.recurrence, !rule.isEmpty
      {
        if let spawn = try handler.spawnRecurrenceSuccessor(
          db, taskId: input.taskId, snapshot: snap,
          activeReminderTimes: input.preTransitionActiveReminderTimes,
          now: input.now, reminderVersion: input.reminderVersion)
        {
          spawnedSuccessorId = spawn.successorId
          spawnedTagEdges = spawn.copiedTagEdges
          spawnedChecklistItemIds = spawn.copiedChecklistItemIds
          spawnedReminderIds = spawn.copiedReminderIds
          rewiredFocusScheduleDates = spawn.rewiredFocusScheduleDates
          rewiredCurrentFocusDates = spawn.rewiredCurrentFocusDates
        }
      }
    }

    // Any terminal → nonterminal transition rewinds the same direct successor.
    if input.newStatus.isActive && input.oldStatus.isTerminal {
      if let snap = input.snapshot, snap.recurrence != nil {
        let outcome = try handler.cancelRecurringSuccessors(
          db, taskId: input.taskId, snapshot: snap,
          now: input.now, reminderVersion: input.reminderVersion)
        cancelledSuccessorIds = outcome.ids
        successorCancelSideEffects = outcome.sideEffects
        rewiredFocusScheduleDates.append(
          contentsOf: outcome.sideEffects.rewiredFocusScheduleDates)
        rewiredCurrentFocusDates.append(
          contentsOf: outcome.sideEffects.rewiredCurrentFocusDates)
      }
    }

    return LifecycleTransitionResult(
      sideEffects: sideEffects,
      spawnedSuccessorId: spawnedSuccessorId,
      spawnedSuccessorTagEdges: spawnedTagEdges,
      spawnedSuccessorChecklistItemIds: spawnedChecklistItemIds,
      spawnedSuccessorReminderIds: spawnedReminderIds,
      cancelledSuccessorIds: cancelledSuccessorIds,
      successorCancelSideEffects: successorCancelSideEffects,
      rewiredFocusScheduleDates: rewiredFocusScheduleDates,
      rewiredCurrentFocusDates: rewiredCurrentFocusDates)
  }

  /// The empty side-effect result used by no-op orchestrator paths
  /// (e.g. reopen that did not actually flip the row).
  static var emptyResult: LifecycleTransitionResult {
    LifecycleTransitionResult(
      sideEffects: StatusSideEffects.Result(
        cancelledReminderIds: [],
        affectedDependentIds: [],
        deletedDependencyEdges: []),
      spawnedSuccessorId: nil,
      spawnedSuccessorTagEdges: [],
      spawnedSuccessorChecklistItemIds: [],
      spawnedSuccessorReminderIds: [],
      cancelledSuccessorIds: [],
      successorCancelSideEffects: .empty,
      rewiredFocusScheduleDates: [],
      rewiredCurrentFocusDates: [])
  }
}

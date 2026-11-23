import Foundation
import LorvexDomain

/// Shared recurrence-config transition planner.
///
/// Every write surface that creates or modifies recurrence must route
/// through this planner. It is the single semantic owner of the invariant:
///
/// ```text
/// recurrence IS NULL
/// OR (due_date IS NOT NULL AND recurrence_group_id IS NOT NULL
///     AND canonical_occurrence_date IS NOT NULL)
///
/// recurrence_instance_key IS NULL
/// OR (recurrence_group_id IS NOT NULL AND canonical_occurrence_date IS NOT NULL
///     AND recurrence_instance_key = recurrence_group_id || ':' || canonical_occurrence_date)
/// ```
///
/// The instance key is the natural identity of a generated occurrence, so it
/// leaves with its group id and follows its occurrence date.
///
/// The planner classifies each recurrence change into one of four
/// transitions and outputs the exact column actions needed. Surfaces apply
/// these actions in their SQL UPDATE/INSERT — they do not invent recurrence
/// logic locally.
///
/// The LWW-gated DB applier lives in `RecurrenceConfigApply.swift`; callers
/// that need persistence should use that shared boundary instead of applying
/// the planner output by hand.
public enum RecurrenceConfig {
  /// What kind of recurrence-config change is happening.
  public enum Transition: Equatable, Sendable {
    case enable
    case updateRule
    case disable
    case noChange
  }

  /// Column-level actions the planner emits for the caller to apply.
  public struct ColumnActions: Equatable, Sendable {
    public var setRecurrenceGroupId: String?
    public var setCanonicalOccurrenceDate: Patch<String>
    public var setDueDate: String?
    /// The planned day a task takes when its series starts today because the
    /// day it was planned for has passed. A successor keeps its parent's
    /// distance between planned day and occurrence, so a plan left in the past
    /// would put every later occurrence on a day before it is due.
    public var setPlannedDate: String?
    public var clearRecurrenceGroupId: Bool
    public var clearCanonicalOccurrenceDate: Bool
    /// Clears the generated occurrence's instance key, which cannot outlive the
    /// group id and occurrence date it is made of.
    public var clearRecurrenceInstanceKey: Bool
    public var clearRecurrenceExceptions: Bool

    public init(
      setRecurrenceGroupId: String? = nil,
      setCanonicalOccurrenceDate: Patch<String> = .unset,
      setDueDate: String? = nil,
      setPlannedDate: String? = nil,
      clearRecurrenceGroupId: Bool = false,
      clearCanonicalOccurrenceDate: Bool = false,
      clearRecurrenceInstanceKey: Bool = false,
      clearRecurrenceExceptions: Bool = false
    ) {
      self.setRecurrenceGroupId = setRecurrenceGroupId
      self.setCanonicalOccurrenceDate = setCanonicalOccurrenceDate
      self.setDueDate = setDueDate
      self.setPlannedDate = setPlannedDate
      self.clearRecurrenceGroupId = clearRecurrenceGroupId
      self.clearCanonicalOccurrenceDate = clearCanonicalOccurrenceDate
      self.clearRecurrenceInstanceKey = clearRecurrenceInstanceKey
      self.clearRecurrenceExceptions = clearRecurrenceExceptions
    }
  }

  /// Current recurrence state of a task (read from DB before applying).
  public struct State: Equatable, Sendable {
    public var recurrence: String?
    public var recurrenceGroupId: String?
    public var canonicalOccurrenceDate: String?
    /// Set on a generated occurrence, nil on a task the user made recurring.
    public var recurrenceInstanceKey: String?
    public var dueDate: String?
    /// The day the task is planned for, which a task with no due date starts
    /// its series on (``firstOccurrenceDate(dueDate:plannedDate:today:)``).
    public var plannedDate: String?

    public init(
      recurrence: String? = nil, recurrenceGroupId: String? = nil,
      canonicalOccurrenceDate: String? = nil, recurrenceInstanceKey: String? = nil,
      dueDate: String? = nil, plannedDate: String? = nil
    ) {
      self.recurrence = recurrence
      self.recurrenceGroupId = recurrenceGroupId
      self.canonicalOccurrenceDate = canonicalOccurrenceDate
      self.recurrenceInstanceKey = recurrenceInstanceKey
      self.dueDate = dueDate
      self.plannedDate = plannedDate
    }
  }

  /// The date a task's series starts on when the task becomes recurring: its
  /// due date; with none, the day it is planned for when that is today or
  /// later; otherwise today. A plan for a day that has passed is not a start
  /// date: the task is on today, so its series starts today and the plan moves
  /// to today with it (``ColumnActions/setPlannedDate``).
  public static func firstOccurrenceDate(
    dueDate: String?, plannedDate: String?, today: String
  ) -> String {
    if let dueDate { return dueDate }
    if let plannedDate, plannedDate >= today { return plannedDate }
    return today
  }

  /// Plan the recurrence-config transition given old state and the new
  /// recurrence value. `newRecurrence == nil` (or empty) clears recurrence.
  /// On Enable the series starts on
  /// ``firstOccurrenceDate(dueDate:plannedDate:today:)``, which also becomes
  /// the due date of a task that has none; `today` is the timezone-aware today
  /// string.
  public static func planRecurrenceTransition(
    old: State, newRecurrence: String?, today: String
  ) -> (Transition, ColumnActions) {
    let oldHasRecurrence = !(old.recurrence ?? "").isEmpty
    let newHasRecurrence = !(newRecurrence ?? "").isEmpty

    if !oldHasRecurrence && newHasRecurrence {
      let anchor = firstOccurrenceDate(
        dueDate: old.dueDate, plannedDate: old.plannedDate, today: today)
      let planHasPassed = old.dueDate == nil && (old.plannedDate.map { $0 < today } ?? false)
      let actions = ColumnActions(
        setRecurrenceGroupId: EntityID.newEntityIDString(),
        setCanonicalOccurrenceDate: .set(anchor),
        setDueDate: old.dueDate == nil ? anchor : nil,
        setPlannedDate: planHasPassed ? anchor : nil)
      return (.enable, actions)
    } else if oldHasRecurrence && newHasRecurrence {
      // UpdateRule: change rule, keep series identity and anchor; clear
      // exceptions because old EXDATE dates may not be valid occurrences
      // of the new rule.
      return (.updateRule, ColumnActions(clearRecurrenceExceptions: true))
    } else if oldHasRecurrence && !newHasRecurrence {
      // Disable: end the active series.
      return (
        .disable,
        ColumnActions(
          clearRecurrenceGroupId: true,
          clearCanonicalOccurrenceDate: true,
          clearRecurrenceInstanceKey: true,
          clearRecurrenceExceptions: true)
      )
    } else {
      return (.noChange, ColumnActions())
    }
  }

}

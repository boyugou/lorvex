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
/// ```
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
    public var clearRecurrenceGroupId: Bool
    public var clearCanonicalOccurrenceDate: Bool
    public var clearRecurrenceExceptions: Bool

    public init(
      setRecurrenceGroupId: String? = nil,
      setCanonicalOccurrenceDate: Patch<String> = .unset,
      setDueDate: String? = nil,
      clearRecurrenceGroupId: Bool = false,
      clearCanonicalOccurrenceDate: Bool = false,
      clearRecurrenceExceptions: Bool = false
    ) {
      self.setRecurrenceGroupId = setRecurrenceGroupId
      self.setCanonicalOccurrenceDate = setCanonicalOccurrenceDate
      self.setDueDate = setDueDate
      self.clearRecurrenceGroupId = clearRecurrenceGroupId
      self.clearCanonicalOccurrenceDate = clearCanonicalOccurrenceDate
      self.clearRecurrenceExceptions = clearRecurrenceExceptions
    }
  }

  /// Current recurrence state of a task (read from DB before applying).
  public struct State: Equatable, Sendable {
    public var recurrence: String?
    public var recurrenceGroupId: String?
    public var canonicalOccurrenceDate: String?
    public var dueDate: String?

    public init(
      recurrence: String? = nil, recurrenceGroupId: String? = nil,
      canonicalOccurrenceDate: String? = nil, dueDate: String? = nil
    ) {
      self.recurrence = recurrence
      self.recurrenceGroupId = recurrenceGroupId
      self.canonicalOccurrenceDate = canonicalOccurrenceDate
      self.dueDate = dueDate
    }
  }

  /// Plan the recurrence-config transition given old state and the new
  /// recurrence value. `newRecurrence == nil` (or empty) clears recurrence;
  /// `today` is the timezone-aware today string used as the anchor fallback
  /// when due_date is missing on Enable.
  public static func planRecurrenceTransition(
    old: State, newRecurrence: String?, today: String
  ) -> (Transition, ColumnActions) {
    let oldHasRecurrence = !(old.recurrence ?? "").isEmpty
    let newHasRecurrence = !(newRecurrence ?? "").isEmpty

    if !oldHasRecurrence && newHasRecurrence {
      let anchor = old.dueDate ?? today
      let actions = ColumnActions(
        setRecurrenceGroupId: EntityID.newEntityIDString(),
        setCanonicalOccurrenceDate: .set(anchor),
        setDueDate: old.dueDate == nil ? anchor : nil)
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
          clearRecurrenceExceptions: true)
      )
    } else {
      return (.noChange, ColumnActions())
    }
  }

}

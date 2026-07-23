import Foundation

public enum EventKitCalendarFilterMode: String, CaseIterable, Sendable {
  case allExcept
  case onlySelected
}

/// Calendar-level allow/deny rules for EventKit ingestion.
///
/// Two shapes, distinguished by `restrictsToIncluded`:
/// - **all-except** (`restrictsToIncluded == false`): mirror every calendar
///   except `excludedCalendarIDs`. An empty exclude set mirrors all.
/// - **only-selected** (`restrictsToIncluded == true`): mirror only
///   `includedCalendarIDs`. An empty include set mirrors *nothing*.
///
/// The discriminator exists because both shapes can present an empty include
/// set, yet mean opposite things: all-except-with-no-exclusions mirrors
/// everything, while only-selected-with-no-selection mirrors nothing. Collapsing
/// them (treating any empty include set as "all") is a privacy footgun — a user
/// who deselects their last calendar in only-selected mode would silently start
/// mirroring every calendar.
///
/// `excludedCalendarIDs` always wins over the include set. A nil/empty calendar
/// identifier is allowed only in the all-except shape, since it cannot match an
/// allow-list entry.
public struct EventKitCalendarFilter: Sendable, Equatable {
  public static let all = EventKitCalendarFilter(includedCalendarIDs: [], excludedCalendarIDs: [])

  public let includedCalendarIDs: Set<String>
  public let excludedCalendarIDs: Set<String>
  /// `true` for the only-selected shape (mirror only `includedCalendarIDs`; an
  /// empty set mirrors nothing); `false` for all-except (mirror all but
  /// `excludedCalendarIDs`).
  public let restrictsToIncluded: Bool

  /// Allow-list/deny-list constructor. A non-empty include set is the
  /// only-selected shape; an empty include set is the all-except shape. This
  /// constructor cannot express an empty only-selected filter — use the
  /// `mode:`-based initializer for that.
  public init(includedCalendarIDs: Set<String>, excludedCalendarIDs: Set<String>) {
    let included = includedCalendarIDs.filter { !$0.isEmpty }
    self.includedCalendarIDs = included
    self.excludedCalendarIDs = excludedCalendarIDs.filter { !$0.isEmpty }
    self.restrictsToIncluded = !included.isEmpty
  }

  public init(
    mode: EventKitCalendarFilterMode,
    selectedCalendarIDs: Set<String>,
    excludedCalendarIDs: Set<String>
  ) {
    switch mode {
    case .allExcept:
      self.includedCalendarIDs = []
      self.excludedCalendarIDs = excludedCalendarIDs.filter { !$0.isEmpty }
      self.restrictsToIncluded = false
    case .onlySelected:
      self.includedCalendarIDs = selectedCalendarIDs.filter { !$0.isEmpty }
      self.excludedCalendarIDs = []
      self.restrictsToIncluded = true
    }
  }

  /// `true` only when the filter mirrors every calendar (all-except with an
  /// empty exclude set). An empty only-selected filter is *not* default — it
  /// mirrors nothing.
  public var isDefault: Bool {
    !restrictsToIncluded && excludedCalendarIDs.isEmpty
  }

  public func allows(calendarID: String?) -> Bool {
    guard let calendarID, !calendarID.isEmpty else {
      return !restrictsToIncluded
    }
    if excludedCalendarIDs.contains(calendarID) { return false }
    if restrictsToIncluded { return includedCalendarIDs.contains(calendarID) }
    return true
  }
}

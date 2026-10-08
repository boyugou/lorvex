import LorvexCore
import SwiftUI

/// One page of the Day and Week pager: the time grid (``MobileCalendarDayColumn``)
/// for the days that begin on a start date.
///
/// The pager lists every page in its range and gives a column only to the
/// pages near the visible one (``MobileLivePages``); any other page is an
/// empty placeholder. SwiftUI re-evaluates a page whose inputs changed, and a
/// column carries closures it cannot compare, so the page compares its data
/// ``Inputs`` instead and builds the column only when its body runs. A page
/// whose days, events, and tasks are unchanged is skipped when the pager
/// re-evaluates for another page's sake.
struct MobileCalendarDayPage: View, Equatable {
  /// Everything but the closures that decides what the column draws. Two
  /// pages with equal inputs draw the same column.
  struct Inputs: Equatable, Sendable {
    /// The first day the page shows.
    let startDate: Date
    /// The days the page shows: 1, 2, 3, or 7.
    let dayCount: Int
    /// Whether each day column has its own header.
    let showsHeaders: Bool
    /// Whether the headers circle today's date.
    let circlesTodayInHeaders: Bool
    /// Whether a day's header opens that day.
    let opensDays: Bool
    /// The window's events, narrowed by the calendar search.
    let events: [CalendarTimelineEvent]
    /// The window's scheduled tasks.
    let tasks: [LorvexTask]
    let calendar: Calendar
  }

  /// The column's inputs, or nil for a page that holds no column.
  let inputs: Inputs?
  /// Builds the column; set exactly when `inputs` is.
  private let makeColumn: (@MainActor () -> MobileCalendarDayColumn)?

  /// A page that holds a column.
  init(inputs: Inputs, makeColumn: @escaping @MainActor () -> MobileCalendarDayColumn) {
    self.inputs = inputs
    self.makeColumn = makeColumn
  }

  /// A page that holds no column.
  init() {
    inputs = nil
    makeColumn = nil
  }

  nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.inputs == rhs.inputs
  }

  var body: some View {
    if let makeColumn, inputs != nil {
      makeColumn()
    } else {
      Color.clear
    }
  }
}

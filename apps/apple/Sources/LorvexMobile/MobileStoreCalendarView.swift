import LorvexCore
import SwiftUI

/// Full-screen Calendar workspace for iPhone/iPad, in the mode the store
/// holds: the phone-native time-axis grid (`MobileCalendarDayView`) with
/// width-adaptive 1/2/3 days in Day mode and seven days in Week mode, or the
/// month grid over the chosen day's agenda (`MobileCalendarMonthView`). The
/// segmented mode picker lives in each mode's toolbar, and every mode reads
/// the same `store.calendarTimeline` fetch path.
@MainActor
public struct MobileStoreCalendarView: View {
  @Bindable var store: MobileStore
  @State private var searchQuery = ""

  public init(store: MobileStore) {
    self.store = store
  }

  public var body: some View {
    Group {
      switch store.calendarPresentationMode {
      case .week:
        MobileCalendarDayView(store: store, weekMode: true, searchQuery: searchQuery)
      case .grid:
        MobileCalendarDayView(store: store, searchQuery: searchQuery)
      case .month:
        MobileCalendarMonthView(store: store, searchQuery: searchQuery)
      }
    }
    // Event search narrows the visible grid to events matching title,
    // location, or notes — the mobile counterpart to the macOS calendar filter.
    .searchable(
      text: $searchQuery,
      prompt: String(
        localized: "calendar.search.prompt", defaultValue: "Search events", table: "Localizable",
        bundle: MobileL10n.bundle))
    // Folded into a toolbar glyph until tapped: the grid already stacks its
    // header row (and in Day mode a week strip, in Month mode the weekday
    // names) under the navigation bar, and a full search field on top of them
    // pushed the first hour of the day below the fold. The minimized behavior
    // exists on iOS only.
    #if os(iOS)
      .searchToolbarBehavior(.minimize)
    #endif
  }
}

import LorvexCore
import SwiftUI

/// Full-screen Calendar workspace for iPhone/iPad, in the mode the store
/// holds: the phone-native time-axis grid (`MobileCalendarDayView`) with
/// width-adaptive 1/2/3 days in Day mode and seven days in Week mode, or the
/// month grid over the chosen day's agenda (`MobileCalendarMonthView`). The
/// segmented mode picker lives in each mode's toolbar, and every mode reads
/// the same `store.calendarTimeline` fetch path. While the search field holds
/// text, the events it finds on any date list over the grid
/// (`MobileCalendarSearchResults`).
@MainActor
public struct MobileStoreCalendarView: View {
  @Bindable var store: MobileStore
  @State private var searchQuery = ""

  public init(store: MobileStore) {
    self.store = store
  }

  private var isSearching: Bool {
    !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  public var body: some View {
    Group {
      switch store.calendarPresentationMode {
      case .week:
        MobileCalendarDayView(store: store, weekMode: true)
      case .grid:
        MobileCalendarDayView(store: store)
      case .month:
        MobileCalendarMonthView(store: store)
      }
    }
    // The grid stays in the hierarchy under the results, so the day it shows
    // and its scroll position are still there when the search closes; it is
    // hidden from VoiceOver while the results cover it.
    .accessibilityHidden(isSearching)
    .overlay {
      if isSearching {
        MobileCalendarSearchResults(store: store, query: searchQuery, calendar: .current)
      }
    }
    // An iPad keeps the mode picker in the bar beside the open search field;
    // choosing a mode leaves the search for that mode instead of changing a grid
    // the results cover.
    .onChange(of: store.calendarPresentationMode) { searchQuery = "" }
    // Event search finds events by title, location, or notes on any date, as
    // the macOS Calendar workspace's search does.
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

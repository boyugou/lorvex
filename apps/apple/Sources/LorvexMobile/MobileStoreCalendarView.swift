import LorvexCore
import SwiftUI

/// Full-screen Calendar workspace for iPhone/iPad. Renders the phone-native
/// time-axis grid (`MobileCalendarDayView`): width-adaptive 1/2/3 days in Day
/// mode, seven days in Week mode; the segmented toggle lives in that view's
/// toolbar. Both modes read the same `store.calendarTimeline` fetch path.
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
      }
    }
    // Event search narrows the visible day grid to events matching title,
    // location, or notes — the mobile counterpart to the macOS calendar filter.
    .searchable(
      text: $searchQuery,
      prompt: String(
        localized: "calendar.search.prompt", defaultValue: "Search events", table: "Localizable",
        bundle: MobileL10n.bundle))
    // Folded into a toolbar glyph until tapped: the grid already stacks its
    // header row (and in Day mode a week strip) under the navigation bar, and
    // a full search field on top of them pushed the first hour of the day
    // below the fold. The minimized behavior exists on iOS only.
    #if os(iOS)
      .searchToolbarBehavior(.minimize)
    #endif
  }
}

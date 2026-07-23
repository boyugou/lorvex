import LorvexCore
import SwiftUI

/// Full-screen Calendar workspace for iPhone/iPad. Renders the phone-native
/// adaptive time-axis grid (`MobileCalendarDayView`) in Day mode and a grouped
/// seven-day agenda in Week mode; the segmented toggle lives in that view's
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
  }
}

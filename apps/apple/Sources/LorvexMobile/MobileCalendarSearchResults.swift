import LorvexCore
import SwiftUI

/// What the Calendar tab shows while its search field holds text: the events
/// the text finds on any date, in the agenda's list of days
/// (``MobileCalendarAgendaDay/searchResults(_:todayKey:calendar:)``), so a
/// match is found wherever it falls instead of on whichever day the grid
/// happens to show. An event row opens its editor, and its context menu edits
/// or deletes it, as in the agenda. The list covers the grid without replacing
/// it, so closing the search returns to the day, week, or month the person
/// left.
struct MobileCalendarSearchResults: View {
  @Bindable var store: MobileStore
  /// The search field's text.
  let query: String
  let calendar: Calendar

  @State private var days: [MobileCalendarAgendaDay] = []
  @State private var isLoading = true
  @State private var editingEvent: CalendarTimelineEvent?

  var body: some View {
    content
      .mobileReadableWidth()
      // The agenda's plain list is clear so it can continue a grid's surface;
      // here it must hide the grid under it.
      .background(.background)
      .scrollDismissesKeyboard(.interactively)
      .accessibilityIdentifier("mobileCalendar.searchResults")
      .task(id: query) {
        isLoading = true
        guard await LorvexSearchDebounce.shouldSearch(query) else { return }
        await reload()
        // A newer query cancels this one without awaiting it; the flag then
        // belongs to the newer query.
        guard !Task.isCancelled else { return }
        isLoading = false
      }
      // An edit or delete from the list, or from the editor it opens, changes
      // what the query finds.
      .onChange(of: store.isMutatingCalendarEvent) { _, isMutating in
        if !isMutating { Task { await reload() } }
      }
      .sheet(item: $editingEvent) { event in
        MobileStoreEditCalendarEventSheet(
          event: event,
          store: store,
          // A constant-true getter, as in the day view: deriving it from
          // `editingEvent`, which `.sheet(item:)` already owns, double-dismisses.
          isPresented: Binding(
            get: { true },
            set: { if !$0 { editingEvent = nil } }
          )
        )
      }
  }

  @ViewBuilder
  private var content: some View {
    if days.isEmpty {
      List {
        if isLoading {
          MobileSkeletonRows(count: 5)
        } else {
          MobileEmptyState.search(text: query)
            .listRowSeparator(.hidden)
        }
      }
      .listStyle(.plain)
    } else {
      MobileStoreCalendarAgenda(
        store: store, days: days, calendar: calendar, placement: .under,
        editEvent: { editingEvent = $0 })
    }
  }

  /// Reads the results for the current `query` into `days`. A reply for a
  /// query the field has since moved past is dropped, so a slow search never
  /// overwrites a newer one.
  private func reload() async {
    let asked = query
    let found = await store.searchCalendarAgenda(matching: asked, calendar: calendar)
    guard asked == query else { return }
    days = found
  }
}

import LorvexCore
import SwiftUI

/// What the Calendar workspace shows in place of its grid while the toolbar
/// search field holds text: the events the text finds on any date, by day
/// (``CalendarSearchDay``), so a match is found wherever it falls instead of
/// on whichever period the grid happens to show. An event row is the row
/// Today's schedule uses (``TodayEventRow``). Clicking it opens the event in
/// the inspector and moves the grid to the event's day, so clearing the
/// search lands on it; its context menu opens details, edits, or deletes it,
/// as on the grid. The grid stays in the hierarchy under the results, so its
/// period and scroll position are still there when the search clears.
///
/// The list reads from the core, not from the loaded window, and reads again
/// each time the timeline loads, which follows every event create, edit, and
/// delete.
struct CalendarSearchResultsView: View {
  @Bindable var store: AppStore
  let calendar: Calendar
  /// Opens the event in the inspector and moves the grid to its day.
  let reveal: (CalendarTimelineEvent) -> Void
  let edit: (CalendarTimelineEvent) -> Void
  let requestDelete: (CalendarTimelineEvent) -> Void

  @State private var days: [CalendarSearchDay] = []
  @State private var isLoading = true

  /// The widest the list grows, so a row's title and time stay a line apart
  /// in a wide window.
  private static let columnWidth: CGFloat = 720

  var body: some View {
    // The surface is a view of its own, so it covers the grid while the first
    // reply is on its way and `content` is still empty.
    ZStack {
      Rectangle().fill(.background)
      content
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("calendar.searchResults")
    .task(id: store.searchText) {
      isLoading = true
      guard await LorvexSearchDebounce.shouldSearch(store.searchText) else { return }
      await reload()
      // A newer query cancels this one without awaiting it; the flag then
      // belongs to the newer query.
      guard !Task.isCancelled else { return }
      isLoading = false
    }
    .onChange(of: store.calendarTimelineLoadToken) {
      Task { await reload() }
    }
  }

  @ViewBuilder
  private var content: some View {
    if !days.isEmpty {
      results
    } else if !isLoading {
      LorvexEmptyStatePanel(model: emptyState)
    }
  }

  private var results: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0) {
        ForEach(days) { day in
          dayLabel(day)
          ForEach(day.events) { event in
            row(event, on: day)
          }
        }
      }
      .frame(maxWidth: Self.columnWidth)
      .padding(.horizontal, LorvexDesign.Spacing.l)
      .padding(.vertical, LorvexDesign.Spacing.m)
      .frame(maxWidth: .infinity)
    }
  }

  /// A day's name followed by its date, in the page-label style.
  private func dayLabel(_ day: CalendarSearchDay) -> some View {
    let date = PlannedDayBridge.displayDate(forLogicalDay: day.key, timeZone: calendar.timeZone)
    return HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.sm) {
      Text(dayTitle(day, date: date))
      if let date {
        Text(dateLine(date)).fontWeight(.regular).monospacedDigit()
      }
    }
    .font(LorvexDesign.Typography.pageLabel)
    .foregroundStyle(.secondary)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, LorvexDesign.Spacing.s)
    .padding(.top, LorvexDesign.Spacing.m)
    .padding(.bottom, LorvexDesign.Spacing.xxs)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isHeader)
  }

  private func row(_ event: CalendarTimelineEvent, on day: CalendarSearchDay) -> some View {
    TodayEventRow(
      event: event,
      timeLabel: event.listTimeLabel(on: day.key, range: TodayCalmCopy.timeRange)
        ?? TodayCalmCopy.allDay,
      isPast: day.key < store.logicalTodayDateString,
      isSelected: store.isCalendarEventSelected(event),
      identifier: "calendar.searchResults.event.\(event.id)",
      open: { reveal(event) }
    )
    .contextMenu {
      CalendarEventContextMenu(
        event: event, select: reveal, edit: edit, requestDelete: requestDelete)
    }
  }

  /// "Today" on the logical today, else the weekday.
  private func dayTitle(_ day: CalendarSearchDay, date: Date?) -> String {
    if day.key == store.logicalTodayDateString {
      return String(
        localized: "calendar.nav.today", defaultValue: "Today", table: "Localizable",
        bundle: LorvexL10n.bundle)
    }
    guard let date else { return day.key }
    return LorvexDateFormatters.string(
      date, template: "EEEE", timeZone: calendar.timeZone, position: .leading)
  }

  /// The day's date, with the year outside the current year.
  private func dateLine(_ date: Date) -> String {
    calendar.isDate(date, equalTo: Date(), toGranularity: .year)
      ? LorvexDateFormatters.string(date, template: "MMMd", timeZone: calendar.timeZone)
      : LorvexDateFormatters.string(date, dateStyle: .medium, timeZone: calendar.timeZone)
  }

  private var emptyState: LorvexEmptyStateModel {
    LorvexEmptyStateModel(
      title: String(
        format: String(
          localized: "calendar.search.empty_title", defaultValue: "No Results for “%@”",
          table: "Localizable", bundle: LorvexL10n.bundle),
        store.trimmedSearchText),
      message: String(
        localized: "calendar.search.empty_message",
        defaultValue: "Check the spelling or try a different search.",
        table: "Localizable", bundle: LorvexL10n.bundle),
      systemImage: "magnifyingglass",
      tint: .secondary,
      action: LorvexEmptyStateAction(
        title: String(
          localized: "common.clear_search", defaultValue: "Clear Search", table: "Localizable",
          bundle: LorvexL10n.bundle),
        systemImage: "xmark.circle"
      ) {
        store.searchText = ""
      }
    )
  }

  /// Reads the results for the current search text into `days`. A reply for
  /// text the field has since moved past is dropped, so a slow search never
  /// overwrites a newer one.
  private func reload() async {
    let asked = store.searchText
    let found = await store.searchCalendarDays(matching: asked)
    guard asked == store.searchText else { return }
    days = found
  }
}

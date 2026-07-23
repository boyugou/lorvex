import LorvexCore
import SwiftUI

/// Phone-native calendar: a vertical time-axis day view (hour gutter on the
/// left, events as lane-packed blocks, all-day strip on top, live now-line)
/// with horizontal swipe between days. A compact week strip + date picker jump
/// to any day. On wide layouts (landscape / Plus) it shows a 3-day variant.
///
/// Reuses the hoisted pure `CalendarGridModel` lane packer for the visible
/// day(s) and the mobile store's existing `loadCalendarTimeline` fetch path
/// (windowed around the visible date via `refreshCalendarTimeline(around:)`),
/// so it never forks the data path. Tapping a block opens the existing mobile
/// edit sheet; tapping an empty slot prefills + opens the create sheet.
@MainActor
public struct MobileCalendarDayView: View {
  @Bindable var store: MobileStore
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  /// When true, render a seven-day grouped agenda and page by week instead of
  /// squeezing seven time-axis columns into a phone or multitasking window.
  var weekMode: Bool = false
  /// The calendar search text, owned by the enclosing `MobileStoreCalendarView`.
  /// Narrows the visible events to those matching title / location / notes.
  var searchQuery: String = ""
  @State var dayOffset = 0
  @State var loadedAnchor: Date?
  @State var isShowingCreateEvent = false
  @State var editingEvent: CalendarTimelineEvent?
  @State private var eventAwaitingDeleteScope: CalendarTimelineEvent?

  let calendar = Calendar.current
  /// Bounded rolling page window so we never materialize an unbounded range.
  /// In week mode each step is a week, so this still spans years either way.
  let pageRange = -180...180

  public init(store: MobileStore, weekMode: Bool = false, searchQuery: String = "") {
    self.store = store
    self.weekMode = weekMode
    self.searchQuery = searchQuery
  }

  var today: Date {
    PlannedDayBridge.displayDate(
      forLogicalDay: store.logicalTodayString,
      calendar: calendar)
      ?? calendar.startOfDay(for: store.now())
  }

  /// The loaded events narrowed by the calendar search field. Matches title,
  /// location, and notes with the shared term-AND semantics, mirroring the macOS
  /// calendar filter (which narrows the same event array). Tasks stay unfiltered
  /// — this is an event search. An empty query returns every loaded event.
  var filteredEvents: [CalendarTimelineEvent] {
    let events = store.calendarTimeline?.events ?? []
    let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return events }
    return events.filter { event in
      LorvexCatalogSearch.matches(query, fields: [event.title, event.location, event.notes])
    }
  }

  /// True while the search field holds a non-empty query.
  var isSearching: Bool {
    !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  /// First day of the current week, honoring the locale's first weekday.
  var weekStart: Date {
    calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
  }

  func date(forOffset offset: Int) -> Date {
    if weekMode {
      return calendar.date(byAdding: .day, value: offset * 7, to: weekStart) ?? weekStart
    }
    return calendar.date(byAdding: .day, value: offset, to: today) ?? today
  }

  var visibleDate: Date { date(forOffset: dayOffset) }

  var defaultCreateDate: Date {
    Self.defaultCreateDate(
      weekMode: weekMode,
      visibleDate: visibleDate,
      today: today,
      calendar: calendar)
  }

  /// A week-level plus button has no selected day. In the current week it
  /// should create on today; in any other week it anchors to that week's first
  /// visible day. Day and multi-day modes retain their visible-date behavior.
  nonisolated static func defaultCreateDate(
    weekMode: Bool,
    visibleDate: Date,
    today: Date,
    calendar: Calendar
  ) -> Date {
    guard weekMode else { return visibleDate }
    let visibleWeekStart = CalendarGridModel.startOfWeek(
      containing: visibleDate, calendar: calendar)
    let currentWeekStart = CalendarGridModel.startOfWeek(containing: today, calendar: calendar)
    return calendar.isDate(visibleWeekStart, inSameDayAs: currentWeekStart)
      ? today
      : visibleWeekStart
  }

  public var body: some View {
    Group {
      if weekMode {
        weekAgendaBody
      } else if horizontalSizeClass == .regular {
        GeometryReader { geo in
          let dayCount = dayCount(for: geo.size.width)
          if usesAgendaPanel(for: geo.size.width) {
            regularBody(dayCount: dayCount)
          } else {
            dayGrid(dayCount: dayCount)
          }
        }
      } else {
        dayGrid(dayCount: 1)
      }
    }
    .navigationTitle(MobileDestination.calendar.title)
    // Inline title: a large title over a TabView grid reserves a big empty
    // collapse band (the week grid otherwise floated mid-screen), and a compact
    // title is the right idiom for a calendar anyway.
    #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
    #endif
    .toolbar { toolbarContent }
    .task(id: visibleDate) { await ensureWindowLoaded() }
    .sheet(isPresented: $isShowingCreateEvent) {
      MobileStoreCreateCalendarEventSheet(store: store, isPresented: $isShowingCreateEvent)
        .lorvexSpatialBackground()
    }
    .sheet(item: $editingEvent) { event in
      MobileStoreEditCalendarEventSheet(
        event: event,
        store: store,
        // See CalendarWorkspaceView: constant-true getter avoids the
        // double-dismiss flash from deriving the binding off `editingEvent`,
        // which `.sheet(item:)` already owns.
        isPresented: Binding(
          get: { true },
          set: { if !$0 { editingEvent = nil } }
        )
      )
      .lorvexSpatialBackground()
    }
    .mobileCalendarDeleteScopeDialog(
      event: $eventAwaitingDeleteScope,
      delete: { await store.deleteScopedCalendarEvent($0, scope: $1) }
    )
    .accessibilityIdentifier("mobileCalendarDay.root")
    .overlay {
      // No event in the loaded window matches the active query: stand in a
      // search-empty state over the (now empty) grid rather than a blank day.
      if isSearching, filteredEvents.isEmpty {
        ContentUnavailableView.search(text: searchQuery)
          .allowsHitTesting(false)
      }
    }
  }

  func dayGrid(dayCount: Int) -> some View {
    VStack(spacing: 0) {
      if weekMode {
        // Week range + prev/next, so the nav bar stays uncrowded and you can see
        // which week is shown. Changes `dayOffset`; the pinned header and column
        // both key off `visibleDate`, so they move together.
        weekNavigationHeader
        Divider()
        // Pinned 7-day header so the labels stay put while the time grid scrolls.
        MobileCalendarColumnHeaders(
          columns: visibleColumns(dayCount: 7), calendar: calendar, gutterWidth: 52)
        Divider()
        // No pager: a `.page` TabView centers a column shorter than the page,
        // floating the grid mid-screen. The plain column is given an explicit
        // height so it fills from the top instead of being center-aligned.
        GeometryReader { geo in
          column(forOffset: dayOffset, dayCount: 7, showsHeaders: false)
            .frame(width: geo.size.width, height: geo.size.height)
        }
      } else {
        MobileCalendarWeekStrip(visibleDate: visibleDate, calendar: calendar) { day in
          jump(to: day)
        }
        Divider()
        pager(dayCount: dayCount)
      }
    }
  }

  /// Compact week-navigation bar shown above the grouped agenda in week mode:
  /// `‹  Jun 28 – Jul 4  ›`. Prev/next step `dayOffset` by one week.
  var weekNavigationHeader: some View {
    HStack(spacing: 12) {
      Button {
        withAnimation { dayOffset -= 1 }
      } label: {
        Image(systemName: "chevron.left").font(.body.weight(.semibold))
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
      }
      .lorvexToolbarHoverEffect()
      .accessibilityIdentifier("mobileCalendar.week.previous")
      .accessibilityLabel(
        String(
          localized: "calendar.week.previous", defaultValue: "Previous week", table: "Localizable",
          bundle: MobileL10n.bundle))
      Spacer(minLength: 0)
      Text(weekRangeLabel)
        .font(LorvexDesign.Typography.secondaryText.weight(.semibold))
        .monospacedDigit()
        .accessibilityAddTraits(.isHeader)
      Spacer(minLength: 0)
      Button {
        withAnimation { dayOffset += 1 }
      } label: {
        Image(systemName: "chevron.right").font(.body.weight(.semibold))
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
      }
      .lorvexToolbarHoverEffect()
      .accessibilityIdentifier("mobileCalendar.week.next")
      .accessibilityLabel(
        String(
          localized: "calendar.week.next", defaultValue: "Next week", table: "Localizable",
          bundle: MobileL10n.bundle))
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
  }

  /// Locale-aware label for the visible week, e.g. "Jun 28 – Jul 4, 2026".
  private var weekRangeLabel: String {
    let end = calendar.date(byAdding: .day, value: 6, to: visibleDate) ?? visibleDate
    let formatter = DateIntervalFormatter()
    formatter.locale = MobileL10n.locale
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter.string(from: visibleDate, to: end)
  }

  /// The lane-packed `CalendarGridDay` columns for the currently visible window —
  /// used to render the pinned week header outside the pager.
  func visibleColumns(dayCount: Int) -> [CalendarGridDay] {
    CalendarGridModel.buildDays(
      rangeStart: visibleDate, dayCount: dayCount, calendar: calendar,
      events: filteredEvents, tasks: store.calendarScheduledTasks,
      dayKeyFor: { Self.keyFormatter.string(from: $0) })
  }

  /// Regular-width iPad can mean anything from a narrow Stage Manager tile to a
  /// full landscape canvas. Use the actual width so columns stay legible.
  func dayCount(for width: CGFloat) -> Int {
    Self.adaptiveDayCount(for: width, isRegularWidth: horizontalSizeClass == .regular)
  }

  func usesAgendaPanel(for width: CGFloat) -> Bool {
    Self.usesAgendaPanel(for: width, isRegularWidth: horizontalSizeClass == .regular)
  }

  nonisolated static func adaptiveDayCount(for width: CGFloat, isRegularWidth: Bool) -> Int {
    guard isRegularWidth else { return 1 }
    if width < 760 { return 1 }
    if width < 1_020 { return 2 }
    return 3
  }

  nonisolated static func usesAgendaPanel(for width: CGFloat, isRegularWidth: Bool) -> Bool {
    isRegularWidth && width >= 860
  }

  // MARK: Toolbar

  @ToolbarContentBuilder
  private var toolbarContent: some ToolbarContent {
    ToolbarItem(placement: .navigation) {
      Button(
        String(
          localized: "calendar.today", defaultValue: "Today", table: "Localizable",
          bundle: MobileL10n.bundle)
      ) { withAnimation { dayOffset = 0 } }
      .disabled(dayOffset == 0)
      .lorvexToolbarHoverEffect()
      .accessibilityIdentifier("mobileCalendarDay.today")
    }
    // Centered in the nav bar (not crammed beside ＋ in the trailing area, where
    // "Week" truncated to "We…"); the tab bar already names this surface, so the
    // switcher stands in for the redundant inline title — mirrors Apple Calendar.
    ToolbarItem(placement: .principal) {
      Picker(
        String(
          localized: "calendar.view_picker", defaultValue: "View", table: "Localizable",
          bundle: MobileL10n.bundle), selection: $store.calendarPresentationMode
      ) {
        ForEach(MobileCalendarPresentationMode.allCases) { mode in
          Text(mode.title).tag(mode)
        }
      }
      .pickerStyle(.segmented)
      .frame(maxWidth: 280)
      .accessibilityIdentifier("mobileCalendar.presentationToggle")
    }
    ToolbarItem(placement: .primaryAction) {
      Button {
        let date = defaultCreateDate
        prepareCreate(at: date, minutes: defaultCreateMinutes(on: date))
      } label: {
        Label(
          String(
            localized: "calendar.new_event", defaultValue: "New Event", table: "Localizable",
            bundle: MobileL10n.bundle), systemImage: "plus")
      }
      .lorvexToolbarHoverEffect()
      .accessibilityIdentifier("mobileCalendar.toolbarCreate")
    }
  }

  // MARK: Pager

  /// One full-width calendar column (1, 2, or 3 days) wired to the store's
  /// mutation callbacks.
  private func column(forOffset offset: Int, dayCount: Int, showsHeaders: Bool) -> some View {
    MobileCalendarDayColumn(
      startDate: date(forOffset: offset),
      dayCount: dayCount,
      showsHeaders: showsHeaders,
      events: filteredEvents,
      tasks: store.calendarScheduledTasks,
      calendar: calendar,
      onTapEvent: { event in
        store.prepareCalendarDraft(for: event)
        editingEvent = event
      },
      onDeleteEvent: { event in
        if event.supportsScopedMutation {
          eventAwaitingDeleteScope = event
          return false
        }
        return await store.deleteCalendarEvent(event)
      },
      onTapTask: { task in
        store.cacheTasks([task])
        store.openNavigationTarget(
          MobileNavigationTarget(selectedTab: .today, route: .task(task.id))
        )
      },
      onDropTask: { ref, day in
        Task { @MainActor in
          await store.planTask(ref.id, on: day)
        }
      },
      onTapEmpty: { day, minutes in
        prepareCreate(at: day, minutes: minutes)
      },
      onReschedule: { event, targetDay, newStartMinute in
        Task { @MainActor in
          await reschedule(event, toDay: targetDay, minute: newStartMinute)
        }
      }
    )
  }

  /// Day / 3-day pager. The now-line ticks inside each column's own scoped
  /// `TimelineView`, so the per-minute refresh never re-instantiates the pages
  /// or re-runs the lane-packer (`CalendarGridModel.buildDays`) — only the thin
  /// now-line overlay rebuilds. Week mode uses the grouped agenda instead.
  private func pager(dayCount: Int) -> some View {
    TabView(selection: $dayOffset) {
      ForEach(pageRange, id: \.self) { offset in
        column(forOffset: offset, dayCount: dayCount, showsHeaders: true)
          .tag(offset)
      }
    }
    #if os(iOS)
      .tabViewStyle(.page(indexDisplayMode: .never))
    #endif
  }

  // MARK: Actions

  static var keyFormatter: DateFormatter { LorvexDateFormatters.ymd }

}

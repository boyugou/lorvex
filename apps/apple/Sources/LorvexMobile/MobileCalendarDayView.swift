import LorvexCore
import SwiftUI

/// Phone-native calendar: one vertical time-axis grid (hour gutter on the
/// left, events as lane-packed blocks, all-day strip on top, live now-line)
/// whose two modes differ only in how many days it shows. Day mode shows one
/// day on a phone (two or three on a wide iPad, with the agenda beside it),
/// swiped by day, under a week strip that jumps to any day of the week. Week
/// mode shows the seven days of a week, swiped by week; tapping a day's header
/// opens that day in Day mode. Above both sits one header row: the month (or
/// the week's range) and a Today button that keeps its slot, hidden while
/// today is in view, so nothing beside it moves when it appears.
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

  /// When true, the grid shows the seven days of a week and pages by week.
  var weekMode: Bool = false
  /// The calendar search text, owned by the enclosing `MobileStoreCalendarView`.
  /// Narrows the visible events to those matching title / location / notes.
  var searchQuery: String = ""
  @State var dayOffset = 0
  @State var loadedAnchor: Date?
  @State var isShowingCreateEvent = false
  @State var editingEvent: CalendarTimelineEvent?
  // Not private: the agenda-body extension (a separate file) routes scoped
  // deletes through this same this/future/all dialog.
  @State var eventAwaitingDeleteScope: CalendarTimelineEvent?
  /// The calendar's width, so the mode picker names the day grid ("Day",
  /// "3 Days") even while the week is showing. The day count is derived when
  /// the picker draws rather than stored, because it also depends on the
  /// size class, which can settle after the width is first measured.
  @State private var calendarWidth: CGFloat = 0

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
        dayGrid(dayCount: 7)
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
    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
      calendarWidth = width
    }
    .task(id: visibleDate) {
      await ensureWindowLoaded()
    }
    .task {
      if store.workdayEndMinutes == nil { await store.loadWorkdayWindow() }
    }
    .onAppear {
      guard !weekMode, let key = store.calendarPendingDayKey else { return }
      store.calendarPendingDayKey = nil
      if let day = Self.keyFormatter.date(from: key) { jump(to: day) }
    }
    .sheet(isPresented: $isShowingCreateEvent) {
      MobileStoreCreateCalendarEventSheet(store: store, isPresented: $isShowingCreateEvent)
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
    }
    .mobileCalendarDeleteScopeDialog(
      event: $eventAwaitingDeleteScope,
      delete: { await store.deleteScopedCalendarEvent($0, scope: $1) }
    )
    .accessibilityIdentifier("mobileCalendarDay.root")
    .overlay {
      // No event matches the query AND no scheduled task is present: only then
      // is the grid genuinely empty. The search filters events only, so
      // scheduled tasks stay visible; showing "No Results" over them would
      // float a contradictory empty state atop real content.
      if isSearching, filteredEvents.isEmpty, store.calendarScheduledTasks.isEmpty {
        ContentUnavailableView.search(text: searchQuery)
          .allowsHitTesting(false)
      }
    }
  }

  // The time grid in either mode. Its text stops growing at the largest
  // standard size: the week strip, column headers, and hour rows have fixed
  // geometry, so at accessibility sizes weekday names would break letter by
  // letter and event titles would clip. The agenda beside it keeps growing.
  func dayGrid(dayCount: Int) -> some View {
    VStack(spacing: 0) {
      calendarHeader
      // Week mode's column headers already name every day of the week.
      if !weekMode {
        MobileCalendarWeekStripPager(
          visibleDate: visibleDate, today: today, calendar: calendar,
          weekRange: (pageRange.lowerBound / 7)...(pageRange.upperBound / 7)
        ) { day in
          jump(to: day)
        }
        Divider()
      }
      pager(dayCount: dayCount)
    }
    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
  }

  /// The row above the grid: what the grid shows, then Today. Today keeps
  /// its slot while today is in view, only hidden, so the title never shifts
  /// when the user swipes away and the button appears.
  private var calendarHeader: some View {
    let isOnToday = dayOffset == 0
    return HStack(spacing: LorvexDesign.Spacing.m) {
      Text(headerTitle)
        .font(LorvexDesign.Typography.primaryEmphasis)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityAddTraits(.isHeader)
        .contentTransition(.numericText())
      Spacer(minLength: 0)
      Button(
        String(
          localized: "calendar.today", defaultValue: "Today", table: "Localizable",
          bundle: MobileL10n.bundle)
      ) { withAnimation { dayOffset = 0 } }
      .buttonStyle(.bordered)
      .controlSize(.small)
      .opacity(isOnToday ? 0 : 1)
      .disabled(isOnToday)
      .accessibilityHidden(isOnToday)
      .accessibilityIdentifier("mobileCalendarDay.today")
    }
    .padding(.horizontal, LorvexDesign.Spacing.l)
    .padding(.top, LorvexDesign.Spacing.xs)
    .animation(.snappy(duration: 0.2), value: isOnToday)
    .accessibilityIdentifier("mobileCalendarDay.header")
  }

  /// The week's range in week mode ("Sep 27 – Oct 3"); the visible day's
  /// month and year in day mode ("October 2026"), since the week strip under
  /// it already names the days.
  private var headerTitle: String {
    if weekMode {
      return Self.weekRangeLabel(
        from: visibleDate, calendar: calendar, now: LorvexPreviewClock.now(in: calendar),
        locale: MobileL10n.locale)
    }
    var style = Date.FormatStyle().month(.wide).year().locale(MobileL10n.locale)
    style.timeZone = calendar.timeZone
    return visibleDate.formatted(style)
  }

  /// The week that starts on `start` as a locale-aware range: "Sep 27 –
  /// Oct 3" or "9月27日至10月3日" while the week lies in `now`'s year, and with
  /// its years ("Dec 27, 2026 – Jan 2, 2027") once it reaches outside it. The
  /// `MMMd` and `yMMMd` templates rather than the medium date style, which
  /// writes a Chinese interval in numerals ("2026/6/28 – 2026/7/4"). Where it
  /// wraps, it breaks only after its dash.
  nonisolated static func weekRangeLabel(
    from start: Date, calendar: Calendar, now: Date, locale: Locale
  ) -> String {
    let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
    let isThisYear =
      calendar.isDate(start, equalTo: now, toGranularity: .year)
      && calendar.isDate(end, equalTo: now, toGranularity: .year)
    let formatter = DateIntervalFormatter()
    formatter.locale = locale
    formatter.timeZone = calendar.timeZone
    formatter.dateTemplate = isThisYear ? "MMMd" : "yMMMd"
    return lorvexUnbreakable(formatter.string(from: start, to: end))
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
          Text(mode.title(gridDayCount: dayCount(for: calendarWidth))).tag(mode)
        }
      }
      .pickerStyle(.segmented)
      // A segmented control in the toolbar keeps the titles it was created
      // with, so it is rebuilt whenever the grid's day count renames a segment.
      .id(dayCount(for: calendarWidth))
      .frame(maxWidth: 280)
      .accessibilityIdentifier("mobileCalendar.presentationToggle")
    }
    // The tab bar's plus captures a task; New Event carries the calendar glyph
    // so the two creation buttons never read as the same action.
    ToolbarItem(placement: .primaryAction) {
      Button {
        let date = defaultCreateDate
        prepareCreate(at: date, minutes: defaultCreateMinutes(on: date))
      } label: {
        Label(
          String(
            localized: "calendar.new_event", defaultValue: "New Event", table: "Localizable",
            bundle: MobileL10n.bundle), systemImage: "calendar.badge.plus")
      }
      .lorvexToolbarHoverEffect()
      .accessibilityIdentifier("mobileCalendar.toolbarCreate")
    }
  }

  // MARK: Pager

  /// One full-width calendar page (1, 2, 3, or 7 days) wired to the store's
  /// mutation callbacks.
  private func column(forOffset offset: Int, dayCount: Int, showsHeaders: Bool) -> some View {
    MobileCalendarDayColumn(
      startDate: date(forOffset: offset),
      dayCount: dayCount,
      showsHeaders: showsHeaders,
      circlesTodayInHeaders: weekMode,
      events: filteredEvents,
      tasks: store.calendarScheduledTasks,
      calendar: calendar,
      onOpenDay: weekMode ? { day in openInDayMode(day) } : nil,
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
        store.openTaskRouteOnCurrentStack(task.id)
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
      },
      onToggleTask: { task in
        Task { @MainActor in await store.toggleTaskCompletion(task) }
      },
      isRunningNow: { block, day in
        guard day.dayKey == store.logicalTodayString, let now = store.nowMinutesInProductDay
        else { return false }
        return block.startMin <= now && now < block.endMin
      }
    )
  }

  /// The grid's pager, one page per day (or per week in week mode). The
  /// now-line ticks inside each column's own scoped `TimelineView`, so the
  /// per-minute refresh never re-instantiates the pages or re-runs the
  /// lane-packer (`CalendarGridModel.buildDays`) — only the thin now-line
  /// overlay rebuilds.
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

  /// Switches to Day mode on `day`; the day view that replaces this one
  /// opens on it through `calendarPendingDayKey`.
  private func openInDayMode(_ day: Date) {
    store.calendarPendingDayKey = Self.keyFormatter.string(from: day)
    store.calendarPresentationMode = .grid
  }

}

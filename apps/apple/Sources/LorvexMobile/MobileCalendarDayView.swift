import LorvexCore
import SwiftUI

/// Phone-native calendar time grid: one vertical time axis (hour gutter on
/// the left, events as lane-packed blocks, all-day strip on top, live
/// now-line) whose two modes, Day and Week, differ only in how many days it
/// shows; Month mode is ``MobileCalendarMonthView``. Day mode shows one
/// day on a phone held upright (two or three on a wide iPad, with the agenda
/// beside it), swiped by day, under a week strip that jumps to any day of the
/// week. A phone on its side has the width of three days and the height of a
/// few hours, so Day mode shows three days there, each named by its column
/// header, without the week strip. Week mode shows the seven days of a week,
/// swiped by week; tapping a day's header opens that day in Day mode. Above
/// both sits one header row: the month (or the week's range) and a Today
/// button that keeps its slot, hidden while today is in view, so nothing
/// beside it moves when it appears.
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
  /// Compact on a phone on its side.
  @Environment(\.verticalSizeClass) private var verticalSizeClass

  /// When true, the grid shows the seven days of a week and pages by week.
  var weekMode: Bool = false
  /// The calendar search text, owned by the enclosing `MobileStoreCalendarView`.
  /// Narrows the visible events to those matching title / location / notes.
  var searchQuery: String = ""
  @State var dayOffset = 0
  /// In week mode, the day of the visible week a switch to Day mode opens, in
  /// days from the week's first day. It starts on today, or on the day Day
  /// mode handed over, and keeps its weekday as the weeks page.
  @State var weekDayIndex = 0
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
  /// The pager's width, handed to each page so its column is drawn once, at
  /// its final width, when it is built. 0 until measured.
  @State private var pagerWidth: CGFloat = 0

  let calendar = Calendar.current
  /// Bounded rolling page window so we never materialize an unbounded range.
  /// In week mode each step is a week, so this still spans years either way.
  let pageRange = -180...180

  /// Opens on the day a mode switch handed over
  /// (``MobileStore/calendarPendingDay(in:)``), or on today. The view starts
  /// on that day rather than moving there once it appears, so the week strip
  /// takes its first position on the right week.
  public init(store: MobileStore, weekMode: Bool = false, searchQuery: String = "") {
    self.store = store
    self.weekMode = weekMode
    self.searchQuery = searchQuery
    let day = store.calendarPendingDay(in: calendar) ?? today
    _dayOffset = State(initialValue: offset(showing: day))
    _weekDayIndex = State(initialValue: Self.dayIndexInWeek(of: day, calendar: calendar))
  }

  var today: Date { store.calendarToday(in: calendar) }

  /// The loaded events narrowed by the calendar search field
  /// (``MobileStore/calendarEvents(matching:)``).
  var filteredEvents: [CalendarTimelineEvent] {
    store.calendarEvents(matching: searchQuery)
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
      } else if horizontalSizeClass == .regular || verticalSizeClass == .compact {
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
    .toolbar {
      MobileCalendarToolbar(
        mode: store.calendarPresentationMode,
        gridDayCount: dayCount(for: calendarWidth),
        isCompactWidth: horizontalSizeClass != .regular,
        switchMode: { switchMode(to: $0) },
        createEvent: {
          store.calendarDraft = .timedDefault(
            on: defaultCreateDate, now: store.now(), calendar: calendar)
          isShowingCreateEvent = true
        })
    }
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
      // The view opened on the handed-over day (see init); the next mode to
      // appear opens on its own.
      store.calendarPendingDayKey = nil
    }
    #if DEBUG
      .onAppear {
        // Dev/QA only: the `lorvex://sheet/event` screenshot hook raises the
        // New Event sheet on a staged draft so it can be captured without a tap.
        if let draft = MobileCalendarDebugState.takeInitialCreateDraft() {
          store.calendarDraft = draft
          isShowingCreateEvent = true
        }
      }
    #endif
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

  /// Whether the week strip sits over the grid: in Day mode, except on a phone
  /// on its side, where the strip would take the height of an hour from a
  /// grid that shows only a few. Week mode's column headers already name
  /// every day of the week, and so do the three columns of a phone on its
  /// side.
  var showsWeekStrip: Bool {
    !weekMode && verticalSizeClass != .compact
  }

  // The time grid in either mode. Its text stops growing at the largest
  // standard size: the week strip, column headers, and hour rows have fixed
  // geometry, so at accessibility sizes weekday names would break letter by
  // letter and event titles would clip. The agenda beside it keeps growing.
  func dayGrid(dayCount: Int) -> some View {
    VStack(spacing: 0) {
      MobileCalendarHeaderRow(
        title: headerTitle, isOnToday: dayOffset == 0, goToToday: { jump(to: today) })
      if showsWeekStrip {
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

  /// The week's range in week mode ("Sep 27 – Oct 3"); the visible day's
  /// month and year in day mode ("October 2026"), since the week strip under
  /// it already names the days.
  private var headerTitle: String {
    if weekMode {
      return LorvexDateFormatters.weekRange(
        startingOn: visibleDate, now: LorvexPreviewClock.now(in: calendar), calendar: calendar)
    }
    return LorvexDateFormatters.string(
      visibleDate, template: "yMMMM", timeZone: calendar.timeZone, position: .leading)
  }

  /// Regular-width iPad can mean anything from a narrow Stage Manager tile to a
  /// full landscape canvas. Use the actual width so columns stay legible.
  func dayCount(for width: CGFloat) -> Int {
    Self.adaptiveDayCount(
      for: width, isRegularWidth: horizontalSizeClass == .regular,
      isCompactHeight: verticalSizeClass == .compact)
  }

  func usesAgendaPanel(for width: CGFloat) -> Bool {
    Self.usesAgendaPanel(
      for: width, isRegularWidth: horizontalSizeClass == .regular,
      isCompactHeight: verticalSizeClass == .compact)
  }

  /// The days Day mode shows: one in a compact width, two or three by the
  /// actual width in a regular one, and three on a phone on its side (a
  /// compact height), whose landscape width holds three readable columns on
  /// every iPhone.
  nonisolated static func adaptiveDayCount(
    for width: CGFloat, isRegularWidth: Bool, isCompactHeight: Bool = false
  ) -> Int {
    if isCompactHeight { return 3 }
    guard isRegularWidth else { return 1 }
    if width < 760 { return 1 }
    if width < 1_020 { return 2 }
    return 3
  }

  /// Whether the agenda stands beside the grid: in a regular width of at
  /// least 860 points, and never in a compact height, where a list beside
  /// the grid would show only a few rows.
  nonisolated static func usesAgendaPanel(
    for width: CGFloat, isRegularWidth: Bool, isCompactHeight: Bool = false
  ) -> Bool {
    isRegularWidth && !isCompactHeight && width >= 860
  }

  // MARK: Pager

  /// One full-width calendar column (1, 2, 3, or 7 days) starting on
  /// `startDate`, wired to the store's mutation callbacks.
  private func column(
    startDate: Date, dayCount: Int, showsHeaders: Bool, events: [CalendarTimelineEvent],
    tasks: [LorvexTask], pageWidth: CGFloat
  ) -> MobileCalendarDayColumn {
    MobileCalendarDayColumn(
      startDate: startDate,
      dayCount: dayCount,
      showsHeaders: showsHeaders,
      circlesTodayInHeaders: !showsWeekStrip,
      events: events,
      tasks: tasks,
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
      },
      pageWidth: pageWidth
    )
  }

  /// The page at `offset` of the grid's pager: a column while the page is
  /// near the visible one, an empty placeholder otherwise (``MobileLivePages``).
  private func page(
    forOffset offset: Int, dayCount: Int, events: [CalendarTimelineEvent], tasks: [LorvexTask]
  ) -> MobileCalendarDayPage {
    guard MobileLivePages.holdsContent(offset: offset, visibleOffset: dayOffset) else {
      return MobileCalendarDayPage()
    }
    let startDate = date(forOffset: offset)
    let inputs = MobileCalendarDayPage.Inputs(
      startDate: startDate, dayCount: dayCount, showsHeaders: true,
      circlesTodayInHeaders: !showsWeekStrip, opensDays: weekMode, events: events, tasks: tasks,
      pageWidth: pagerWidth, calendar: calendar)
    return MobileCalendarDayPage(inputs: inputs) {
      column(
        startDate: startDate, dayCount: dayCount, showsHeaders: true, events: events, tasks: tasks,
        pageWidth: pagerWidth)
    }
  }

  /// The grid's pager, one page per day (or per week in week mode). Every
  /// page of the range stays in the pager's list so a page keeps its
  /// identity; only the pages near the visible one hold a column
  /// (``MobileLivePages``), and a page whose inputs did not change is skipped
  /// when the pager is evaluated again. The now-line ticks inside each
  /// column's own scoped `TimelineView`, so the per-minute refresh never
  /// re-instantiates the pages or re-runs the lane-packer
  /// (`CalendarGridModel.buildDays`) — only the thin now-line overlay
  /// rebuilds.
  private func pager(dayCount: Int) -> some View {
    let events = filteredEvents
    let tasks = store.calendarScheduledTasks
    return TabView(selection: $dayOffset) {
      ForEach(pageRange, id: \.self) { offset in
        page(forOffset: offset, dayCount: dayCount, events: events, tasks: tasks)
          .equatable()
          .environment(\.mobileCalendarPageIsReachable, offset == dayOffset)
          .tag(offset)
      }
    }
    #if os(iOS)
      .tabViewStyle(.page(indexDisplayMode: .never))
    #endif
    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { pagerWidth = $0 }
  }

  // MARK: Actions

  static var keyFormatter: DateFormatter { LorvexDateFormatters.ymd }

  /// Switches to Day mode on `day`.
  private func openInDayMode(_ day: Date) {
    switchMode(to: .grid, on: day)
  }

  /// Switches the calendar to `mode` on the day this view is showing, so the
  /// other mode opens where the person was: Day mode hands over its first
  /// visible day, Week mode the focused day of its visible week, and Month
  /// mode opens on that day's month with the day chosen.
  private func switchMode(to mode: MobileCalendarPresentationMode) {
    switchMode(to: mode, on: modeSwitchDay)
  }

  /// Switches the calendar to `mode` on `day`, which the view that replaces
  /// this one opens on.
  private func switchMode(to mode: MobileCalendarPresentationMode, on day: Date) {
    store.switchCalendarPresentationMode(to: mode, onDayKey: Self.keyFormatter.string(from: day))
  }

}

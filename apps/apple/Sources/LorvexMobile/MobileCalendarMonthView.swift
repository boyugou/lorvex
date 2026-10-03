import LorvexCore
import SwiftUI

/// Month mode of the mobile calendar: six weeks of days, swiped by month,
/// over or beside the agenda of the chosen day.
///
/// A phone held upright stacks the agenda under a grid of fixed-height rows
/// that mark each day's events and tasks with dots. A wide iPad and a phone
/// on its side stand the agenda beside a grid that fills the height, and an
/// iPad's narrower window stacks it under one; where a cell is tall and wide
/// enough, it names its entries instead of marking them
/// (``MobileCalendarMonthDayCell``). Every month keeps six rows, so the grid
/// never changes height as the months page.
///
/// Tapping a day chooses it, and paging to another month chooses its first
/// day, or today in today's month. Over the grid sit the header row (the
/// month, and Today, which pages back to today's month and chooses today)
/// and the weekday names. New Event creates on the chosen day, a day's
/// context menu creates on that day, and a task dragged onto a day from the
/// agenda, or from another day, is planned on it. A switch to Day or Week
/// mode opens on the chosen day. The grid reads the store's calendar
/// window, loaded for the visible month and both months a swipe reveals,
/// and the search field narrows its events as it does in the other modes.
@MainActor
struct MobileCalendarMonthView: View {
  @Bindable var store: MobileStore
  /// The calendar search text, owned by the enclosing `MobileStoreCalendarView`.
  var searchQuery: String = ""
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  /// Compact on a phone on its side.
  @Environment(\.verticalSizeClass) private var verticalSizeClass
  /// The visible month, in months from today's.
  @State private var monthOffset = 0
  /// The chosen day, a local start of day.
  @State private var selectedDay: Date
  /// Counts the days the user taps, which plays the selection haptic; a
  /// choice that paging makes plays none.
  @State private var chooseCount = 0
  @State private var isShowingCreateEvent = false
  @State private var editingEvent: CalendarTimelineEvent?
  @State private var eventAwaitingDeleteScope: CalendarTimelineEvent?
  /// The calendar's width, so the mode picker names Day mode's segment by the
  /// days Day mode would show here ("Day", "3 Days").
  @State private var calendarWidth: CGFloat = 0

  private let calendar = Calendar.current
  /// Ten years each way: a bounded page range, so the pager never
  /// materializes an unbounded one.
  private let pageRange = -120...120
  /// Every month's grid has six rows.
  private static let gridWeeks = 6

  /// Opens on the day a switch from Day or Week mode handed over
  /// (``MobileStore/calendarPendingDay(in:)``), chosen in its month, or on
  /// today. The view starts there rather than paging there once it appears,
  /// so the first window it loads is that month's.
  init(store: MobileStore, searchQuery: String = "") {
    self.store = store
    self.searchQuery = searchQuery
    let day = store.calendarPendingDay(in: .current) ?? store.calendarToday(in: .current)
    _selectedDay = State(initialValue: day)
    _monthOffset = State(initialValue: offset(showing: day))
  }

  private var today: Date { store.calendarToday(in: calendar) }

  private var currentMonthStart: Date {
    CalendarMonthGridModel.startOfMonth(containing: today, calendar: calendar)
  }

  private func monthStart(forOffset offset: Int) -> Date {
    calendar.date(byAdding: .month, value: offset, to: currentMonthStart) ?? currentMonthStart
  }

  private var selectedKey: String { Self.keyFormatter.string(from: selectedDay) }

  private var isSearching: Bool {
    !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var body: some View {
    let events = store.calendarEvents(matching: searchQuery)
    GeometryReader { geo in
      let isRegularWidth = horizontalSizeClass == .regular
      if Self.usesSideAgenda(
        width: geo.size.width, isRegularWidth: isRegularWidth,
        isCompactHeight: verticalSizeClass == .compact)
      {
        HStack(spacing: 0) {
          monthColumn(events: events, fillsHeight: true)
          Divider()
          agenda(events: events, placement: .beside)
            .frame(minWidth: 300, idealWidth: 340, maxWidth: 420)
        }
      } else {
        VStack(spacing: 0) {
          // An iPad's narrower window gives the grid the larger share of the
          // height, enough for its cells to name their entries; a phone's
          // grid keeps fixed rows and the agenda takes the rest.
          monthColumn(events: events, fillsHeight: isRegularWidth)
          Divider()
          agenda(events: events, placement: .under)
            .frame(height: isRegularWidth ? geo.size.height * 0.38 : nil)
        }
      }
    }
    .navigationTitle(MobileDestination.calendar.title)
    #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
    #endif
    .toolbar {
      MobileCalendarToolbar(
        mode: .month,
        gridDayCount: MobileCalendarDayView.adaptiveDayCount(
          for: calendarWidth, isRegularWidth: horizontalSizeClass == .regular,
          isCompactHeight: verticalSizeClass == .compact),
        isCompactWidth: horizontalSizeClass != .regular,
        switchMode: { switchMode(to: $0) },
        createEvent: { createEvent(on: selectedDay) })
    }
    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
      calendarWidth = width
    }
    .task(id: monthOffset) { await loadWindow() }
    .onAppear {
      // The view opened on the handed-over day (see init); the next mode to
      // appear opens on its own.
      store.calendarPendingDayKey = nil
    }
    .onChange(of: monthOffset) { _, offset in
      // A swipe to another month chooses a day in it; a tap on a day of the
      // next or previous month has already chosen that day.
      let start = monthStart(forOffset: offset)
      guard !calendar.isDate(selectedDay, equalTo: start, toGranularity: .month) else { return }
      selectedDay = Self.defaultSelection(forMonthStarting: start, today: today, calendar: calendar)
    }
    .lorvexSensoryFeedback(.selection, trigger: chooseCount)
    .sheet(isPresented: $isShowingCreateEvent) {
      MobileStoreCreateCalendarEventSheet(store: store, isPresented: $isShowingCreateEvent)
    }
    .sheet(item: $editingEvent) { event in
      MobileStoreEditCalendarEventSheet(
        event: event,
        store: store,
        // A constant-true getter: deriving the binding from `editingEvent`,
        // which `.sheet(item:)` already owns, flashes a double dismiss.
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
    .accessibilityIdentifier("mobileCalendarMonth.root")
    .overlay {
      // The search narrows events only, so "No Results" shows only when no
      // event matches and no task is in the window either.
      if isSearching, events.isEmpty, store.calendarScheduledTasks.isEmpty {
        ContentUnavailableView.search(text: searchQuery)
          .allowsHitTesting(false)
      }
    }
  }

  // MARK: Layout

  /// The header row, the weekday names, and the paged grid. Its text stops
  /// growing at the largest standard size, as the time grid's does: the
  /// cells have fixed geometry, so at accessibility sizes day numbers would
  /// overflow their circles. The agenda keeps growing.
  private func monthColumn(events: [CalendarTimelineEvent], fillsHeight: Bool) -> some View {
    VStack(spacing: 0) {
      MobileCalendarHeaderRow(
        title: LorvexDateFormatters.string(
          monthStart(forOffset: monthOffset), template: "yMMMM", timeZone: calendar.timeZone),
        isOnToday: monthOffset == 0 && selectedKey == store.logicalTodayString,
        goToToday: { choose(today) })
      weekdayRow
      MobileCalendarMonthPager(
        monthOffset: $monthOffset, pageRange: pageRange, weeks: Self.gridWeeks,
        fillsHeight: fillsHeight
      ) { offset in
        page(forOffset: offset, events: events)
      }
    }
    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
  }

  /// The weekday names over the grid's columns, in the locale's week order.
  /// VoiceOver skips them: each day cell reads its full date.
  private var weekdayRow: some View {
    let weekStart = CalendarGridModel.startOfWeek(containing: today, calendar: calendar)
    return HStack(spacing: 0) {
      ForEach(0..<7, id: \.self) { index in
        let day = calendar.date(byAdding: .day, value: index, to: weekStart) ?? weekStart
        Text(LorvexDateFormatters.string(day, template: "EEE", timeZone: calendar.timeZone))
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
          .frame(maxWidth: .infinity)
      }
    }
    .padding(.top, LorvexDesign.Spacing.s)
    .padding(.bottom, LorvexDesign.Spacing.xs)
    .accessibilityHidden(true)
  }

  /// The month `offset` months from today's, wired to the store's actions.
  private func page(forOffset offset: Int, events: [CalendarTimelineEvent]) -> some View {
    let days = CalendarMonthGridModel.buildDays(
      monthAnchor: monthStart(forOffset: offset), calendar: calendar, events: events,
      tasks: store.calendarScheduledTasks, minimumWeeks: Self.gridWeeks,
      dayKeyFor: { Self.keyFormatter.string(from: $0) })
    return MobileCalendarMonthGrid(
      days: days,
      todayKey: store.logicalTodayString,
      selectedKey: selectedKey,
      calendar: calendar,
      choose: { day in
        chooseCount &+= 1
        choose(day.date)
      },
      openEvent: { event in
        store.prepareCalendarDraft(for: event)
        editingEvent = event
      },
      openTask: { task in
        store.cacheTasks([task])
        store.openTaskRouteOnCurrentStack(task.id)
      },
      createEvent: { day in createEvent(on: day) },
      dropTasks: { refs, day in
        Task { @MainActor in
          for ref in refs { await store.planTask(ref.id, on: day) }
        }
      })
  }

  /// The chosen day's agenda, which lists the day even when it is free.
  private func agenda(
    events: [CalendarTimelineEvent], placement: MobileCalendarAgendaPanel.Placement
  ) -> some View {
    MobileStoreCalendarAgenda(
      store: store,
      days: MobileCalendarAgendaDay.days(
        for: [selectedDay], events: events, tasks: store.calendarScheduledTasks,
        keyFor: { Self.keyFormatter.string(from: $0) }),
      calendar: calendar,
      pinnedDayKey: selectedKey,
      placement: placement,
      editEvent: { editingEvent = $0 },
      requestScopedDelete: { eventAwaitingDeleteScope = $0 })
  }

  /// Whether the agenda stands beside the grid rather than under it: in a
  /// regular width of at least 860 points, where Day mode stands its agenda
  /// beside the time grid, and on a phone on its side (a compact height),
  /// where a grid over a list would leave each a sliver of the height.
  nonisolated static func usesSideAgenda(
    width: CGFloat, isRegularWidth: Bool, isCompactHeight: Bool
  ) -> Bool {
    isCompactHeight || (isRegularWidth && width >= 860)
  }

  // MARK: Actions

  static var keyFormatter: DateFormatter { LorvexDateFormatters.ymd }

  /// Chooses `day` and pages to its month, which a day of the next or
  /// previous month needs.
  private func choose(_ day: Date) {
    selectedDay = calendar.startOfDay(for: day)
    let target = offset(showing: day)
    guard target != monthOffset else { return }
    withAnimation { monthOffset = target }
  }

  /// The page of the month containing `day`, within the pager's range.
  private func offset(showing day: Date) -> Int {
    let target = Self.monthOffset(showing: day, currentMonthStart: currentMonthStart, calendar: calendar)
    return min(max(target, pageRange.lowerBound), pageRange.upperBound)
  }

  private func createEvent(on day: Date) {
    store.calendarDraft = .timedDefault(on: day, now: store.now(), calendar: calendar)
    isShowingCreateEvent = true
  }

  /// Switches the calendar to `mode` on the chosen day, which the mode that
  /// replaces this one opens on.
  private func switchMode(to mode: MobileCalendarPresentationMode) {
    store.switchCalendarPresentationMode(to: mode, onDayKey: selectedKey)
  }

  /// Loads the calendar window for the visible month and both neighbors.
  private func loadWindow() async {
    let window = Self.loadWindow(
      forMonthStarting: monthStart(forOffset: monthOffset), weeks: Self.gridWeeks,
      calendar: calendar)
    await store.refreshCalendarTimeline(
      from: Self.keyFormatter.string(from: window.from),
      to: Self.keyFormatter.string(from: window.through))
  }

  /// The page of the month containing `day`, in months from the month that
  /// starts on `currentMonthStart`.
  nonisolated static func monthOffset(
    showing day: Date, currentMonthStart: Date, calendar: Calendar
  ) -> Int {
    let target = CalendarMonthGridModel.startOfMonth(containing: day, calendar: calendar)
    return calendar.dateComponents([.month], from: currentMonthStart, to: target).month ?? 0
  }

  /// The day a month chooses when a swipe pages to it: today in today's
  /// month, else its first day.
  nonisolated static func defaultSelection(
    forMonthStarting monthStart: Date, today: Date, calendar: Calendar
  ) -> Date {
    calendar.isDate(today, equalTo: monthStart, toGranularity: .month)
      ? calendar.startOfDay(for: today) : monthStart
  }

  /// The days the calendar window spans for the month starting on
  /// `monthStart`: from the first day of the previous month's grid through
  /// the last day of the next month's, each grid `weeks` rows long, so a
  /// swipe either way lands on a month already loaded.
  nonisolated static func loadWindow(
    forMonthStarting monthStart: Date, weeks: Int, calendar: Calendar
  ) -> (from: Date, through: Date) {
    let previousMonth = calendar.date(byAdding: .month, value: -1, to: monthStart) ?? monthStart
    let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
    let previous = CalendarMonthGridModel.gridRange(
      forMonthContaining: previousMonth, calendar: calendar, minimumWeeks: weeks)
    let next = CalendarMonthGridModel.gridRange(
      forMonthContaining: nextMonth, calendar: calendar, minimumWeeks: weeks)
    let through = calendar.date(byAdding: .day, value: next.dayCount - 1, to: next.start) ?? next.start
    return (previous.start, through)
  }
}

/// The month grid's horizontal pager, one page per month. A grid that fills
/// the height takes what its container offers; one that does not is `weeks`
/// rows of a fixed height, which grows with the text size up to the largest
/// standard size its container caps the text at.
private struct MobileCalendarMonthPager<Page: View>: View {
  @Binding var monthOffset: Int
  let pageRange: ClosedRange<Int>
  let weeks: Int
  let fillsHeight: Bool
  @ViewBuilder let page: (Int) -> Page
  /// The height of a row that holds a day number in its circle and a line
  /// of marks under it.
  @ScaledMetric(relativeTo: .subheadline) private var rowHeight: CGFloat = 46

  var body: some View {
    TabView(selection: $monthOffset) {
      ForEach(pageRange, id: \.self) { offset in
        page(offset).tag(offset)
      }
    }
    #if os(iOS)
      .tabViewStyle(.page(indexDisplayMode: .never))
    #endif
    .frame(height: fillsHeight ? nil : rowHeight * CGFloat(weeks))
  }
}

import LorvexCore
import SwiftUI

struct CalendarWorkspaceView: View {
  @Bindable var store: AppStore
  /// The create/edit sheet and the delete confirmations, raised from the
  /// inspector, the toolbar, and the event blocks' context menus. Create and
  /// edit share one modal (`CalendarEventSheet`); the read-only
  /// `CalendarEventInspector` stays in the trailing panel behind it.
  @State private var eventActions = CalendarEventActions()
  /// The day the calendar is on, and the one date every mode shows from: Day
  /// shows it, Week the week containing it, Month the month containing it.
  /// Stepping moves it by the visible period and the toolbar chip's popover
  /// marks it, so switching modes always lands on the period that holds the
  /// day the person was looking at.
  @State private var anchorDate: Date
  /// Persisted like the Tasks workspace's `isTableMode`, so the chosen view
  /// (Day/Week/Month) survives navigation and relaunch.
  @AppStorage("calendar.workspace.mode") private var mode: CalendarPresentationMode = .week
  /// Whether the unplanned-tasks rail stands beside the grid. Persisted like the
  /// mode, so it stays as the person left it.
  @AppStorage("calendar.workspace.planRail") private var showsPlanRail = false

  /// The grid (`CalendarWeekGridView`) lays out from `@Environment(\.calendar)`,
  /// so the workspace's week math (step, week range, "is current") reads the same
  /// environment calendar to stay consistent with what's rendered.
  @Environment(\.calendar) var calendar

  /// Opens on the day another surface asked for
  /// (``AppStore/calendarPendingDayKey``), else on today.
  init(store: AppStore) {
    self.store = store
    let calendar = Calendar.current
    _anchorDate = State(
      initialValue: PlannedDayBridge.displayDate(
        forLogicalDay: store.calendarPendingDayKey ?? store.logicalTodayDateString,
        timeZone: calendar.timeZone)
        ?? calendar.startOfDay(for: Date()))
  }

  var body: some View {
    HStack(spacing: 0) {
      calendarColumn
        .frame(maxWidth: .infinity)
      if showsPlanRail {
        Divider()
        CalendarPlanRail(store: store, openTask: { store.selectTaskFromList($0.id) })
          .transition(.move(edge: .trailing).combined(with: .opacity))
      }
      if let event = store.selectedCalendarEvent {
        Divider()
        CalendarEventInspector(
          event: event,
          edit: { eventActions.beginEditing(event, store: store) },
          requestDelete: { eventActions.requestDelete(event) },
          close: { store.clearSelectedCalendarEvent() },
          resolveSource: { await store.calendarEventSource(for: $0) }
        )
        .transition(.move(edge: .trailing).combined(with: .opacity))
      }
    }
    .reduceMotionAnimation(.snappy(duration: 0.18), value: store.selectedCalendarEventID)
    .reduceMotionAnimation(.snappy(duration: 0.18), value: showsPlanRail)
    // The rail's tasks load when it is shown and stop reloading with every task
    // change once it is hidden or the calendar leaves the screen.
    .task(id: showsPlanRail) {
      if showsPlanRail {
        await store.showCalendarUnplannedTasks()
      } else {
        store.hideCalendarUnplannedTasks()
      }
    }
    .onDisappear { store.hideCalendarUnplannedTasks() }
    .calendarEventActions(eventActions, store: store)
    .focusedSceneValue(
      \.lorvexCalendarCommandContext,
      LorvexCalendarCommandContext(
        mode: $mode, showsPlanRail: $showsPlanRail, isViewingCurrent: isViewingCurrent,
        jumpToCurrent: jumpToCurrent))
  }

  private var calendarColumn: some View {
    VStack(spacing: 0) {
      // One title row only: the range, the view mode, and the create action
      // ride in the window toolbar, so the header only names the surface,
      // leaving the vertical band to the grid.
      CalendarWorkspaceHeader()

      Divider()

      switch mode {
      case .day:
        CalendarWeekGridView(
          store: store,
          weekStart: visiblePeriod.start,
          visibleDayCount: 1,
          selectEvent: { store.toggleCalendarEventSelection($0) },
          editEvent: { eventActions.beginEditing($0, store: store) },
          requestDeleteEvent: { eventActions.requestDelete($0) },
          openTask: { task in
            store.selectTaskFromList(task.id)
          },
          createAt: { date, minutes, duration in
            prepareCreateDraft(date: date, minutes: minutes, durationMinutes: duration)
            eventActions.activeSheet = .create
          }
        )
      case .week:
        CalendarWeekGridView(
          store: store,
          weekStart: weekStart,
          selectEvent: { store.toggleCalendarEventSelection($0) },
          editEvent: { eventActions.beginEditing($0, store: store) },
          requestDeleteEvent: { eventActions.requestDelete($0) },
          openTask: { task in
            store.selectTaskFromList(task.id)
          },
          createAt: { date, minutes, duration in
            prepareCreateDraft(date: date, minutes: minutes, durationMinutes: duration)
            eventActions.activeSheet = .create
          }
        )
      case .month:
        CalendarMonthGridView(
          store: store,
          monthAnchor: monthAnchor,
          selectEvent: { store.toggleCalendarEventSelection($0) },
          editEvent: { eventActions.beginEditing($0, store: store) },
          requestDeleteEvent: { eventActions.requestDelete($0) },
          openTask: { task in
            store.selectTaskFromList(task.id)
          },
          openDay: { navigateToDay($0) },
          createEvent: { createEvent(on: $0) }
        )
      }
    }
    .navigationTitle(String(localized: SidebarSelection.calendar.macOSLocalizedTitle))
    .toolbar {
      CalendarWorkspaceToolbar(
        anchorDate: $anchorDate,
        mode: $mode,
        showsPlanRail: $showsPlanRail,
        weekRangeTitle: weekRangeTitle,
        monthRangeTitle: monthRangeTitle,
        isViewingCurrent: isViewingCurrent,
        step: step,
        jumpToCurrent: jumpToCurrent,
        createEvent: { eventActions.beginCreating(store: store) }
      )
    }
    .lorvexOpenDestinationActivity(selection: .calendar, isActive: store.selection == .calendar)
    // A step, a day picked outside the visible period, and a mode switch all
    // change the period on screen; a day picked inside it changes nothing.
    .onChange(of: visiblePeriod) { _, _ in
      fetchVisiblePeriod()
    }
    .onChange(of: store.today) { _, _ in
      // A task mutation (defer / complete / move / batch) updates `today`.
      // Refetch the visible timeline so scheduled-task pills reflect mutations
      // across the day/week/month window instead of the Today snapshot
      // truncating them. This view is mounted only while the calendar is on
      // screen.
      fetchVisiblePeriod()
    }
    // A day asked for while the calendar is on screen moves it there. One
    // asked for before it appeared already chose its first day in `init`, so
    // appearing only clears it.
    .onChange(of: store.calendarPendingDayKey) { _, dayKey in
      guard let dayKey else { return }
      if let day = PlannedDayBridge.displayDate(forLogicalDay: dayKey, timeZone: calendar.timeZone) {
        anchorDate = day
      }
      store.calendarPendingDayKey = nil
    }
    .onAppear {
      store.calendarPendingDayKey = nil
      fetchVisiblePeriod()
    }
    .task {
      // The day and week headers size each day's load against the working
      // window; Today loads it too, but Plan can be the first workspace opened.
      if store.workdayEndMinutes == nil { await store.loadWorkdayWindow() }
    }
  }

  /// The first day of the week containing `anchorDate`: the week grid's first
  /// column.
  private var weekStart: Date {
    CalendarPresentationMode.week.periodStart(containing: anchorDate, calendar: calendar)
  }

  /// The first day of the month containing `anchorDate`.
  private var monthAnchor: Date {
    CalendarPresentationMode.month.periodStart(containing: anchorDate, calendar: calendar)
  }

  private var visiblePeriod: CalendarVisiblePeriod {
    CalendarVisiblePeriod(mode: mode, anchor: anchorDate, calendar: calendar)
  }

  private var isViewingCurrent: Bool {
    let today = logicalTodayAnchor
    switch mode {
    case .day:
      return calendar.isDate(anchorDate, inSameDayAs: today)
    case .week:
      return calendar.isDate(
        weekStart,
        inSameDayAs: CalendarGridModel.startOfWeek(
          containing: today, calendar: calendar))
    case .month:
      return calendar.isDate(
        monthAnchor,
        equalTo: CalendarMonthGridModel.startOfMonth(containing: today, calendar: calendar),
        toGranularity: .month)
    }
  }

  private var logicalTodayAnchor: Date {
    PlannedDayBridge.displayDate(
      forLogicalDay: store.logicalTodayDateString,
      timeZone: calendar.timeZone)
      ?? calendar.startOfDay(for: Date())
  }

  private var weekRangeTitle: String {
    let end = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
    return LorvexDateFormatters.range(
      from: weekStart, to: end, template: "MMMd", timeZone: calendar.timeZone)
  }

  private var monthRangeTitle: String {
    LorvexDateFormatters.string(
      monthAnchor, template: "yMMMM", timeZone: calendar.timeZone, position: .leading)
  }

  /// Moves `anchorDate` by one visible period. A week step keeps the weekday
  /// and a month step the day of the month, so a later switch to Day opens the
  /// matching day of the new period.
  private func step(_ direction: Int) {
    anchorDate = mode.anchor(anchorDate, steppedBy: direction, calendar: calendar)
  }

  private func jumpToCurrent() {
    anchorDate = logicalTodayAnchor
  }

  /// Opens the create-event sheet for a month-grid day: an event today starts at
  /// the next full hour, like the toolbar's, and one on another day at 9 AM.
  private func createEvent(on day: Date) {
    if calendar.isDate(day, inSameDayAs: logicalTodayAnchor) {
      eventActions.beginCreating(store: store)
    } else {
      prepareCreateDraft(date: day, minutes: 9 * 60)
      eventActions.activeSheet = .create
    }
  }

  /// Opens a month-grid cell's day in Day mode.
  private func navigateToDay(_ date: Date) {
    anchorDate = date
    mode = .day
  }

  /// Loads the visible period's timeline. Day and Week load the store's
  /// default window from their first day, which also covers the next step;
  /// Month loads exactly the whole weeks its grid shows.
  private func fetchVisiblePeriod() {
    let period = visiblePeriod
    let monthGrid = CalendarMonthGridModel.gridRange(
      forMonthContaining: period.start, calendar: calendar)
    Task {
      do {
        switch period.mode {
        case .day, .week:
          try await store.refreshCalendarTimeline(anchorDate: period.start)
        case .month:
          try await store.refreshCalendarTimeline(
            anchorDate: monthGrid.start, dayCount: monthGrid.dayCount)
        }
      } catch {
        store.toastMessage = Self.timelineLoadErrorMessage
      }
    }
  }

  /// Actionable hint instead of the raw EventKit/sync error, whose
  /// `localizedDescription` ("…(LorvexSync.EnqueueError error 2.)") is meaningless
  /// to a user. A failed timeline load is almost always missing calendar access.
  private static var timelineLoadErrorMessage: String {
    String(
      localized: "calendar.timeline.load_error",
      defaultValue:
        "Couldn’t load calendar events. Check that Lorvex has calendar access in System Settings.",
      table: "Localizable",
      bundle: LorvexL10n.bundle
    )
  }

}

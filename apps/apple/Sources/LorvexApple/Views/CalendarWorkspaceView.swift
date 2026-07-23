import LorvexCore
import SwiftUI

struct CalendarWorkspaceView: View {
  @Bindable var store: AppStore
  /// The create/edit sheet currently presented, or nil when none. Create and
  /// edit share one modal (`CalendarEventSheet`) for a consistent surface + size;
  /// the read-only `CalendarEventInspector` stays in the trailing panel behind it.
  @State private var activeSheet: CalendarEventSheet.Mode?
  /// Staged for the delete confirmation / occurrence-scope dialog raised from the
  /// inspector (or the event block's context menu).
  @State private var deletingEvent: CalendarTimelineEvent?
  @State private var isShowingDeleteScope = false
  @State private var anchorDate: Date
  /// Persisted like the Tasks workspace's `isTableMode`, so the chosen view
  /// (Day/Week/Month) survives navigation and relaunch.
  @AppStorage("calendar.workspace.mode") private var mode: CalendarPresentationMode = .week
  @State private var weekStart: Date
  @State private var monthAnchor: Date

  /// The grid (`CalendarWeekGridView`) lays out from `@Environment(\.calendar)`,
  /// so the workspace's week math (step, week range, "is current") reads the same
  /// environment calendar to stay consistent with what's rendered.
  @Environment(\.calendar) var calendar

  init(store: AppStore) {
    self.store = store
    let calendar = Calendar.current
    let today =
      PlannedDayBridge.displayDate(
        forLogicalDay: store.logicalTodayDateString,
        calendar: calendar)
      ?? calendar.startOfDay(for: Date())
    _anchorDate = State(initialValue: today)
    _weekStart = State(
      initialValue: CalendarGridModel.startOfWeek(containing: today, calendar: calendar))
    _monthAnchor = State(
      initialValue: CalendarMonthGridModel.startOfMonth(containing: today, calendar: calendar))
  }

  var body: some View {
    HStack(spacing: 0) {
      calendarColumn
        .frame(maxWidth: .infinity)
      if let event = store.selectedCalendarEvent {
        Divider()
        CalendarEventInspector(
          event: event,
          edit: { beginEditing(event) },
          requestDelete: { requestDeleteEvent(event) },
          close: { store.clearSelectedCalendarEvent() },
          resolveSource: { await store.calendarEventSource(for: $0) }
        )
        .transition(.move(edge: .trailing).combined(with: .opacity))
      }
    }
    .animation(.snappy(duration: 0.18), value: store.selectedCalendarEventID)
    .confirmationDialog(
      deletingEvent.map {
        String(
          format: String(
            localized: "calendar.delete_event.confirm.title",
            defaultValue: "Delete event \u{201C}%@\u{201D}?",
            table: "Localizable",
            bundle: LorvexL10n.bundle),
          $0.title)
      } ?? "",
      isPresented: Binding(
        get: { deletingEvent != nil && !isShowingDeleteScope },
        set: { if !$0 { deletingEvent = nil } }
      ),
      titleVisibility: .visible
    ) {
      Button(
        String(
          localized: "common.delete", defaultValue: "Delete", table: "Localizable",
          bundle: LorvexL10n.bundle), role: .destructive
      ) {
        if let event = deletingEvent {
          deletingEvent = nil
          Task { await store.deleteCalendarEvent(event) }
        }
      }
      Button(
        String(
          localized: "common.keep", defaultValue: "Keep", table: "Localizable",
          bundle: LorvexL10n.bundle), role: .cancel
      ) {
        deletingEvent = nil
      }
    }
    .confirmationDialog(
      String(
        localized: "calendar.delete_event.scope.title",
        defaultValue: "Delete this repeating event?",
        table: "Localizable",
        bundle: LorvexL10n.bundle),
      isPresented: $isShowingDeleteScope,
      titleVisibility: .visible
    ) {
      Button(
        String(
          localized: "calendar.recurring_scope.this_event", defaultValue: "This Event",
          table: "Localizable", bundle: LorvexL10n.bundle)
      ) {
        runScopedDelete(.thisEvent)
      }
      Button(
        String(
          localized: "calendar.recurring_scope.this_and_following",
          defaultValue: "This and Following Events",
          table: "Localizable",
          bundle: LorvexL10n.bundle)
      ) {
        runScopedDelete(.thisAndFollowing)
      }
      Button(
        String(
          localized: "calendar.recurring_scope.all_events", defaultValue: "All Events",
          table: "Localizable", bundle: LorvexL10n.bundle), role: .destructive
      ) {
        runScopedDelete(.allEvents)
      }
      Button(
        String(
          localized: "common.cancel", defaultValue: "Cancel", table: "Localizable",
          bundle: LorvexL10n.bundle), role: .cancel
      ) {
        isShowingDeleteScope = false
        deletingEvent = nil
      }
    }
  }

  /// Open `event`'s edit form: select it so the read-only inspector stays
  /// anchored behind the sheet, stage its draft, then present the shared
  /// create/edit sheet in edit mode. Used by both the inspector's Edit button
  /// and the grid blocks' edit affordance.
  private func beginEditing(_ event: CalendarTimelineEvent) {
    store.selectCalendarEvent(event)
    store.prepareCalendarDraft(for: event)
    activeSheet = .edit(event)
    // The event's calendar lives only in the EventKit mirror, so resolve it live
    // to preselect the form's calendar picker (defaults to Lorvex until it lands).
    Task { await store.resolveDraftTargetCalendar(for: event) }
  }

  /// Stage `event` for deletion: recurring events choose an occurrence scope, a
  /// plain event gets a single confirmation. Both run from `body`'s dialogs.
  private func requestDeleteEvent(_ event: CalendarTimelineEvent) {
    guard event.editable else { return }
    deletingEvent = event
    isShowingDeleteScope = event.supportsScopedMutation
  }

  private func runScopedDelete(_ scope: CalendarEventEditScope) {
    guard let event = deletingEvent else { return }
    deletingEvent = nil
    isShowingDeleteScope = false
    Task { await store.deleteScopedCalendarEvent(event, scope: scope) }
  }

  private var calendarColumn: some View {
    VStack(spacing: 0) {
      // No in-content "Calendar" title row: the window title bar already names
      // the surface and the nav bar carries the date range. Dropping the
      // WorkspaceHeader reclaims the vertical band for the timeline grid, the
      // way Apple's own Calendar week view does.
      CalendarWorkspaceNavigationBar(
        anchorDate: $anchorDate,
        mode: $mode,
        weekRangeTitle: weekRangeTitle,
        monthRangeTitle: monthRangeTitle,
        isViewingCurrent: isViewingCurrent,
        eventCount: store.filteredCalendarEvents.count,
        plannedTaskCount: store.filteredScheduledTasks.count,
        isFiltering: store.hasActiveSearch,
        step: step,
        jumpToCurrent: jumpToCurrent
      ) {
        CalendarWorkspaceHeaderActions(
          createEvent: {
            store.beginCreateCalendarDraft()
            activeSheet = .create
          }
        )
      }

      Divider()

      switch mode {
      case .day:
        CalendarWeekGridView(
          store: store,
          weekStart: anchorDate,
          visibleDayCount: 1,
          selectEvent: { store.toggleCalendarEventSelection($0) },
          editEvent: { beginEditing($0) },
          requestDeleteEvent: { requestDeleteEvent($0) },
          openTask: { task in
            store.selectTaskFromList(task.id)
          },
          createAt: { date, minutes, duration in
            prepareCreateDraft(date: date, minutes: minutes, durationMinutes: duration)
            activeSheet = .create
          }
        )
      case .week:
        CalendarWeekGridView(
          store: store,
          weekStart: weekStart,
          selectEvent: { store.toggleCalendarEventSelection($0) },
          editEvent: { beginEditing($0) },
          requestDeleteEvent: { requestDeleteEvent($0) },
          openTask: { task in
            store.selectTaskFromList(task.id)
          },
          createAt: { date, minutes, duration in
            prepareCreateDraft(date: date, minutes: minutes, durationMinutes: duration)
            activeSheet = .create
          }
        )
      case .month:
        CalendarMonthGridView(
          store: store,
          monthAnchor: monthAnchor,
          selectEvent: { store.toggleCalendarEventSelection($0) },
          openTask: { task in
            store.selectTaskFromList(task.id)
          },
          openDay: { navigateToDay($0) }
        )
      }
    }
    .sheet(item: $activeSheet, onDismiss: { store.restoreStashedCalendarDraft() }) { mode in
      CalendarEventSheet(store: store, mode: mode, dismiss: { activeSheet = nil })
    }
    .navigationTitle(String(localized: SidebarSelection.calendar.macOSLocalizedTitle))
    .lorvexOpenDestinationActivity(selection: .calendar, isActive: store.selection == .calendar)
    .onChange(of: anchorDate) { _, newDate in
      switch mode {
      case .week:
        // The week navigator's date chip picks a single day; jump to the week
        // containing it. The grid renders from `weekStart`, so re-derive it —
        // its own onChange refetches the visible week.
        let newWeekStart = CalendarGridModel.startOfWeek(containing: newDate, calendar: calendar)
        if newWeekStart != weekStart { weekStart = newWeekStart }
      case .month:
        // Same idea for the month grid: the chip picks a single day, jump to
        // the month containing it. `monthAnchor`'s own onChange refetches.
        let newMonthAnchor = CalendarMonthGridModel.startOfMonth(
          containing: newDate, calendar: calendar)
        if newMonthAnchor != monthAnchor { monthAnchor = newMonthAnchor }
      case .day:
        fetchVisibleDay(newDate)
      }
    }
    .onChange(of: weekStart) { _, newWeekStart in
      guard mode == .week else { return }
      // Keep the navigator's date chip aligned to the visible week (stepping
      // weeks moves weekStart; the chip reads anchorDate). Re-deriving weekStart
      // from this is idempotent, so the anchorDate↔weekStart sync terminates.
      if anchorDate != newWeekStart { anchorDate = newWeekStart }
      fetchVisibleWeek(newWeekStart)
    }
    .onChange(of: monthAnchor) { _, newMonthAnchor in
      guard mode == .month else { return }
      // Same anchorDate↔weekStart sync, mirrored for the month grid.
      if !calendar.isDate(anchorDate, equalTo: newMonthAnchor, toGranularity: .month) {
        anchorDate = newMonthAnchor
      }
      fetchVisibleMonth(newMonthAnchor)
    }
    .onChange(of: mode) { _, newMode in
      switch newMode {
      case .day:
        fetchVisibleDay(anchorDate)
      case .week:
        fetchVisibleWeek(weekStart)
      case .month:
        fetchVisibleMonth(monthAnchor)
      }
    }
    .onChange(of: store.today) { _, _ in
      // A task mutation (defer / complete / move / batch) updates `today`.
      // Refetch the visible timeline so scheduled-task pills reflect mutations
      // across the day/week/month window instead of the Today snapshot
      // truncating them. This view is mounted only while the calendar is on
      // screen.
      switch mode {
      case .day:
        fetchVisibleDay(anchorDate)
      case .week:
        fetchVisibleWeek(weekStart)
      case .month:
        fetchVisibleMonth(monthAnchor)
      }
    }
    .onAppear {
      switch mode {
      case .day:
        fetchVisibleDay(anchorDate)
      case .week:
        fetchVisibleWeek(weekStart)
      case .month:
        fetchVisibleMonth(monthAnchor)
      }
    }
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
      calendar: calendar)
      ?? calendar.startOfDay(for: Date())
  }

  private var weekRangeTitle: String {
    let end = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
    let f = LorvexMonthDayFormatter.local
    return "\(f.string(from: weekStart)) – \(f.string(from: end))"
  }

  private var monthRangeTitle: String {
    Self.monthTitleFormatter.string(from: monthAnchor)
  }

  private func step(_ direction: Int) {
    switch mode {
    case .week:
      weekStart =
        calendar.date(byAdding: .day, value: 7 * direction, to: weekStart) ?? weekStart
    case .day:
      anchorDate = calendar.date(byAdding: .day, value: direction, to: anchorDate) ?? anchorDate
    case .month:
      monthAnchor =
        calendar.date(byAdding: .month, value: direction, to: monthAnchor) ?? monthAnchor
    }
  }

  private func jumpToCurrent() {
    let today = logicalTodayAnchor
    switch mode {
    case .week:
      weekStart = CalendarGridModel.startOfWeek(containing: today, calendar: calendar)
    case .day:
      anchorDate = today
    case .month:
      monthAnchor = CalendarMonthGridModel.startOfMonth(containing: today, calendar: calendar)
    }
  }

  /// Selects `date`'s day (reusing the same day/week navigation the Day-mode
  /// date chip and stepper drive) from a month-grid cell click. Sets `mode`
  /// before `anchorDate` so the `anchorDate` `onChange` handler above already
  /// sees `.day` and fetches the clicked date directly — the `mode` change's
  /// own `onChange` fires first with the stale `anchorDate`, but that fetch is
  /// immediately superseded by the correct one via the timeline load token.
  private func navigateToDay(_ date: Date) {
    mode = .day
    anchorDate = date
  }

  private func fetchVisibleWeek(_ start: Date) {
    Task {
      do {
        try await store.refreshCalendarTimeline(anchorDate: start)
      } catch {
        store.toastMessage = Self.timelineLoadErrorMessage
      }
    }
  }

  private func fetchVisibleDay(_ day: Date) {
    Task {
      do {
        try await store.refreshCalendarTimeline(anchorDate: day)
      } catch {
        store.toastMessage = Self.timelineLoadErrorMessage
      }
    }
  }

  private func fetchVisibleMonth(_ anchor: Date) {
    let range = CalendarMonthGridModel.gridRange(forMonthContaining: anchor, calendar: calendar)
    Task {
      do {
        try await store.refreshCalendarTimeline(anchorDate: range.start, dayCount: range.dayCount)
      } catch {
        store.toastMessage = Self.timelineLoadErrorMessage
      }
    }
  }

  private static let monthTitleFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.setLocalizedDateFormatFromTemplate("yyyyMMMM")
    return formatter
  }()

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

import LorvexCore
import SwiftUI

/// The menu bar panel (a `.window`-style `MenuBarExtra`): the day at a glance
/// and the week ahead. The date with a Today / Next 7 Days switch, one
/// sentence of facts, and a one-line quick-add stay put; under them a
/// scrolling body that grows with its content up to ``bodyMaxHeight``.
///
/// Today reads the same ``LorvexCalmToday`` and the same schedule as the Today
/// workspace, without the workspace's search filter, so the two never
/// disagree about the day (``MenuBarTodayContent``): the lead task set
/// larger, then what is still ahead on the clock, the tasks without a time,
/// the habits (checked in from their rings), and how much is done. Next 7
/// Days is the agenda of the seven days after today (``LorvexAgendaDay``).
/// A task or an event clicked in either opens in the main window. The panel
/// advances with the clock while it is open.
struct MenuBarStatusView: View {
  @Bindable var store: AppStore
  @Environment(\.openWindow) private var openWindow
  @Environment(\.undoManager) private var undoManager
  /// Claimed when the panel opens so the user can type a capture immediately.
  @FocusState private var quickAddFocused: Bool
  /// The menu-bar capture's own draft, so half-typed text here never bleeds
  /// into a capture field in the main window.
  @State private var quickAddText: String
  /// The scope the panel last showed, kept across openings.
  @AppStorage("menubar.scope") private var scope: MenuBarScope = .today

  /// The tallest the scrolling body grows before it scrolls, which keeps the
  /// whole panel near 600pt.
  private static let bodyMaxHeight: CGFloat = 440

  /// `initialQuickAdd` opens the panel with a capture line already typed; the
  /// preview tour uses it to capture the recognized-details state.
  init(store: AppStore, initialQuickAdd: String = "") {
    self.store = store
    _quickAddText = State(initialValue: initialQuickAdd)
  }

  var body: some View {
    TimelineView(.everyMinute) { _ in
      let nowMinutes = store.nowMinutesInProductDay
      panel(store.calmToday(nowMinutes: nowMinutes), nowMinutes: nowMinutes)
    }
    .frame(width: 340)
    .tint(.accentColor)
    .task {
      quickAddFocused = false
      await Task.yield()
      quickAddFocused = true
      await load()
    }
    .onChange(of: store.today) {
      Task { await store.loadDoneTodayCount() }
    }
    .onChange(of: store.taskDataGeneration) {
      Task { await store.loadDoneTodayCount() }
    }
    .onChange(of: scope) { _, newScope in
      guard newScope == .week else { return }
      Task { await ensureWeekLoaded() }
    }
  }

  private func panel(_ page: LorvexCalmToday, nowMinutes: Int?) -> some View {
    let weekDays = LorvexAgendaDay.build(
      todayKey: store.logicalTodayDateString,
      events: store.calendarTimeline?.events ?? [],
      tasks: store.calendarScheduledTasks ?? [])
    // A free week has nothing to list: the headline above already says so.
    let showsBody = scope == .today || !weekDays.isEmpty
    return VStack(spacing: 0) {
      header(page, weekDays: weekDays)
        .padding(.horizontal, LorvexDesign.Spacing.m)
        .padding(.top, LorvexDesign.Spacing.m)
        .padding(.bottom, LorvexDesign.Spacing.s)

      quickAdd
        .padding(.horizontal, LorvexDesign.Spacing.m)
        .padding(.bottom, LorvexDesign.Spacing.m)

      if showsBody {
        Divider()

        ScrollView {
          Group {
            switch scope {
            case .today:
              MenuBarTodayContent(
                page: page, events: store.todayScheduleEvents, logicalDay: store.logicalTodayDateString,
                nowMinutes: nowMinutes,
                habits: store.habits?.habits.filter { !$0.archived }.listed(on: store.logicalTodayDateString) ?? [],
                isOverdue: { store.isOverdue($0) },
                complete: { task in
                  Task { await store.toggleTaskCompletion(task, undoManager: undoManager) }
                },
                open: open,
                openEvent: { event in
                  store.showEventInToday(event)
                  perform(.openMain)
                },
                checkIn: checkIn)
            case .week:
              MenuBarAgendaList(
                days: weekDays,
                todayKey: store.logicalTodayDateString,
                complete: { task in
                  Task { await store.toggleTaskCompletion(task, undoManager: undoManager) }
                },
                open: { task in openRoute(.task(task.id)) },
                openEvent: { event, dayKey in
                  store.showEventInCalendar(event, onDayKey: dayKey)
                  perform(.openMain)
                })
            }
          }
          .padding(LorvexDesign.Spacing.m)
          .reduceMotionAnimation(.snappy(duration: 0.25), value: page)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: Self.bodyMaxHeight)
        .fixedSize(horizontal: false, vertical: true)
      }

      Divider()

      footer
        .padding(LorvexDesign.Spacing.s)
    }
  }

  /// The panel reads the same loads as the Today workspace, so it is complete
  /// even before that workspace has been opened this launch.
  private func load() async {
    async let todaySchedule: Void = store.loadTodaySchedule()
    async let doneCount: Void = store.loadDoneTodayCount()
    async let hours = store.loadWorkdayWindow()
    _ = await (todaySchedule, doneCount, hours)
    if scope == .week { await ensureWeekLoaded() }
  }

  /// Next 7 Days reads the calendar window the Calendar workspace shares;
  /// when that window ends before the seventh day ahead, a today-anchored
  /// window replaces it.
  private func ensureWeekLoaded() async {
    let today = store.logicalTodayDateString
    guard let lastDay = LorvexDateFormatters.ymdUTCAddingDays(today, days: 7) else { return }
    if let timeline = store.calendarTimeline, timeline.from <= today, lastDay <= timeline.to { return }
    do {
      try await store.refreshCalendarTimeline()
    } catch {
      await store.presentUserFacingError(error)
    }
  }

  // MARK: - Header

  /// The date, the scope switch, and a sentence about what the scope shows:
  /// today's facts, or what the next seven days hold.
  private func header(_ page: LorvexCalmToday, weekDays: [LorvexAgendaDay]) -> some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
      dateAndScope
      Text(headline(page, weekDays: weekDays), serifVoice: .panelSentence)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("menubar.headline")
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// The date beside the scope switch. The switch keeps the width its labels
  /// need, and a translated "Next 7 Days" can take more than half the panel,
  /// so the date has three forms and the first that fits is shown: the
  /// spelled-out date, its short form, and the spelled-out date above the
  /// switch.
  private var dateAndScope: some View {
    let day = store.logicalTodayDateString
    return ViewThatFits(in: .horizontal) {
      HStack(alignment: .center, spacing: LorvexDesign.Spacing.s) {
        dateLabel(TodayCalmCopy.dateLine(logicalDay: day))
        Spacer(minLength: 0)
        scopePicker
      }
      HStack(alignment: .center, spacing: LorvexDesign.Spacing.s) {
        dateLabel(TodayCalmCopy.shortDateLine(logicalDay: day))
        Spacer(minLength: 0)
        scopePicker
      }
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
        dateLabel(TodayCalmCopy.dateLine(logicalDay: day))
        scopePicker
      }
    }
  }

  private func dateLabel(_ text: String) -> some View {
    Text(text)
      .font(LorvexDesign.Typography.pageLabel)
      .foregroundStyle(.secondary)
      .lineLimit(1)
      .accessibilityIdentifier("menubar.date")
  }

  private var scopePicker: some View {
    Picker(MenuBarScope.pickerLabel, selection: $scope) {
      ForEach(MenuBarScope.allCases) { scope in
        Text(scope.title).tag(scope)
      }
    }
    .pickerStyle(.segmented)
    .labelsHidden()
    .controlSize(.small)
    .fixedSize()
    .accessibilityIdentifier("menubar.scope")
  }

  private func headline(_ page: LorvexCalmToday, weekDays: [LorvexAgendaDay]) -> String {
    switch scope {
    case .today:
      return TodayCalmCopy.sentence(page.facts)
    case .week:
      // An event spanning several days appears under each; count it once.
      let events = Set(weekDays.flatMap { $0.events.map(\.id) }).count
      return TodayCalmCopy.weekSentence(tasks: weekDays.reduce(0) { $0 + $1.tasks.count }, events: events)
    }
  }

  // MARK: - Quick add

  /// One field: type a line and press Return to capture a task into the inbox.
  /// The line may carry details ("Call mom tomorrow 5pm"); once one is
  /// recognized, the words it will become show under the field, as in the
  /// main window's quick-add rows. No notes field and no separate button — the
  /// lightest possible capture.
  private var quickAdd: some View {
    let preview = store.quickAddPreview(quickAddText)
    return VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
      HStack(spacing: LorvexDesign.Spacing.s) {
        Image(systemName: "plus.circle.fill")
          .foregroundStyle(.tint)
        TextField(
          String(
            localized: "menubar.quick_add", defaultValue: "Add a task, then press Return",
            table: "Localizable",
            bundle: LorvexL10n.bundle),
          text: $quickAddText
        )
        .textFieldStyle(.plain)
        .font(LorvexDesign.Typography.secondaryText)
        .focused($quickAddFocused)
        .onSubmit { submitQuickAdd() }
        .lorvexSingleLine($quickAddText)
        .accessibilityIdentifier("menubar.quickAdd")
      }
      .padding(.horizontal, LorvexDesign.Spacing.s)
      .padding(.vertical, LorvexDesign.Spacing.sm)
      .background(.quaternary.opacity(0.5), in: Capsule())

      if !preview.words.isEmpty {
        QuickAddPreviewLine(preview: preview)
          .padding(.horizontal, LorvexDesign.Spacing.s)
          .transition(.opacity)
      }
    }
    .reduceMotionAnimation(.snappy(duration: 0.18), value: preview.words.isEmpty)
  }

  /// Capture the typed line (like the command palette), then clear the field.
  private func submitQuickAdd() {
    let line = quickAddText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !line.isEmpty else { return }
    quickAddText = ""
    Task { await store.captureLine(line) }
  }

  // MARK: - Habits

  /// A ring tap: a single check-in habit toggles today; a habit counted
  /// several times a day adds one until it meets its target, and is cleared
  /// only from the Habits workspace, so a stray click never wipes a day.
  private func checkIn(_ habit: LorvexHabit) {
    Task {
      switch LorvexHabitCheckIn.action(for: habit) {
      case .complete: await store.completeHabit(habit)
      case .uncomplete: await store.uncompleteHabit(habit)
      case .addOne: await store.adjustHabitCompletion(habit, delta: 1)
      case .none: break
      }
    }
  }

  // MARK: - Footer

  private var footer: some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      Button {
        perform(.openMain)
      } label: {
        Label(
          String(localized: "menubar.action.open_app", defaultValue: "Open Lorvex", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "arrow.up.forward.app")
      }
      .buttonStyle(.borderless)

      Spacer(minLength: 0)

      footerIcon(.quit, "power")
    }
  }

  private func footerIcon(_ action: MenuBarStatusAction, _ systemImage: String) -> some View {
    Button {
      perform(action)
    } label: {
      Image(systemName: systemImage)
        .frame(width: 18, height: 18)
    }
    .buttonStyle(.borderless)
    .foregroundStyle(.secondary)
    .help(action.title)
    .accessibilityLabel(action.title)
    .accessibilityIdentifier("menubar.action.\(action)")
  }

  // MARK: - Opening the app

  /// Show the task in the Today workspace of the main window.
  private func open(_ task: LorvexTask) {
    store.selection = .today
    store.selectOnlyTodayTask(task.id)
    perform(.openMain)
  }

  /// Show a task that is not on today's list where it lives: the Tasks
  /// workspace with its detail loaded.
  private func openRoute(_ route: LorvexDeepLinkRoute) {
    Task { await store.openDeepLinkRoute(route) }
    perform(.openMain)
  }

  private func perform(_ action: MenuBarStatusAction) {
    LorvexCommandDispatcher(
      store: store,
      openWindow: { windowID in openWindow(windowID) },
      activateApplication: { NSApp.activate() },
      terminateApplication: { NSApplication.shared.terminate(nil) }
    )
    .perform(action.commandAction)
  }
}

/// What the menu bar panel's body shows: today, or the seven days after it.
enum MenuBarScope: String, CaseIterable, Identifiable {
  case today
  case week

  var id: String { rawValue }

  var title: String {
    switch self {
    case .today:
      String(localized: "menubar.scope.today", defaultValue: "Today", table: "Localizable", bundle: LorvexL10n.bundle)
    case .week:
      String(
        localized: "menubar.scope.week", defaultValue: "Next 7 Days", table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }

  static var pickerLabel: String {
    String(localized: "menubar.scope.label", defaultValue: "Show", table: "Localizable", bundle: LorvexL10n.bundle)
  }
}

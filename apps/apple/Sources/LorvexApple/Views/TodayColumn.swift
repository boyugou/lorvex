import LorvexCore
import SwiftUI

/// Today's main column: the whole day in one column, every task on it once.
///
/// The date and one line of facts open it, then the assistant's briefing and,
/// when the day holds more estimated work than free working time, one decision
/// that offers to move the least urgent work to tomorrow. Then the day on the
/// clock (``TodayScheduleSection``): calendar events and timed tasks in time
/// order. Then the tasks without a time, started ones first, the rest in the
/// canonical order; under a "Tasks" label only when a schedule stands above
/// them. The quick-add field and what is already done close the column; Done
/// folds on request, since it is a record rather than work, and leaves out
/// finished timed tasks, which keep their place in the schedule.
struct TodayColumn: View {
  @Bindable var store: AppStore
  /// The day as of this render, built once (``AppStore/todayColumnContent``).
  let content: TodayColumnContent
  @State private var planningDay: String?
  @State private var tomorrowAgenda: LorvexAgendaDay?
  @State private var loadingAgenda = true
  @Environment(\.undoManager) private var undoManager
  @State private var showsFullBriefing = false
  /// Whether the three-line limit cuts the briefing at the column's current
  /// width, which is what brings the "Show more" toggle.
  @State private var briefingHidesText = false

  private var page: LorvexCalmToday { content.page }
  private var nowMinutes: Int? { content.nowMinutes }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      if let item = content.featured, let cue = content.workCue {
        TodayTaskRow(
          task: item.task, store: store, isBlocked: store.isBlocked(item.task),
          timeLabel: item.time.map { TodayCalmCopy.timeRange(start: $0.lowerBound, end: $0.upperBound) },
          timeIsRunning: item.isRunning, chips: Self.chips(for: item), workCue: cue)
        .padding(LorvexDesign.Spacing.s)
        .background(LorvexDesign.Palette.insetFill, in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.m))
        .padding(.top, LorvexDesign.Spacing.m)
        .id(item.id)
      }
      if let catalog = store.habits, !catalog.habits.isEmpty {
        routine(catalog).padding(.top, LorvexDesign.Spacing.m)
      }
      if let overbooked = page.overbooked {
        overbookedWell(overbooked)
          .padding(.top, LorvexDesign.Spacing.l)
      }
      if showsSchedule {
        TodayScheduleSection(
          store: store, rows: content.schedule, nowMinutes: nowMinutes, workCue: content.workCue,
          items: Dictionary(page.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }))
          .padding(.top, LorvexDesign.Spacing.l)
      }
      if !untimedItems.isEmpty {
        VStack(alignment: .leading, spacing: 0) {
          if showsSchedule {
            TodayColumnLabel(title: TodayCalmCopy.tasksTitle)
          }
          taskList
        }
        .padding(.top, LorvexDesign.Spacing.l)
      } else if page.items.isEmpty, !showsSchedule, let nowMinutes {
        LorvexSunArc(
          nowMinutes: nowMinutes, startLabel: TodayCalmCopy.sunStart, endLabel: TodayCalmCopy.sunEnd
        )
        .frame(height: 150)
        .padding(.horizontal, LorvexDesign.Spacing.xl)
        .padding(.top, LorvexDesign.Spacing.l)
        .accessibilityIdentifier("today.sun")
      }
      QuickAddRow(
        placeholder: String(
          localized: "today.quick_add.placeholder", defaultValue: "Add a task for today",
          table: "Localizable", bundle: LorvexL10n.bundle),
        focusToken: store.quickAddFocusToken,
        preview: store.quickAddPreview
      ) { text, keep in
        await store.createInlineTask(text, destination: .today, keepOriginalTitle: keep)
      }
      .padding(.top, LorvexDesign.Spacing.m)
      if !content.doneListTasks.isEmpty {
        doneSection
          .padding(.top, LorvexDesign.Spacing.l)
      }
    }
    .frame(maxWidth: 720, alignment: .leading)
    .reduceMotionAnimation(.snappy(duration: 0.25), value: page)
    .sheet(isPresented: Binding(get: { planningDay != nil }, set: { if !$0 { planningDay = nil } })) {
      if let day = planningDay, let tomorrow = LorvexDateFormatters.ymdUTCAddingDays(day, days: 1),
        let load = page.overbooked {
        ReviewTomorrowPlanSheet(dayKey: tomorrow, tasks: load.planningRows,
          agenda: tomorrowAgenda?.key == tomorrow ? tomorrowAgenda : nil, loading: loadingAgenda,
          workday: store.workdayWindow, todayRemaining: load.freeMinutes - load.workMinutes, suggestedIDs: Set(load.candidates.map(\.id)),
          retry: { await loadOverflowAgenda() }) { chosen in
          planningDay = nil
          Task { await store.moveTodayOverflow(chosen, on: day, undoManager: undoManager) }
        }
        .task(id: store.dayReviewReadKey) { await loadOverflowAgenda() }
      }
    }
    .onChange(of: store.logicalTodayDateString) { planningDay = nil }
    .onChange(of: page.overbooked?.candidates.isEmpty != false) { _, unavailable in
      if unavailable { planningDay = nil }
    }
  }

  private func loadOverflowAgenda() async {
    loadingAgenda = true
    await store.loadWorkdayWindow()
    let day = await store.loadTomorrowAgenda()
    guard !Task.isCancelled else { return }
    tomorrowAgenda = day
    loadingAgenda = false
  }

  private func routine(_ catalog: HabitCatalogSnapshot) -> some View {
    TodayHabitRoutine(catalog: catalog, day: store.logicalTodayDateString, nowMinutes: nowMinutes,
      checkIn: { await store.checkInHabit($0, on: store.logicalTodayDateString) },
      undoOne: { await store.adjustHabitCompletion($0, delta: -1) },
      skip: { await store.toggleHabitSkip($0) }
    ) { period, routine in
      try await store.core.saveHabitRoutine(routine, for: period)
      store.habits = try await store.core.loadHabits(date: store.logicalTodayDateString)
      await store.republishSurfacesAfterLocalMutation()
    }
  }

  // MARK: Header

  private var header: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
      Text(TodayCalmCopy.dateLine(logicalDay: store.logicalTodayDateString))
        .font(LorvexDesign.Typography.pageTitle)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("today.date")
      LorvexFactsLine(TodayCalmCopy.facts(page.facts, workIsStated: page.overbooked != nil))
        .font(LorvexDesign.Typography.secondaryText)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("today.headline")
      if let briefing = LorvexCalmToday.briefing(from: store.today.briefing) {
        briefingView(briefing)
          .padding(.top, LorvexDesign.Spacing.s)
      }
    }
  }

  /// The assistant's briefing in the system face, marked by the sparkles
  /// glyph rather than italics. One that takes more than three lines at the
  /// column's width opens on three, with a toggle for the rest; a shorter one
  /// shows in full and has no toggle.
  private func briefingView(_ text: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.s) {
      Image(systemName: "sparkles")
        .foregroundStyle(LorvexDesign.Palette.accent)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
        Text(userContent: text)
          .font(LorvexDesign.Typography.briefing)
          .foregroundStyle(.primary)
          .lorvexLineClamp(3, isClamped: !showsFullBriefing, hidesText: $briefingHidesText)
          .textSelection(.enabled)
        if briefingHidesText {
          Button(showsFullBriefing ? TodayCalmCopy.briefingLess : TodayCalmCopy.briefingMore) {
            lorvexAnimated(.snappy(duration: 0.2)) { showsFullBriefing.toggle() }
          }
          .buttonStyle(.link)
          .font(LorvexDesign.Typography.secondaryText)
          .accessibilityIdentifier("today.briefing.toggle")
        }
      }
    }
    .padding(LorvexDesign.Spacing.m)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(LorvexDesign.Palette.insetFill, in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.m))
    .accessibilityElement(children: .contain)
    .accessibilityLabel(TodayCalmCopy.briefingLabel)
    .accessibilityIdentifier("today.briefing")
  }

  // MARK: The list

  /// The schedule stands when the day has anything on the clock (an event or
  /// a timed task) or suggested times are waiting for an answer.
  private var showsSchedule: Bool {
    store.proposedDayTimes != nil || content.schedule.contains { $0.kind != .now }
  }

  /// Today's tasks the schedule does not already show
  /// (``TodayColumnContent/untimedItems``).
  private var untimedItems: [LorvexCalmToday.Item] { content.untimedItems }

  /// The tasks without a time, started tasks first.
  private var taskList: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(untimedItems) { item in
        TodayTaskRow(
          task: item.task, store: store, isBlocked: store.isBlocked(item.task),
          chips: Self.chips(for: item))
      }
    }
    .accessibilityIdentifier("today.list")
  }

  /// The chips a Today row carries: "Pushed N times" once a task has been
  /// deferred often.
  static func chips(for item: LorvexCalmToday.Item) -> [LorvexTaskRowChip] {
    var chips: [LorvexTaskRowChip] = []
    if item.task.deferCount >= LorvexCalmToday.deferredOftenThreshold {
      chips.append(
        LorvexTaskRowChip(
          id: "pushed", title: TodayCalmCopy.pushedChip(item.task.deferCount),
          systemImage: "arrow.uturn.forward", tint: LorvexDesign.Palette.neutral))
    }
    return chips
  }

  // MARK: Overbooked

  /// Today holds more estimated work than free working time: one well says so
  /// and offers to move the named tasks to tomorrow. With nothing that can move
  /// on its own, it states the fact alone.
  @ViewBuilder
  private func overbookedWell(_ overbooked: LorvexCalmToday.Overbooked) -> some View {
    let title = TodayCalmCopy.overbookedTitle(overbooked)
    let message = TodayCalmCopy.overbookedMessage(overbooked)
    Group {
      if overbooked.candidates.isEmpty {
        LorvexDecisionWell(title: title, message: message)
      } else {
        LorvexDecisionWell(
          title: title, message: message, actionTitle: ReviewTomorrowPlanSheet.title + "…",
          actionIdentifier: "today.overbooked.action"
        ) {
          planningDay = store.logicalTodayDateString
        }
      }
    }
    .transition(.opacity)
    .accessibilityIdentifier("today.overbooked")
  }

  // MARK: Done

  /// What is already done today, newest first; the header folds it away and
  /// counts the rows only while they are folded, since open rows are their own
  /// count.
  private var doneSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button {
        lorvexAnimated(.snappy(duration: 0.2)) { store.isTodayDoneCollapsed.toggle() }
      } label: {
        // A record rather than work, so a quiet line, not a section title.
        HStack(spacing: LorvexDesign.Spacing.xs) {
          Text(TodayCalmCopy.doneTitle)
          if store.isTodayDoneCollapsed {
            Text("\(content.doneListTasks.count)")
              .monospacedDigit()
              .transition(.opacity)
          }
          LorvexDisclosureChevron(isExpanded: !store.isTodayDoneCollapsed)
            .imageScale(.small)
            .foregroundStyle(.tertiary)
          Spacer(minLength: 0)
        }
        .font(LorvexDesign.Typography.secondaryText)
        .foregroundStyle(.secondary)
        .padding(.horizontal, LorvexDesign.Spacing.s)
        .padding(.bottom, LorvexDesign.Spacing.xxs)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityAddTraits(.isHeader)
      .lorvexFoldState(isExpanded: !store.isTodayDoneCollapsed)
      .accessibilityIdentifier("today.done.toggle")
      if !store.isTodayDoneCollapsed {
        ForEach(content.doneListTasks) { task in
          TodayTaskRow(task: task, store: store)
        }
      }
    }
    .accessibilityIdentifier("today.done")
  }
}

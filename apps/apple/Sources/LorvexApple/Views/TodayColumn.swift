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
  let page: LorvexCalmToday
  let nowMinutes: Int?
  @State private var showsFullBriefing = false

  /// Briefings longer than this open on three lines with a "Show more" toggle.
  private static let briefingFoldLength = 150

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      if let overbooked = page.overbooked {
        overbookedWell(overbooked)
          .padding(.top, LorvexDesign.Spacing.l)
      }
      if showsSchedule {
        TodayScheduleSection(
          store: store, rows: store.todaySchedule, nowMinutes: nowMinutes,
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
      ) { text in
        await store.createInlineTask(text, destination: .today)
      }
      .padding(.top, LorvexDesign.Spacing.m)
      if !store.todayDoneListTasks.isEmpty {
        doneSection
          .padding(.top, LorvexDesign.Spacing.l)
      }
    }
    .frame(maxWidth: 720, alignment: .leading)
    .animation(.snappy(duration: 0.25), value: page)
  }

  // MARK: Header

  private var header: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
      Text(TodayCalmCopy.dateLine(logicalDay: store.logicalTodayDateString))
        .font(LorvexDesign.Typography.pageTitle)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("today.date")
      LorvexFactsLine(TodayCalmCopy.facts(page.facts))
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
  /// glyph rather than italics. A long one opens on three lines.
  private func briefingView(_ text: String) -> some View {
    let folds = text.count > Self.briefingFoldLength
    return HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.s) {
      Image(systemName: "sparkles")
        .foregroundStyle(LorvexDesign.Palette.accent)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
        Text(text)
          .font(LorvexDesign.Typography.briefing)
          .foregroundStyle(.primary)
          .lineLimit(folds && !showsFullBriefing ? 3 : nil)
          .fixedSize(horizontal: false, vertical: true)
          .textSelection(.enabled)
        if folds {
          Button(showsFullBriefing ? TodayCalmCopy.briefingLess : TodayCalmCopy.briefingMore) {
            withAnimation(.snappy(duration: 0.2)) { showsFullBriefing.toggle() }
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
    store.proposedDayTimes != nil || store.todaySchedule.contains { $0.kind != .now }
  }

  /// Today's tasks the schedule does not already show (``AppStore/todayUntimedItems``).
  private var untimedItems: [LorvexCalmToday.Item] { store.todayUntimedItems }

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
          title: title, message: message, actionTitle: TodayCalmCopy.overbookedAction,
          actionIdentifier: "today.overbooked.action"
        ) {
          let ids = overbooked.candidates.map(\.id)
          Task { await store.moveTodayTasksToTomorrow(ids) }
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
        withAnimation(.snappy(duration: 0.2)) { store.isTodayDoneCollapsed.toggle() }
      } label: {
        // A record rather than work, so a quiet line, not a section title.
        HStack(spacing: LorvexDesign.Spacing.xs) {
          Text(TodayCalmCopy.doneTitle)
          if store.isTodayDoneCollapsed {
            Text("\(store.todayDoneListTasks.count)")
              .monospacedDigit()
              .transition(.opacity)
          }
          Image(systemName: "chevron.right")
            .imageScale(.small)
            .rotationEffect(.degrees(store.isTodayDoneCollapsed ? 0 : 90))
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
      .accessibilityIdentifier("today.done.toggle")
      if !store.isTodayDoneCollapsed {
        ForEach(store.todayDoneListTasks) { task in
          TodayTaskRow(task: task, store: store)
        }
      }
    }
    .accessibilityIdentifier("today.done")
  }
}

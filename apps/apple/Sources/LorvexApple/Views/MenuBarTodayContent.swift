import LorvexCore
import SwiftUI

/// The menu bar panel's Today body (``MenuBarTodaySections``): the lead task
/// set larger, then the rest of the day on the clock (events and timed tasks
/// by start), the overdue tasks, the other tasks, the habits, and how much is
/// done. Section labels appear only when more than one section is listed, so
/// a plain day reads as one list. With nothing left on the day and no habit
/// it shows the sun arc for the hour.
struct MenuBarTodayContent: View {
  let page: LorvexCalmToday
  /// The events that occur today (``AppStore/todayScheduleEvents``).
  let events: [CalendarTimelineEvent]
  /// The product day as `yyyy-MM-dd`.
  let logicalDay: String
  let nowMinutes: Int?
  /// The habits still open on `logicalDay` (``LorvexHabit/isListed(on:)``) and
  /// not archived, in the catalog's order.
  let habits: [LorvexHabit]
  let isOverdue: (LorvexTask) -> Bool
  let complete: (LorvexTask) -> Void
  let open: (LorvexTask) -> Void
  let openEvent: (CalendarTimelineEvent) -> Void
  let checkIn: (LorvexHabit) -> Void

  var body: some View {
    let sections = MenuBarTodaySections(
      page: page, events: events, logicalDay: logicalDay, nowMinutes: nowMinutes, isOverdue: isOverdue)
    let sectionCount = [
      !sections.schedule.isEmpty, !sections.overdue.isEmpty, !sections.tasks.isEmpty, !habits.isEmpty,
    ].filter { $0 }.count
    let labelsSections = sectionCount > 1
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
      if let lead = sections.lead {
        leadBlock(lead)
      } else if sections.isEmpty, habits.isEmpty, let nowMinutes {
        LorvexSunArc(
          nowMinutes: nowMinutes, startLabel: TodayCalmCopy.sunStart, endLabel: TodayCalmCopy.sunEnd
        )
        .frame(height: 96)
        .padding(.horizontal, LorvexDesign.Spacing.l)
        .padding(.top, LorvexDesign.Spacing.xs)
        .accessibilityIdentifier("menubar.sun")
      }
      if !sections.schedule.isEmpty {
        section(labelsSections ? TodayCalmCopy.scheduleTitle : nil) {
          ForEach(sections.schedule) { scheduleRow($0) }
        }
        .accessibilityIdentifier("menubar.schedule")
      }
      if !sections.overdue.isEmpty {
        section(labelsSections ? MenuBarCopy.overdue : nil, isOverdue: true) {
          ForEach(sections.overdue) { taskRow($0) }
        }
        .accessibilityIdentifier("menubar.overdue")
      }
      if !sections.tasks.isEmpty {
        section(labelsSections ? TodayCalmCopy.tasksTitle : nil) {
          ForEach(sections.tasks) { taskRow($0) }
        }
      }
      if !habits.isEmpty {
        section(labelsSections || sections.lead != nil ? MenuBarCopy.habits : nil) {
          ForEach(habits) { habitRow($0) }
        }
        .accessibilityIdentifier("menubar.habits")
      }
      if page.doneToday > 0 {
        doneFoot(page.doneToday)
      }
    }
  }

  private func section(
    _ title: String?, isOverdue: Bool = false, @ViewBuilder rows: () -> some View
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      if let title {
        Text(title)
          .font(LorvexDesign.Typography.pageLabel)
          .foregroundStyle(isOverdue ? AnyShapeStyle(LorvexDesign.Palette.overdue) : AnyShapeStyle(.secondary))
          .padding(.bottom, LorvexDesign.Spacing.xxs)
          .accessibilityAddTraits(.isHeader)
      }
      rows()
    }
  }

  // MARK: - The lead

  /// The task the day leads with (``TodayLead``: a running time, a started
  /// task, or the next time today), one step larger than the rows under it:
  /// its circle, which completes it and fills as a running time passes, the
  /// title, which opens it in the main window, and one line of detail (the
  /// time, Started, or the estimate).
  private func leadBlock(_ item: LorvexCalmToday.Item) -> some View {
    let task = item.task
    return HStack(alignment: .top, spacing: LorvexDesign.Spacing.m) {
      leadCompleteButton(item)
        .accessibilityIdentifier("menubar.lead.complete")

      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
        Button {
          open(task)
        } label: {
          Text(userContent: task.title)
            .font(LorvexDesign.Typography.leadTitle)
            .foregroundStyle(.primary)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(TodayCalmCopy.openDetails)
        .accessibilityIdentifier("menubar.lead.open")
        if let detail = TodayCalmCopy.leadDetail(item) {
          Text(detail)
            .font(LorvexDesign.Typography.tertiaryText)
            .foregroundStyle(item.isRunning ? AnyShapeStyle(LorvexDesign.Palette.accent) : AnyShapeStyle(.secondary))
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    .padding(.top, LorvexDesign.Spacing.xs)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("menubar.lead")
  }

  // MARK: - Rows

  /// A task after the lead: its circle, which completes it, and its title,
  /// which opens it, with its time when it has one.
  private func taskRow(_ item: LorvexCalmToday.Item) -> some View {
    MenuBarTaskRow(
      task: item.task, time: item.time, identifier: "menubar.next",
      complete: { complete(item.task) }, open: { open(item.task) })
  }

  /// A row of the schedule: a timed task as every task row, or an event,
  /// which opens in the main window's Today.
  @ViewBuilder
  private func scheduleRow(_ entry: MenuBarTodaySections.Entry) -> some View {
    switch entry {
    case .task(let item):
      taskRow(item)
    case .event(let event):
      MenuBarEventRow(
        event: event, dayKey: logicalDay, identifier: "menubar.event", open: { openEvent(event) })
    }
  }

  /// The lead's circle, which completes its task: a ring that fills as a
  /// running time passes, with the faint check hint the widgets share.
  private func leadCompleteButton(_ item: LorvexCalmToday.Item) -> some View {
    Button {
      complete(item.task)
    } label: {
      LorvexTaskRing(progress: item.progress(nowMinutes: nowMinutes), isDone: false, diameter: 36)
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .help(TodayCalmCopy.complete)
    .accessibilityLabel(MenuBarCopy.complete(item.task.title))
  }

  /// A habit: its ring in the habit's color, which checks it in and fills
  /// with today's count, its name, and the count when the habit is counted
  /// more than once a day. A habit set aside for today draws its ring as
  /// skipped and quiets its name.
  private func habitRow(_ habit: LorvexHabit) -> some View {
    let target = max(habit.targetCount, 1)
    let isMet = habit.completionsToday >= target
    return HStack(spacing: LorvexDesign.Spacing.s) {
      Button {
        checkIn(habit)
      } label: {
        LorvexHabitCheckRing(
          fraction: min(Double(habit.completionsToday) / Double(target), 1),
          tint: isMet ? LorvexDesign.Palette.done : LorvexHabitPalette.baseColor(for: habit),
          isSkipped: habit.isSkipped)
      }
      .buttonStyle(.plain)
      .disabled(isMet && target > 1)
      .help(MenuBarCopy.checkIn)
      .accessibilityLabel(habit.name)
      .accessibilityValue(
        habit.isSkipped ? HabitSkipText.skippedToday : "\(habit.completionsToday)/\(target)")
      .accessibilityAddTraits(isMet ? .isSelected : [])
      Text(habit.name)
        .font(LorvexDesign.Typography.primaryText)
        .foregroundStyle(isMet || habit.isSkipped ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        .lineLimit(1)
      Spacer(minLength: 0)
      if target > 1 {
        Text("\(habit.completionsToday)/\(target)")
          .font(LorvexDesign.Typography.secondaryText)
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
    }
    .frame(minHeight: MenuBarTaskRow.minHeight)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("menubar.habit")
  }

  private func doneFoot(_ count: Int) -> some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(LorvexDesign.Palette.done)
      Text(TodayCalmCopy.doneToday(count))
        .foregroundStyle(.secondary)
    }
    .font(LorvexDesign.Typography.secondaryText)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("menubar.done")
  }
}

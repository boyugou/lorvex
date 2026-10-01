import LorvexCore
import SwiftUI

/// The menu bar panel's Today body: the lead task set larger, then the
/// overdue tasks, the rest of today's tasks, the habits, and how much is done.
/// Section labels appear only when more than one section is listed, so a
/// plain day reads as one list. With no task and no habit it shows the sun
/// arc for the hour.
struct MenuBarTodayContent: View {
  let page: LorvexCalmToday
  let nowMinutes: Int?
  /// The habits that are not archived, in the catalog's order.
  let habits: [LorvexHabit]
  let isOverdue: (LorvexTask) -> Bool
  let complete: (LorvexTask) -> Void
  let open: (LorvexTask) -> Void
  let checkIn: (LorvexHabit) -> Void

  var body: some View {
    let lead = page.lead
    let rest = page.leadFirst.dropFirst(lead == nil ? 0 : 1)
    let overdue = rest.filter { isOverdue($0.task) }
    let others = rest.filter { !isOverdue($0.task) }
    let sectionCount = [!overdue.isEmpty, !others.isEmpty, !habits.isEmpty].filter { $0 }.count
    let labelsSections = sectionCount > 1
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
      if let lead {
        leadBlock(lead)
      } else if page.items.isEmpty, habits.isEmpty, let nowMinutes {
        LorvexSunArc(
          nowMinutes: nowMinutes, startLabel: TodayCalmCopy.sunStart, endLabel: TodayCalmCopy.sunEnd
        )
        .frame(height: 96)
        .padding(.horizontal, LorvexDesign.Spacing.l)
        .padding(.top, LorvexDesign.Spacing.xs)
        .accessibilityIdentifier("menubar.sun")
      }
      if !overdue.isEmpty {
        section(labelsSections ? MenuBarCopy.overdue : nil, isOverdue: true) {
          ForEach(overdue) { taskRow($0) }
        }
        .accessibilityIdentifier("menubar.overdue")
      }
      if !others.isEmpty {
        section(labelsSections ? MenuBarCopy.today : nil) {
          ForEach(others) { taskRow($0) }
        }
      }
      if !habits.isEmpty {
        section(labelsSections || lead != nil ? MenuBarCopy.habits : nil) {
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
      completeButton(item, diameter: 36)
        .accessibilityIdentifier("menubar.lead.complete")

      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
        Button {
          open(task)
        } label: {
          Text(task.title)
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
    HStack(spacing: LorvexDesign.Spacing.s) {
      completeButton(item, diameter: 18)
        .accessibilityIdentifier("menubar.next.complete")
      Button {
        open(item.task)
      } label: {
        HStack(spacing: LorvexDesign.Spacing.s) {
          Text(item.task.title)
            .font(LorvexDesign.Typography.primaryText)
            .foregroundStyle(.primary)
            .lineLimit(1)
          Spacer(minLength: 0)
          if let time = item.time {
            Text(TodayCalmCopy.timeRange(start: time.lowerBound, end: time.upperBound))
              .font(LorvexDesign.Typography.secondaryText)
              .foregroundStyle(.secondary)
              .monospacedDigit()
              .lineLimit(1)
          }
        }
        .frame(minHeight: 30)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help(TodayCalmCopy.openDetails)
      .accessibilityIdentifier("menubar.next.task")
    }
  }

  /// The circle that completes `item`'s task. It fills as a running time
  /// passes. The lead's large ring carries the faint check hint the widgets
  /// share; a row's small circle stays plain, like every task row in the main
  /// window.
  private func completeButton(_ item: LorvexCalmToday.Item, diameter: CGFloat) -> some View {
    Button {
      complete(item.task)
    } label: {
      LorvexTaskRing(
        progress: item.progress(nowMinutes: nowMinutes), isDone: false, diameter: diameter,
        showsCheckHint: diameter >= 24)
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .help(TodayCalmCopy.complete)
    .accessibilityLabel(MenuBarCopy.complete(item.task.title))
  }

  /// A habit: its ring in the habit's color, which checks it in and fills
  /// with today's count, its name, and the count when the habit is counted
  /// more than once a day.
  private func habitRow(_ habit: LorvexHabit) -> some View {
    let target = max(habit.targetCount, 1)
    let isMet = habit.completionsToday >= target
    return HStack(spacing: LorvexDesign.Spacing.s) {
      Button {
        checkIn(habit)
      } label: {
        LorvexHabitCheckRing(
          fraction: min(Double(habit.completionsToday) / Double(target), 1),
          tint: isMet ? LorvexDesign.Palette.done : LorvexHabitPalette.baseColor(for: habit))
      }
      .buttonStyle(.plain)
      .disabled(isMet && target > 1)
      .help(MenuBarCopy.checkIn)
      .accessibilityLabel(habit.name)
      .accessibilityValue("\(habit.completionsToday)/\(target)")
      .accessibilityAddTraits(isMet ? .isSelected : [])
      Text(habit.name)
        .font(LorvexDesign.Typography.primaryText)
        .foregroundStyle(isMet ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        .lineLimit(1)
      Spacer(minLength: 0)
      if target > 1 {
        Text("\(habit.completionsToday)/\(target)")
          .font(LorvexDesign.Typography.secondaryText)
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
    }
    .frame(minHeight: 30)
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

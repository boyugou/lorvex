import LorvexCore
import SwiftUI

private enum CalendarMonthGridDayCellMetrics {
  static let cellPadding: CGFloat = 5
  static let dayNumberSize: CGFloat = 20
  /// A chip's height: one line of tertiary text plus its vertical padding.
  static let chipHeight: CGFloat = 16
  static let chipSpacing: CGFloat = LorvexDesign.Spacing.xxs
  static let chipCornerRadius: CGFloat = 4
  static let chipAccentRailWidth: CGFloat = 2
}

/// One month-grid day cell: the day number, a bounded stack of event and task
/// chips, and a "+N" overflow when the day has more items than
/// `maxVisibleChips`, which the grid sizes to the row (``chipsFitting(in:)``).
/// A chip names its title, then its time in the secondary color where the
/// width allows (``LorvexCalendarStripLabel``): an event's start on the day it
/// starts and "Until 6:00 AM" on a later day it ends, a timed task's start. A
/// task wears the calendar task surface rather than an event's fill and rail.
/// The "+N" chip opens a popover listing the whole day under its date.
///
/// Clicking anywhere in the cell background (including the day number) opens
/// that day (`onOpenDay`) — the whole cell is one Tab-focusable, Return/Space-
/// activatable region, matching the codebase's other "big region, not a
/// `Button`" affordances (`CalendarWeekGridEventBlock`). Each chip and the
/// overflow badge are real `Button`s layered on top, exactly the way
/// `LorvexTaskRow`'s completion circle nests inside its row's own tap
/// gesture: SwiftUI resolves a click to whichever region's own recognizer
/// contains the point, innermost first, so the cell-level "open day" gesture
/// and the chips' own taps never fight over the same click. `.contain`
/// grouping (rather than `.combine`) keeps every chip and the overflow badge
/// independently reachable to VoiceOver alongside the cell's own "open day"
/// action.
struct CalendarMonthGridDayCell: View {
  let day: CalendarMonthGridDay
  let isToday: Bool
  let maxVisibleChips: Int
  let eventColor: (CalendarTimelineEvent) -> Color
  let onSelectEvent: (CalendarTimelineEvent) -> Void
  let onOpenTask: (LorvexTask) -> Void
  @Environment(\.calendar) private var calendar
  let onOpenDay: () -> Void
  @Binding var isOverflowPresented: Bool
  let onShowOverflow: () -> Void

  private var chips: (visible: [CalendarMonthGridEntry], overflowCount: Int) {
    CalendarMonthGridModel.chips(for: day, maxVisible: maxVisibleChips)
  }

  /// How many chips (the "+N" chip included) a cell `rowHeight` tall can stack
  /// under its day number without running into the row below; at least one.
  static func chipsFitting(in rowHeight: CGFloat) -> Int {
    let metrics = CalendarMonthGridDayCellMetrics.self
    let stack = rowHeight - metrics.cellPadding * 2 - metrics.dayNumberSize - metrics.chipSpacing
    return max(1, Int(stack / (metrics.chipHeight + metrics.chipSpacing)))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: CalendarMonthGridDayCellMetrics.chipSpacing) {
      dayNumber
      ForEach(chips.visible) { entry in
        chipRow(entry)
      }
      if chips.overflowCount > 0 {
        overflowChip
      }
      Spacer(minLength: 0)
    }
    .padding(CalendarMonthGridDayCellMetrics.cellPadding)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    // Kept inside the cell: a background reaches into the safe area by default,
    // and the first column's tint would then show through the sidebar.
    .background(isToday ? Color.accentColor.opacity(0.07) : Color.clear, ignoresSafeAreaEdges: [])
    .contentShape(Rectangle())
    .onTapGesture(perform: onOpenDay)
    .calendarPointingHandCursor()
    .focusable(true)
    .onKeyPress(.return) {
      onOpenDay()
      return .handled
    }
    .onKeyPress(.space) {
      onOpenDay()
      return .handled
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(dayAccessibilityLabel)
    .accessibilityAddTraits(.isButton)
    .accessibilityAction(.default, onOpenDay)
    .accessibilityIdentifier("calendar.month.day.\(day.dayKey)")
    .popover(isPresented: $isOverflowPresented) {
      overflowPopover
    }
  }

  private var dayNumber: some View {
    Text(LorvexDateFormatters.dayNumber(day.date, timeZone: calendar.timeZone))
      .font(isToday ? LorvexDesign.Typography.primaryEmphasis : LorvexDesign.Typography.secondaryText)
      .foregroundStyle(dayNumberStyle)
      .frame(
        width: CalendarMonthGridDayCellMetrics.dayNumberSize,
        height: CalendarMonthGridDayCellMetrics.dayNumberSize
      )
      .background {
        if isToday {
          Circle().fill(.tint.opacity(0.18))
        }
      }
      .accessibilityHidden(true)
  }

  private var dayNumberStyle: AnyShapeStyle {
    if isToday { return AnyShapeStyle(.tint) }
    if !day.isCurrentMonth { return AnyShapeStyle(.tertiary) }
    return AnyShapeStyle(.primary)
  }

  @ViewBuilder
  private func chipRow(_ entry: CalendarMonthGridEntry) -> some View {
    switch entry {
    case .event(let event):
      Button {
        onSelectEvent(event)
      } label: {
        chip(title: event.title, time: event.pillTimeLabel(on: day.dayKey), color: eventColor(event))
      }
      .buttonStyle(.plain)
      .calendarPointingHandCursor()
      .opacity(day.isCurrentMonth ? 1 : 0.55)
      .accessibilityLabel(calendarPillAccessibilityLabel(event))
    case .task(let task):
      Button {
        onOpenTask(task)
      } label: {
        taskChip(
          title: task.title, time: nil, isDone: task.status == .completed,
          isOverdue: task.isOverdue(now: LorvexPreviewClock.now(in: calendar), timeZone: calendar.timeZone))
      }
      .buttonStyle(.plain)
      .calendarPointingHandCursor()
      .opacity(day.isCurrentMonth ? 1 : 0.55)
    case .timedTask(let task, let time):
      Button {
        onOpenTask(task)
      } label: {
        taskChip(
          title: task.title, time: lorvexClockTimeLabel(minutes: time.lowerBound),
          isDone: task.status == .completed, isOverdue: false)
      }
      .buttonStyle(.plain)
      .calendarPointingHandCursor()
      .opacity(day.isCurrentMonth ? 1 : 0.55)
      .accessibilityLabel(
        calendarTimedTaskAccessibilityLabel(
          title: task.title, startMinutes: time.lowerBound, endMinutes: time.upperBound))
    }
  }

  /// A task's chip, timed or not, wears the calendar task surface: a hollow
  /// dashed outline in the accent tint rather than an event's solid fill and
  /// rail, so time set aside for the user's own work never reads like a
  /// meeting. A finished task is struck through and faded. `time` follows the
  /// title where the width allows. `isOverdue` ends the chip with the overdue
  /// clock, as the week's all-day strip does for a task past its due day; a
  /// timed task's chip, like its week block, leaves it off.
  private func taskChip(title: String, time: String?, isDone: Bool, isOverdue: Bool) -> some View {
    HStack(spacing: 2) {
      LorvexCalendarStripLabel(title: title, time: time)
        .font(LorvexDesign.Typography.tertiaryText)
        .strikethrough(isDone)
        .foregroundStyle(isDone ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        .frame(maxWidth: .infinity, alignment: .leading)
      if isOverdue {
        Image(systemName: "clock.badge.exclamationmark")
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(LorvexDesign.Palette.overdue)
          .accessibilityLabel(
            String(localized: "task_detail.pill.overdue", defaultValue: "Overdue", table: "Localizable", bundle: LorvexL10n.bundle))
      }
    }
      .padding(.horizontal, 4)
      .padding(.vertical, 1)
      .frame(maxWidth: .infinity, alignment: .leading)
      .lorvexCalendarTaskSurface(
        isDone: isDone, cornerRadius: CalendarMonthGridDayCellMetrics.chipCornerRadius)
  }

  /// An event's chip: its title and `time` (``LorvexCalendarStripLabel``) on
  /// the event's color, with a rail at its leading edge.
  private func chip(title: String, time: String?, color: Color) -> some View {
    LorvexCalendarStripLabel(title: title, time: time)
      .font(LorvexDesign.Typography.tertiaryText)
      .padding(.horizontal, 4)
      .padding(.vertical, 1)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: CalendarMonthGridDayCellMetrics.chipCornerRadius))
      .overlay(alignment: .leading) {
        Rectangle()
          .fill(color)
          .frame(width: CalendarMonthGridDayCellMetrics.chipAccentRailWidth)
          .clipShape(RoundedRectangle(cornerRadius: CalendarMonthGridDayCellMetrics.chipAccentRailWidth / 2))
      }
  }

  private var overflowChip: some View {
    Button(action: onShowOverflow) {
      Text(verbatim: "+" + chips.overflowCount.formatted(.number.locale(LorvexClockFormat.displayLocale)))
        .font(LorvexDesign.Typography.tertiaryText.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .buttonStyle(.plain)
    .opacity(day.isCurrentMonth ? 1 : 0.55)
    .accessibilityLabel(
      String(
        localized: "calendar.overflow.more_events.a11y",
        defaultValue: "\(chips.overflowCount) more events",
        table: "Localizable", bundle: LorvexL10n.bundle))
    .accessibilityIdentifier("calendar.month.day.\(day.dayKey).overflow")
  }

  /// The whole day under its date, each entry with its time on the day's
  /// clock: an event's span ("9:30 – 10:00 AM"), its start or "Until 6:00 AM"
  /// on one day of an event that runs past midnight, or "All day"; a timed
  /// task's span. An untimed task has no time line.
  private var overflowPopover: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
      Text(
        LorvexDateFormatters.string(
          day.date, template: "EEEEMMMMd", timeZone: calendar.timeZone, position: .leading))
        .font(LorvexDesign.Typography.primaryEmphasis)
      ForEach(day.entries) { entry in
        switch entry {
        case .event(let event):
          overflowRow(
            title: event.title,
            time: event.listTimeLabel(on: day.dayKey, range: TodayCalmCopy.timeRange(start:end:))
              ?? TodayCalmCopy.allDay,
            color: eventColor(event)
          ) {
            isOverflowPresented = false
            onSelectEvent(event)
          }
        case .task(let task):
          overflowRow(title: task.title, time: nil, color: LorvexDesign.Palette.accent) {
            isOverflowPresented = false
            onOpenTask(task)
          }
        case .timedTask(let task, let time):
          overflowRow(
            title: task.title, time: TodayCalmCopy.timeRange(start: time.lowerBound, end: time.upperBound),
            color: LorvexDesign.Palette.accent
          ) {
            isOverflowPresented = false
            onOpenTask(task)
          }
        }
      }
    }
    .padding(LorvexDesign.Spacing.m)
    .frame(width: 260, alignment: .leading)
  }

  /// One popover row: a dot in the entry's color, its title, and `time` on a
  /// second line, as the week grid's hidden-items popover lays a row out.
  private func overflowRow(title: String, time: String?, color: Color, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: LorvexDesign.Spacing.s) {
        Circle().fill(color).frame(width: 8, height: 8)
        VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
          Text(userContent: title)
            .font(LorvexDesign.Typography.secondaryText)
            .lineLimit(1)
          if let time {
            Text(time)
              .font(LorvexDesign.Typography.tertiaryText)
              .foregroundStyle(.secondary)
          }
        }
        Spacer(minLength: 0)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private var dayAccessibilityLabel: String {
    let base = LorvexDateFormatters.string(day.date, dateStyle: .full, timeZone: calendar.timeZone)
    return isToday
      ? String(
        format: String(
          localized: "calendar.today_date.a11y", defaultValue: "Today, %@",
          table: "Localizable",
          bundle: LorvexL10n.bundle),
        base)
      : base
  }
}

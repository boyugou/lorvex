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
/// chips (a timed item leads with its start time; a task wears the calendar
/// task surface rather than an event's fill and rail), and a "+N" overflow
/// when the day has more items than `maxVisibleChips`, which the grid sizes to
/// the row (``chipsFitting(in:)``).
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
    .background(isToday ? Color.accentColor.opacity(0.07) : Color.clear)
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
        chip(title: chipTitle(for: event), color: eventColor(event))
      }
      .buttonStyle(.plain)
      .calendarPointingHandCursor()
      .opacity(day.isCurrentMonth ? 1 : 0.55)
    case .task(let task):
      Button {
        onOpenTask(task)
      } label: {
        taskChip(
          title: task.title, isDone: task.status == .completed,
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
          title: chipTitle(for: task, at: time), isDone: task.status == .completed, isOverdue: false)
      }
      .buttonStyle(.plain)
      .calendarPointingHandCursor()
      .opacity(day.isCurrentMonth ? 1 : 0.55)
    }
  }

  /// A task's chip, timed or not, wears the calendar task surface: a hollow
  /// dashed outline in the accent tint rather than an event's solid fill and
  /// rail, so time set aside for the user's own work never reads like a
  /// meeting. A finished task is struck through and faded.
  /// A task's chip. `isOverdue` ends it with the overdue clock, as the
  /// week's all-day strip does for a task past its due day; a timed task's
  /// chip, like its week block, leaves it off.
  private func taskChip(title: String, isDone: Bool, isOverdue: Bool) -> some View {
    HStack(spacing: 2) {
      Text(title)
        .font(LorvexDesign.Typography.tertiaryText)
        .strikethrough(isDone)
        .foregroundStyle(isDone ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        .lineLimit(1)
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

  /// A timed task's chip leads with its start time like a timed event's.
  private func chipTitle(for task: LorvexTask, at time: Range<Int>) -> String {
    "\(lorvexClockTimeLabel(minutes: time.lowerBound)) \(task.title)"
  }

  private func chip(title: String, color: Color) -> some View {
    Text(title)
      .font(LorvexDesign.Typography.tertiaryText)
      .lineLimit(1)
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

  /// A timed event's chip leads with its start time (matching Apple Calendar's
  /// month view); an all-day event just shows its title, matching the week
  /// grid's all-day pills.
  private func chipTitle(for event: CalendarTimelineEvent) -> String {
    guard !event.allDay, let start = event.startTime else { return event.title }
    return "\(lorvexClockTimeLabel(start)) \(event.title)"
  }

  private var overflowChip: some View {
    Button(action: onShowOverflow) {
      Text("+\(chips.overflowCount)")
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

  private var overflowPopover: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
      Text(LocalizedStringResource("calendar.overflow.title", defaultValue: "Hidden events", table: "Localizable", bundle: LorvexL10n.bundle))
        .font(LorvexDesign.Typography.primaryEmphasis)
      ForEach(day.entries) { entry in
        switch entry {
        case .event(let event):
          overflowRow(title: chipTitle(for: event), color: eventColor(event)) {
            isOverflowPresented = false
            onSelectEvent(event)
          }
        case .task(let task):
          overflowRow(title: task.title, color: LorvexDesign.Palette.accent) {
            isOverflowPresented = false
            onOpenTask(task)
          }
        case .timedTask(let task, let time):
          overflowRow(title: chipTitle(for: task, at: time), color: LorvexDesign.Palette.accent) {
            isOverflowPresented = false
            onOpenTask(task)
          }
        }
      }
    }
    .padding(LorvexDesign.Spacing.m)
    .frame(width: 260, alignment: .leading)
  }

  private func overflowRow(title: String, color: Color, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: LorvexDesign.Spacing.s) {
        Circle().fill(color).frame(width: 8, height: 8)
        Text(title)
          .font(LorvexDesign.Typography.secondaryText)
          .lineLimit(1)
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

import LorvexCore
import SwiftUI

private enum CalendarMonthGridDayCellMetrics {
  static let cellPadding: CGFloat = 5
  static let dayNumberSize: CGFloat = 20
  static let chipCornerRadius: CGFloat = 4
  static let chipAccentRailWidth: CGFloat = 2
}

/// One month-grid day cell: the day number, a bounded stack of event/task
/// chips, and a "+N" overflow when the day has more items than
/// ``CalendarMonthGridView/maxChipsPerDay``.
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
  let taskColor: (LorvexTask) -> Color
  let onSelectEvent: (CalendarTimelineEvent) -> Void
  let onOpenTask: (LorvexTask) -> Void
  let onOpenDay: () -> Void
  @Binding var isOverflowPresented: Bool
  let onShowOverflow: () -> Void

  private var chips: (visible: [CalendarMonthGridEntry], overflowCount: Int) {
    CalendarMonthGridModel.chips(for: day, maxVisible: maxVisibleChips)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
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
    Text(Self.dayNumberFormatter.string(from: day.date))
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
        chip(title: task.title, color: taskColor(task))
      }
      .buttonStyle(.plain)
      .calendarPointingHandCursor()
      .opacity(day.isCurrentMonth ? 1 : 0.55)
    }
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
        format: String(
          localized: "calendar.overflow.more_events.a11y", defaultValue: "%lld more events",
          table: "Localizable",
          bundle: LorvexL10n.bundle),
        chips.overflowCount))
    .accessibilityIdentifier("calendar.month.day.\(day.dayKey).overflow")
  }

  private var overflowPopover: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
      Text(LocalizedStringResource("calendar.overflow.title", defaultValue: "Hidden events", table: "Localizable", bundle: LorvexL10n.bundle))
        .font(LorvexDesign.Typography.primaryEmphasis)
      ForEach(day.events) { event in
        overflowRow(title: chipTitle(for: event), color: eventColor(event)) {
          isOverflowPresented = false
          onSelectEvent(event)
        }
      }
      ForEach(day.scheduledTasks) { task in
        overflowRow(title: task.title, color: taskColor(task)) {
          isOverflowPresented = false
          onOpenTask(task)
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
    let base = Self.fullDateFormatter.string(from: day.date)
    return isToday
      ? String(
        format: String(
          localized: "calendar.today_date.a11y", defaultValue: "Today, %@",
          table: "Localizable",
          bundle: LorvexL10n.bundle),
        base)
      : base
  }

  static let dayNumberFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "d"
    return formatter
  }()

  static let fullDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .full
    return formatter
  }()
}

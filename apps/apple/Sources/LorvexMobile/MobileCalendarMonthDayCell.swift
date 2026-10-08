import LorvexCore
import SwiftUI

/// One day of the month grid.
///
/// The day number sits at the top center: today's in the accent color, a day
/// of another month dimmed, and the chosen day's in a filled circle (the
/// accent on today, the primary color elsewhere), as Apple Calendar marks
/// them. Under it the day's entries follow in reading order
/// (``CalendarMonthGridDay/entries``). The `.marks` style draws up to three
/// marks: a dot in the event's color for an event, a ring in the accent for a
/// task, faded once the task is done. The `.titled` style draws chips that
/// name their entries and open them: an event's chip in its color with a
/// rail and its time where the width allows (its start, or "Until 6:00 AM"
/// on the day a longer event ends), a task's on the dashed task surface,
/// struck through once done, and "+N" for the entries that do not fit.
///
/// Tapping the cell chooses the day. Its context menu creates an event on
/// the day, and a task dropped on it is planned on it; a task chip drags to
/// another day. VoiceOver reads the cell as one button: the date, then how
/// many events and tasks the day has.
struct MobileCalendarMonthDayCell: View, Equatable {
  /// The vertical room a titled cell keeps around its stack: an inset at the
  /// top and a margin at the bottom.
  nonisolated static let titledInsets: CGFloat = 6
  /// The space between a titled cell's chips.
  nonisolated static let chipSpacing: CGFloat = 2
  private static let maxMarks = 3
  private static let markSize: CGFloat = 6

  let day: CalendarMonthGridDay
  let isToday: Bool
  let isSelected: Bool
  let style: MobileCalendarMonthCellStyle
  /// The side of the day number's circle.
  let dayNumberSize: CGFloat
  /// The height of a titled chip.
  let chipHeight: CGFloat
  let calendar: Calendar
  let choose: () -> Void
  let openEvent: (CalendarTimelineEvent) -> Void
  let openTask: (LorvexTask) -> Void
  let createEvent: () -> Void
  let dropTasks: ([LorvexTaskRef]) -> Void
  @State private var isDropTarget = false

  /// Two cells draw the same when they hold the same day in the same state at
  /// the same size. The closures they carry do the same thing for equal days,
  /// so they are not compared; this lets SwiftUI skip a cell whose page was
  /// evaluated again for another day's change.
  nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.day == rhs.day && lhs.isToday == rhs.isToday && lhs.isSelected == rhs.isSelected
      && lhs.style == rhs.style && lhs.dayNumberSize == rhs.dayNumberSize
      && lhs.chipHeight == rhs.chipHeight && lhs.calendar == rhs.calendar
  }

  var body: some View {
    content
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .background {
        if isDropTarget { LorvexDesign.Palette.accent.opacity(0.12) }
      }
      .contentShape(Rectangle())
      .onTapGesture(perform: choose)
      .dropDestination(for: LorvexTaskRef.self) { refs, _ in
        guard !refs.isEmpty else { return false }
        dropTasks(refs)
        return true
      } isTargeted: { isDropTarget = $0 }
      .contextMenu {
        Button(action: createEvent) {
          Label(Self.newEventTitle, systemImage: "calendar.badge.plus")
        }
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(accessibilityDate)
      .accessibilityValue(accessibilityCounts)
      .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
      .accessibilityAction(.default, choose)
      .accessibilityAction(named: Text(Self.newEventTitle), createEvent)
      .accessibilityIdentifier("mobileCalendar.month.day.\(day.dayKey)")
  }

  @ViewBuilder
  private var content: some View {
    switch style {
    case .marks:
      marksContent
    case .titled(let maxChips):
      titledContent(maxChips: maxChips)
    }
  }

  // MARK: Day number

  private var dayNumber: some View {
    Text(LorvexDateFormatters.dayNumber(day.date, timeZone: calendar.timeZone))
      .font(
        LorvexDesign.Typography.secondaryText
          .weight(isToday || isSelected ? .semibold : .regular).monospacedDigit()
      )
      .foregroundStyle(numberStyle)
      .lineLimit(1)
      .minimumScaleFactor(0.6)
      .frame(width: dayNumberSize, height: dayNumberSize)
      .background {
        if isSelected {
          Circle().fill(isToday ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
        }
      }
      .reduceMotionAnimation(.snappy(duration: 0.2), value: isSelected)
  }

  private var numberStyle: AnyShapeStyle {
    if isSelected { return isToday ? AnyShapeStyle(.white) : AnyShapeStyle(.background) }
    if isToday { return AnyShapeStyle(.tint) }
    return day.isCurrentMonth ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary)
  }

  // MARK: Marks

  private var marksContent: some View {
    VStack(spacing: 3) {
      dayNumber
      HStack(spacing: 3) {
        ForEach(day.entries.prefix(Self.maxMarks)) { entry in
          mark(for: entry)
        }
      }
      .frame(height: Self.markSize)
      .opacity(day.isCurrentMonth ? 1 : 0.5)
    }
    .padding(.top, 3)
  }

  @ViewBuilder
  private func mark(for entry: CalendarMonthGridEntry) -> some View {
    switch entry {
    case .event(let event):
      Circle()
        .fill(eventColor(event))
        .frame(width: Self.markSize, height: Self.markSize)
    case .task(let task), .timedTask(let task, _):
      Circle()
        .strokeBorder(
          LorvexDesign.Palette.accent.opacity(task.status == .completed ? 0.4 : 0.85),
          lineWidth: 1.25
        )
        .frame(width: Self.markSize, height: Self.markSize)
    }
  }

  // MARK: Chips

  private func titledContent(maxChips: Int) -> some View {
    let chips = CalendarMonthGridModel.chips(for: day, maxVisible: maxChips)
    return VStack(spacing: Self.chipSpacing) {
      dayNumber
      Group {
        ForEach(chips.visible) { entry in
          chip(for: entry)
        }
        if chips.overflowCount > 0 {
          Text(
            verbatim: "+"
              + chips.overflowCount.formatted(.number.locale(LorvexClockFormat.displayLocale))
          )
          .font(LorvexDesign.CalendarMetrics.compactBlockText.weight(.semibold))
          .foregroundStyle(.secondary)
          .padding(.horizontal, 4)
          .frame(maxWidth: .infinity, alignment: .leading)
          .frame(height: chipHeight)
        }
      }
      .opacity(day.isCurrentMonth ? 1 : 0.55)
    }
    .padding(.horizontal, 3)
    .padding(.top, Self.titledInsets / 2)
  }

  @ViewBuilder
  private func chip(for entry: CalendarMonthGridEntry) -> some View {
    switch entry {
    case .event(let event):
      // An event the user cannot edit opens nothing, so its chip is no
      // button and a tap on it chooses the day like the rest of the cell.
      if event.editable {
        Button { openEvent(event) } label: { eventChip(event) }
          .buttonStyle(.plain)
      } else {
        eventChip(event)
      }
    case .task(let task):
      taskChip(task, time: nil)
    case .timedTask(let task, let time):
      taskChip(task, time: lorvexClockTimeLabel(minutes: time.lowerBound))
    }
  }

  private func eventChip(_ event: CalendarTimelineEvent) -> some View {
    let color = eventColor(event)
    return LorvexCalendarStripLabel(title: event.title, time: event.pillTimeLabel(on: day.dayKey))
      .font(LorvexDesign.CalendarMetrics.compactBlockText)
      .padding(.leading, 5)
      .padding(.trailing, 3)
      .frame(maxWidth: .infinity, alignment: .leading)
      .frame(height: chipHeight)
      .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.s))
      .overlay(alignment: .leading) {
        Rectangle().fill(color).frame(width: 2)
          .clipShape(RoundedRectangle(cornerRadius: LorvexDesign.Radius.s))
      }
  }

  private func taskChip(_ task: LorvexTask, time: String?) -> some View {
    let isDone = task.status == .completed
    return Button {
      openTask(task)
    } label: {
      LorvexCalendarStripLabel(title: task.title, time: time)
        .font(LorvexDesign.CalendarMetrics.compactBlockText)
        .strikethrough(isDone)
        .foregroundStyle(isDone ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: chipHeight)
        .lorvexCalendarTaskSurface(isDone: isDone, cornerRadius: LorvexDesign.Radius.s)
    }
    .buttonStyle(.plain)
    .draggable(LorvexTaskRef(id: task.id, title: task.title))
  }

  private func eventColor(_ event: CalendarTimelineEvent) -> Color {
    Color(lorvexHex: event.color) ?? LorvexDesign.Palette.accent
  }

  // MARK: Accessibility

  private static var newEventTitle: String {
    String(
      localized: "calendar.new_event", defaultValue: "New Event", table: "Localizable",
      bundle: MobileL10n.bundle)
  }

  /// The full date, after "Today," on today.
  private var accessibilityDate: String {
    let date = LorvexDateFormatters.string(day.date, dateStyle: .full, timeZone: calendar.timeZone)
    guard isToday else { return date }
    return String(
      format: String(
        localized: "calendar.week.today_prefix", defaultValue: "Today, %@", table: "Localizable",
        bundle: MobileL10n.bundle), date)
  }

  /// How many events and tasks the day has ("2 events and 1 task"), leaving
  /// out a count of none; empty for a free day.
  private var accessibilityCounts: String {
    let eventCount = day.events.count
    let taskCount = day.scheduledTasks.count + day.timedTasks.count
    var counts: [String] = []
    if eventCount > 0 {
      counts.append(
        String(
          localized: "calendar.month.events.a11y", defaultValue: "\(eventCount) events",
          table: "Localizable", bundle: MobileL10n.bundle))
    }
    if taskCount > 0 {
      counts.append(
        String(
          localized: "calendar.month.tasks.a11y", defaultValue: "\(taskCount) tasks",
          table: "Localizable", bundle: MobileL10n.bundle))
    }
    return counts.formatted(.list(type: .and).locale(LorvexClockFormat.displayLocale))
  }
}

import LorvexCore
import SwiftUI

@MainActor
/// The weekday and date over each column of a multi-day grid. Today's
/// weekday and date are accent-colored, and with `circlesToday` its date sits
/// in a filled accent circle. A grid under the week strip turns the circle
/// off: the strip already circles the chosen day, and a second circle right
/// below it reads as the same date drawn twice. With `onOpenDay`, each header
/// is a button that opens its day.
struct MobileCalendarColumnHeaders: View {
  let columns: [CalendarGridDay]
  let calendar: Calendar
  let gutterWidth: CGFloat
  var circlesToday = true
  var onOpenDay: ((Date) -> Void)? = nil

  var body: some View {
    HStack(spacing: 0) {
      // Gutter spacer to align day columns with the time axis. `Color.clear` is
      // greedy in any unconstrained axis, so pin a height — otherwise it stretches
      // the header to fill and centers the labels in a tall floating band.
      Color.clear.frame(width: gutterWidth, height: 1)
      ForEach(columns) { day in
        if let onOpenDay {
          Button { onOpenDay(day.date) } label: { label(for: day) }
            .buttonStyle(.plain)
            .accessibilityLabel(day.date.formatted(date: .complete, time: .omitted))
            .accessibilityAddTraits(isToday(day.date) ? [.isButton, .isSelected] : .isButton)
        } else {
          label(for: day)
        }
      }
    }
    .padding(.vertical, 4)
    .fixedSize(horizontal: false, vertical: true)
  }

  private func label(for day: CalendarGridDay) -> some View {
    let isToday = isToday(day.date)
    return VStack(spacing: 2) {
      Text(
        MobileDateFormatting.weekdayAbbrev.string(from: day.date)
          .uppercased(with: MobileL10n.locale)
      )
      .font(LorvexDesign.Typography.tertiaryText)
      .foregroundStyle(isToday ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
      Text(MobileDateFormatting.dayOfMonth.string(from: day.date))
        .font(LorvexDesign.Typography.secondaryText.weight(.semibold).monospacedDigit())
        .foregroundStyle(
          isToday ? (circlesToday ? AnyShapeStyle(.white) : AnyShapeStyle(.tint)) : AnyShapeStyle(.primary)
        )
        .frame(width: 28, height: 28)
        .background { if isToday && circlesToday { Circle().fill(.tint) } }
    }
    .frame(maxWidth: .infinity)
    .contentShape(Rectangle())
  }

  private func isToday(_ date: Date) -> Bool { calendar.isDateInToday(date) }
}

@MainActor
struct MobileCalendarAllDayStrip: View {
  let columns: [CalendarGridDay]
  let gutterWidth: CGFloat
  /// Narrow columns: pills carry their title alone, in the compact block face.
  var isCompact = false
  let eventColor: (CalendarTimelineEvent) -> Color
  let onTapEvent: (CalendarTimelineEvent) -> Void
  let onDeleteEvent: (CalendarTimelineEvent) async -> Bool
  let onTapTask: (LorvexTask) -> Void
  let onToggleTask: (LorvexTask) -> Void
  let onDropTask: (LorvexTaskRef, Date) -> Void
  @Environment(\.calendar) private var calendar

  var body: some View {
    let hasContent = columns.contains {
      !$0.allDayEvents.isEmpty || !$0.scheduledTasks.isEmpty
    }
    HStack(alignment: .top, spacing: 0) {
      Text(
        String(
          localized: "calendar.all_day_strip", defaultValue: "all-day", table: "Localizable",
          bundle: MobileL10n.bundle)
      )
      .font(LorvexDesign.Typography.tertiaryText).foregroundStyle(.secondary)
      .frame(width: gutterWidth, alignment: .trailing)
      .padding(.trailing, 6)
      ForEach(columns) { day in
        VStack(spacing: 3) {
          ForEach(day.allDayEvents) { event in
            allDayPill(title: event.title, color: eventColor(event))
              .onTapGesture { if event.editable { onTapEvent(event) } }
              .contextMenu {
                if event.editable {
                  Button {
                    onTapEvent(event)
                  } label: {
                    Label(
                      String(
                        localized: "common.edit", defaultValue: "Edit", table: "Localizable",
                        bundle: MobileL10n.bundle), systemImage: "pencil")
                  }

                  Button(role: .destructive) {
                    Task { _ = await onDeleteEvent(event) }
                  } label: {
                    Label(
                      String(
                        localized: "common.delete", defaultValue: "Delete", table: "Localizable",
                        bundle: MobileL10n.bundle), systemImage: "trash")
                  }
                }
              }
              .accessibilityAddTraits(.isButton)
              .accessibilityLabel(
                String(
                  format: String(
                    localized: "calendar.all_day_event.a11y", defaultValue: "All day event %@",
                    table: "Localizable", bundle: MobileL10n.bundle),
                  event.title))
          }
          ForEach(day.scheduledTasks) { task in
            allDayTaskPill(task)
          }
        }
        .dropDestination(for: LorvexTaskRef.self) { refs, _ in
          guard !refs.isEmpty else { return false }
          for ref in refs {
            onDropTask(ref, day.date)
          }
          return true
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 3)
      }
    }
    .padding(.vertical, hasContent ? 5 : 2)
    .frame(minHeight: 24)
  }

  /// A task in the all-day strip speaks the timed blocks' task vocabulary,
  /// never an event pill's fill and rail: a leading ring that completes it,
  /// on the calendar task surface. A finished task stays, struck through and
  /// faded, as the day's record. A task past its due day ends with the
  /// overdue clock Today's rows use, since the ring's tint already speaks for
  /// priority. The pill opens the task. A compact pill (`isCompact`) keeps
  /// only its title, in the overdue color when the task is overdue; its
  /// context menu still completes it.
  private func allDayTaskPill(_ task: LorvexTask) -> some View {
    let isDone = task.status == .completed
    let isOverdue = task.isOverdue(now: LorvexPreviewClock.now(in: calendar), calendar: calendar)
    let toggleLabel = MobileTaskActionCopy.completionToggle(isDone: isDone)
    return HStack(spacing: 2) {
      if !isCompact {
        MobileCalendarTaskRing(isDone: isDone, font: LorvexDesign.Typography.tertiaryText, width: 18) {
          onToggleTask(task)
        }
      }
      Text(task.title)
        .font(isCompact ? LorvexDesign.CalendarMetrics.compactBlockText : LorvexDesign.Typography.tertiaryText)
        .lineLimit(1)
        .strikethrough(isDone)
        .foregroundStyle(
          isOverdue && isCompact
            ? AnyShapeStyle(LorvexDesign.Palette.overdue)
            : isDone ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
      if isOverdue, !isCompact {
        Image(systemName: "clock.badge.exclamationmark")
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(LorvexDesign.Palette.overdue)
      }
    }
    .padding(.leading, isCompact ? 4 : 2).padding(.trailing, isCompact ? 2 : 6).padding(.vertical, 2)
    .frame(maxWidth: .infinity, alignment: .leading)
    .lorvexCalendarTaskSurface(isDone: isDone, cornerRadius: LorvexDesign.Radius.s)
    .contentShape(Rectangle())
    .onTapGesture { onTapTask(task) }
    .contextMenu {
      Button {
        onTapTask(task)
      } label: {
        Label(MobileCalendarTaskCopy.open, systemImage: "arrow.up.forward.square")
      }
      Button {
        onToggleTask(task)
      } label: {
        Label(toggleLabel, systemImage: MobileCalendarTaskCopy.toggleSystemImage(isDone: isDone))
      }
    }
    // One VoiceOver element per pill, as on a timed block: the default action
    // opens the task and the ring's completion is a named action.
    .accessibilityElement(children: .ignore)
    .accessibilityAddTraits(.isButton)
    .accessibilityLabel(
      String(
        format: String(
          localized: "calendar.scheduled_task.a11y", defaultValue: "Scheduled task %@",
          table: "Localizable", bundle: MobileL10n.bundle),
        task.title))
    .accessibilityValue(
      isOverdue
        ? String(localized: "calendar.task.overdue", defaultValue: "Overdue", table: "Localizable", bundle: MobileL10n.bundle)
        : "")
    .accessibilityAction { onTapTask(task) }
    .accessibilityAction(named: Text(toggleLabel)) { onToggleTask(task) }
    .accessibilityIdentifier("mobileCalendar.allDayTask")
  }

  private func allDayPill(title: String, color: Color) -> some View {
    Text(title)
      .font(isCompact ? LorvexDesign.CalendarMetrics.compactBlockText : LorvexDesign.Typography.tertiaryText)
      .lineLimit(1)
      .padding(.horizontal, isCompact ? 4 : 6).padding(.vertical, 2)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.s))
      .overlay(alignment: .leading) {
        Rectangle().fill(color).frame(width: 2).clipShape(
          RoundedRectangle(cornerRadius: LorvexDesign.Radius.s))
      }
  }
}

@MainActor
struct MobileCalendarHourGutter: View {
  let calendar: Calendar
  let gutterWidth: CGFloat
  let hourHeight: CGFloat
  let anchorHour: Int

  var body: some View {
    VStack(spacing: 0) {
      ForEach(0..<24, id: \.self) { hour in
        Text(hourLabel(hour))
          .font(LorvexDesign.Typography.tertiaryText).foregroundStyle(.secondary)
          .frame(width: gutterWidth - 6, height: hourHeight, alignment: .topTrailing)
          .modifier(MobileDayAnchorModifier(hour: hour, anchorHour: anchorHour))
      }
    }
    .frame(width: gutterWidth)
  }

  private func hourLabel(_ hour: Int) -> String {
    var components = DateComponents(calendar: calendar)
    components.year = 2001
    components.month = 1
    components.day = 1
    components.hour = hour
    guard let date = calendar.date(from: components) else {
      return "\(hour)"
    }
    return LorvexDateFormatters.hourLabel(
      date, timeZone: calendar.timeZone,
      locale: LorvexClockFormat.current.applied(to: MobileL10n.locale))
  }

}

enum MobileDayScrollAnchor: Hashable { case hour(Int) }

/// Tags the chosen gutter row as the scroll anchor.
struct MobileDayAnchorModifier: ViewModifier {
  let hour: Int
  let anchorHour: Int
  func body(content: Content) -> some View {
    if hour == anchorHour { content.id(MobileDayScrollAnchor.hour(anchorHour)) } else { content }
  }
}

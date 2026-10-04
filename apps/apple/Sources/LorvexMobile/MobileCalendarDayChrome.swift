import LorvexCore
import SwiftUI
#if os(iOS)
  import UIKit
#endif

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
            .accessibilityLabel(
              LorvexDateFormatters.string(day.date, dateStyle: .full, timeZone: calendar.timeZone))
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
      Text(LorvexDateFormatters.string(day.date, template: "EEE", timeZone: calendar.timeZone))
      .font(LorvexDesign.Typography.tertiaryText)
      .foregroundStyle(isToday ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
      Text(LorvexDateFormatters.dayNumber(day.date, timeZone: calendar.timeZone))
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
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  /// ``LorvexDesign/CalendarMetrics/allDayStripMaxHeight``, scaled with the
  /// pills' text.
  @ScaledMetric(relativeTo: .caption) private var baseMaxHeight: CGFloat =
    LorvexDesign.CalendarMetrics.allDayStripMaxHeight
  /// Whether the strip, once it scrolls, has rows below the visible ones. It
  /// starts true: a strip scrolls only when its rows overflow, from the top.
  @State private var hasRowsBelow = true

  /// Whether any of `columns` has an all-day event or a task without a time.
  static func hasContent(_ columns: [CalendarGridDay]) -> Bool {
    columns.contains { !$0.allDayEvents.isEmpty || !$0.scheduledTasks.isEmpty }
  }

  /// The strip takes the height its rows need up to a limit, then scrolls
  /// within it, so the hours below keep their room however many tasks the day
  /// has. While rows lie below the visible ones, the last rows fade, so a cut
  /// row reads as "more below" rather than as the end.
  var body: some View {
    let hasContent = Self.hasContent(columns)
    ViewThatFits(in: .vertical) {
      rows(hasContent: hasContent)
      ScrollView(.vertical) { rows(hasContent: hasContent) }
        .onScrollGeometryChange(for: Bool.self) { scroll in
          scroll.contentOffset.y + scroll.containerSize.height < scroll.contentSize.height - 1
        } action: { _, hasMore in
          hasRowsBelow = hasMore
        }
        .mask {
          VStack(spacing: 0) {
            Color.black
            LinearGradient(
              colors: [.black, hasRowsBelow ? .clear : .black], startPoint: .top, endPoint: .bottom
            )
            .frame(height: 16)
          }
        }
    }
    .frame(maxHeight: baseMaxHeight * (horizontalSizeClass == .regular ? 2 : 1))
  }

  private func rows(hasContent: Bool) -> some View {
    HStack(alignment: .top, spacing: 0) {
      Text(
        String(
          localized: "calendar.all_day_strip", defaultValue: "all-day", table: "Localizable",
          bundle: MobileL10n.bundle)
      )
      .font(LorvexDesign.Typography.tertiaryText).foregroundStyle(.secondary)
      // A label that wraps in the narrow gutter ("весь / день") keeps each
      // line against the hour labels' trailing edge.
      .multilineTextAlignment(.trailing)
      .frame(width: gutterWidth, alignment: .trailing)
      .padding(.trailing, 6)
      ForEach(columns) { day in
        VStack(spacing: 3) {
          ForEach(day.allDayEvents) { event in
            allDayPill(
              title: event.title, time: isCompact ? nil : event.pillTimeLabel(on: day.dayKey),
              color: eventColor(event))
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
              .accessibilityLabel(allDayEventAccessibilityLabel(event))
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
    let isOverdue = task.isOverdue(now: LorvexPreviewClock.now(in: calendar), timeZone: calendar.timeZone)
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

  /// An event's pill in the all-day strip: the title, followed by `time`
  /// where the width allows (``LorvexCalendarStripLabel``).
  private func allDayPill(title: String, time: String?, color: Color) -> some View {
    LorvexCalendarStripLabel(title: title, time: time)
      .font(isCompact ? LorvexDesign.CalendarMetrics.compactBlockText : LorvexDesign.Typography.tertiaryText)
      .padding(.horizontal, isCompact ? 4 : 6).padding(.vertical, 2)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.s))
      .overlay(alignment: .leading) {
        Rectangle().fill(color).frame(width: 2).clipShape(
          RoundedRectangle(cornerRadius: LorvexDesign.Radius.s))
      }
  }

  /// An all-day event reads as one ("All day event Offsite"); a timed event of
  /// a day or more, which the strip also holds, reads with its span.
  private func allDayEventAccessibilityLabel(_ event: CalendarTimelineEvent) -> String {
    guard event.allDay else { return calendarEventAccessibilityLabel(event) }
    return String(
      format: String(
        localized: "calendar.all_day_event.a11y", defaultValue: "All day event %@",
        table: "Localizable", bundle: MobileL10n.bundle),
      event.title)
  }
}

@MainActor
struct MobileCalendarHourGutter: View {
  /// The space between an hour label and the first day column.
  static let labelInset: CGFloat = 6

  /// The gutter's width at the default text size: the widest of `calendar`'s
  /// hour labels on one line in the footnote font, plus the inset, and never
  /// narrower than 52pt, which fits English labels ("11 PM"). The 12-hour
  /// labels of Chinese and Korean ("上午10時", "오전 10시") need more. Callers
  /// scale it with the footnote style, as the labels scale.
  static func baseWidth(calendar: Calendar) -> CGFloat {
    #if os(iOS)
      let labels = (0..<24).map { hourLabel($0, calendar: calendar) }
      let key = labels.joined(separator: "\u{1F}")
      if let cached = baseWidths[key] { return cached }
      let font = UIFont.preferredFont(
        forTextStyle: .footnote, compatibleWith: UITraitCollection(preferredContentSizeCategory: .large))
      let widest = labels.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
      let width = max(52, (widest + labelInset + 2).rounded(.up))
      baseWidths[key] = width
      return width
    #else
      return 52
    #endif
  }

  private static var baseWidths: [String: CGFloat] = [:]

  let calendar: Calendar
  let gutterWidth: CGFloat
  let hourHeight: CGFloat
  let anchorHour: Int

  var body: some View {
    VStack(spacing: 0) {
      ForEach(0..<24, id: \.self) { hour in
        Text(Self.hourLabel(hour, calendar: calendar))
          .font(LorvexDesign.Typography.tertiaryText).foregroundStyle(.secondary)
          .frame(width: gutterWidth - Self.labelInset, height: hourHeight, alignment: .topTrailing)
          .modifier(MobileDayAnchorModifier(hour: hour, anchorHour: anchorHour))
      }
    }
    .frame(width: gutterWidth)
  }

  static func hourLabel(_ hour: Int, calendar: Calendar) -> String {
    var components = DateComponents(calendar: calendar)
    components.year = 2001
    components.month = 1
    components.day = 1
    components.hour = hour
    guard let date = calendar.date(from: components) else {
      return "\(hour)"
    }
    return LorvexDateFormatters.hourLabel(date, timeZone: calendar.timeZone)
  }

}

enum MobileDayScrollAnchor: Hashable {
  case hour(Int)

  /// The margin above the hours' scroll content, so the hour scrolled to the
  /// top keeps its label and the blocks that start on it clear of the divider
  /// over the grid.
  static let topClearance: CGFloat = 10
}

/// Tags the chosen gutter row as the scroll anchor.
struct MobileDayAnchorModifier: ViewModifier {
  let hour: Int
  let anchorHour: Int
  func body(content: Content) -> some View {
    if hour == anchorHour { content.id(MobileDayScrollAnchor.hour(anchorHour)) } else { content }
  }
}

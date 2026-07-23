import LorvexCore
import SwiftUI

@MainActor
struct MobileCalendarColumnHeaders: View {
  let columns: [CalendarGridDay]
  let calendar: Calendar
  let gutterWidth: CGFloat

  var body: some View {
    HStack(spacing: 0) {
      // Gutter spacer to align day columns with the time axis. `Color.clear` is
      // greedy in any unconstrained axis, so pin a height — otherwise it stretches
      // the header to fill and centers the labels in a tall floating band.
      Color.clear.frame(width: gutterWidth, height: 1)
      ForEach(columns) { day in
        VStack(spacing: 1) {
          Text(
            MobileDateFormatting.weekdayAbbrev.string(from: day.date)
              .uppercased(with: MobileL10n.locale)
          )
          .font(LorvexDesign.Typography.tertiaryText).foregroundStyle(.secondary)
          Text(MobileDateFormatting.dayOfMonth.string(from: day.date))
            .font(LorvexDesign.Typography.secondaryText.weight(.semibold))
            .foregroundStyle(isToday(day.date) ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
        }
        .frame(maxWidth: .infinity)
      }
    }
    .padding(.vertical, 4)
    .fixedSize(horizontal: false, vertical: true)
  }

  private func isToday(_ date: Date) -> Bool { calendar.isDateInToday(date) }
}

@MainActor
struct MobileCalendarAllDayStrip: View {
  let columns: [CalendarGridDay]
  let gutterWidth: CGFloat
  let eventColor: (CalendarTimelineEvent) -> Color
  let onTapEvent: (CalendarTimelineEvent) -> Void
  let onDeleteEvent: (CalendarTimelineEvent) async -> Bool
  let onTapTask: (LorvexTask) -> Void
  let onDropTask: (LorvexTaskRef, Date) -> Void

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
            allDayPill(title: task.title, color: .secondary)
              .onTapGesture { onTapTask(task) }
              .accessibilityAddTraits(.isButton)
              .accessibilityLabel(
                String(
                  format: String(
                    localized: "calendar.scheduled_task.a11y", defaultValue: "Scheduled task %@",
                    table: "Localizable", bundle: MobileL10n.bundle),
                  task.title))
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

  private func allDayPill(title: String, color: Color) -> some View {
    Text(title)
      .font(LorvexDesign.Typography.tertiaryText).lineLimit(1)
      .padding(.horizontal, 6).padding(.vertical, 2)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
      .overlay(alignment: .leading) {
        Rectangle().fill(color).frame(width: 2).clipShape(RoundedRectangle(cornerRadius: 1))
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
    return Self.hourFormatter.string(from: date)
  }

  private static let hourFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = MobileL10n.locale
    f.setLocalizedDateFormatFromTemplate("j")
    return f
  }()
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

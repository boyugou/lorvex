import LorvexCore
import SwiftUI

/// Picks from the displayed agenda, whose clock marker already accounts for
/// projected instants in a repeated hour and for overnight occurrences.
struct MobileTodayAppointment: Equatable {
  enum Phase { case now, next, allDay }

  let event: CalendarTimelineEvent
  let phase: Phase

  static func firstGlance(in rows: [LorvexTodayTimelineItem]) -> Self? {
    var current: Self?
    var daylong: Self?
    var reachedClock = false
    for row in rows {
      if case .now = row.kind {
        if let current { return current }
        reachedClock = true
        continue
      }
      guard case .event(let event) = row.kind, event.occurrenceState != .cancelled, !row.isPast else { continue }
      if row.startMinutes != nil {
        if reachedClock { return Self(event: event, phase: .next) }
        // With overlapping meetings the most recently started one leads.
        current = Self(event: event, phase: .now)
      } else if daylong == nil {
        if event.allDay { daylong = Self(event: event, phase: .allDay) }
        else if row.eventPart == .middleDay { daylong = Self(event: event, phase: .now) }
      }
    }
    return daylong
  }

  var label: String {
    switch phase {
    case .now:
      String(localized: "today.schedule.row_now.a11y", defaultValue: "Now",
        table: "Localizable", bundle: MobileL10n.bundle)
    case .next:
      String(localized: "today.appointment.up_next", defaultValue: "Up next",
        table: "Localizable", bundle: MobileL10n.bundle)
    case .allDay:
      String(localized: "calendar.all_day_short", defaultValue: "All day",
        table: "Localizable", bundle: MobileL10n.bundle)
    }
  }
}

struct MobileTodayAppointmentRow: View {
  let appointment: MobileTodayAppointment
  let day: String
  let open: (CalendarTimelineEvent) -> Void

  var body: some View {
    Button { open(appointment.event) } label: {
      HStack(spacing: LorvexDesign.Spacing.m) {
        Capsule()
          .fill(LorvexDesign.Palette.eventTint(appointment.event.color))
          .frame(width: 3)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
          Text(verbatim: appointment.label)
            .font(LorvexDesign.Typography.pageLabel).foregroundStyle(.secondary)
          Text(verbatim: appointment.event.title)
            .font(.headline)
          if let time = appointment.event.listTimeLabel(on: day, range: MobileTodayCalmCopy.timeRange)
            ?? appointment.event.timedSpanLabel {
            Text(verbatim: time)
              .font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
          }
        }
        Spacer(minLength: 0)
        Image(systemName: "chevron.forward")
          .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
          .accessibilityHidden(true)
      }
      .fixedSize(horizontal: false, vertical: true)
      .padding(LorvexDesign.Spacing.m)
      .background(LorvexDesign.Palette.insetFill, in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.m))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("today.appointment")
  }
}

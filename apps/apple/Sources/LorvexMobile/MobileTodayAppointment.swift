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

  /// The time until an event starts, in hours and minutes: "In 45 min", "In 2
  /// hr 40 min". `style` `.spoken` spells the units out for VoiceOver.
  static func countdown(
    minutesAway: Int, style: LorvexDurationFormat.Style = .compact,
    locale: Locale = LorvexClockFormat.displayLocale
  ) -> String {
    let duration = LorvexDurationFormat.hoursAndMinutes(minutesAway, style: style, locale: locale)
    return String(
      localized: "today.appointment.in_duration", defaultValue: "In \(duration)",
      table: "Localizable", bundle: MobileL10n.bundle)
  }
}

struct MobileTodayAppointmentRow: View {
  let appointment: MobileTodayAppointment
  let day: String
  var minutesAway: Int?
  let open: (CalendarTimelineEvent) -> Void

  private var timingLabel: String {
    guard let minutesAway else { return appointment.label }
    return MobileTodayAppointment.countdown(minutesAway: minutesAway)
  }

  var body: some View {
    Button { open(appointment.event) } label: {
      HStack(spacing: LorvexDesign.Spacing.m) {
        Capsule()
          .fill(LorvexDesign.Palette.eventTint(appointment.event.color))
          .frame(width: 3)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
          Text(verbatim: timingLabel)
            .font(LorvexDesign.Typography.pageLabel).foregroundStyle(.secondary)
            .accessibilityLabel(
              minutesAway.map { MobileTodayAppointment.countdown(minutesAway: $0, style: .spoken) }
                ?? timingLabel)
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
      .padding(minutesAway == nil ? LorvexDesign.Spacing.m : 0)
      .background(minutesAway == nil ? LorvexDesign.Palette.insetFill : Color.clear, in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.m))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("today.appointment")
  }
}

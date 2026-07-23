import LorvexCore
import SwiftUI

struct MobileCalendarAgendaRow: View {
  let event: CalendarTimelineEvent

  var body: some View {
    HStack(alignment: .top, spacing: LorvexDesign.Spacing.m) {
      Image(systemName: event.allDay ? "sun.max" : "calendar")
        .font(LorvexDesign.Typography.secondaryText)
        .foregroundStyle(.secondary)
        .frame(width: 22)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
        Text(event.title)
          .font(LorvexDesign.Typography.primaryEmphasis)
          .lineLimit(2)
        Text(subtitle)
          .font(LorvexDesign.Typography.secondaryText)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }

      Spacer(minLength: LorvexDesign.Spacing.s)

      if event.isRecurring || event.supportsScopedMutation {
        Image(systemName: "repeat")
          .font(LorvexDesign.Typography.secondaryText)
          .foregroundStyle(.secondary)
          .accessibilityLabel(
            String(
              localized: "calendar.repeating_event.a11y", defaultValue: "Repeating event",
              table: "Localizable", bundle: MobileL10n.bundle))
      }
    }
    .padding(.vertical, LorvexDesign.Spacing.s)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("mobileCalendar.agendaRow.\(event.id)")
  }

  private var subtitle: String {
    let time =
      event.allDay
      ? String(
        localized: "calendar.all_day", defaultValue: "all day", table: "Localizable",
        bundle: MobileL10n.bundle)
      : event.startTime
        ?? String(
          localized: "calendar.time_unset", defaultValue: "time unset", table: "Localizable",
          bundle: MobileL10n.bundle)
    if let location = event.location, !location.isEmpty {
      return "\(time) - \(location)"
    }
    return time
  }
}

struct MobileCalendarAgendaTaskRow: View {
  let task: LorvexTask

  var body: some View {
    HStack(alignment: .top, spacing: LorvexDesign.Spacing.m) {
      Image(systemName: "checklist")
        .font(LorvexDesign.Typography.secondaryText)
        .foregroundStyle(.secondary)
        .frame(width: 22)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
        Text(task.title)
          .font(LorvexDesign.Typography.primaryEmphasis)
          .lineLimit(2)
        Text(subtitle)
          .font(LorvexDesign.Typography.secondaryText)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }

      Spacer(minLength: LorvexDesign.Spacing.s)
    }
    .padding(.vertical, LorvexDesign.Spacing.s)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("mobileCalendar.agendaTaskRow.\(task.id)")
  }

  private var subtitle: String {
    [
      MobileTaskDisplayText.priority(task.priority),
      MobileTaskDisplayText.status(task.status),
      task.estimatedMinutes.map { MobileTaskDisplayText.compactEstimateMinutes($0) },
    ]
    .compactMap { $0 }
    .joined(separator: " - ")
  }
}

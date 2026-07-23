import LorvexCore
import SwiftUI

/// Today's calendar agenda — the day's fixed commitments (Lorvex events plus
/// the mirrored EventKit external calendar), shown at the top of Today as the
/// frame the rest of the day fills in around.
///
/// This is the "no focus plan yet" state. Once a focus schedule is proposed or
/// saved, these same events are woven into ``FocusScheduleSection`` as `event`
/// blocks, so Today shows this standalone agenda only while no focus timeline is
/// present — never both, so an event is never listed twice.
struct TodayScheduleSection: View {
  /// Today's events, already filtered to the day and agenda-ordered by
  /// ``CalendarTimelineSnapshot/events(on:)``.
  let events: [CalendarTimelineEvent]

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      WorkspaceTaskSectionHeader(
        title: String(
          localized: "today.section.schedule", defaultValue: "Schedule", table: "Localizable",
          bundle: LorvexL10n.bundle),
        count: events.count,
        systemImage: "calendar.day.timeline.left",
        tint: .secondary,
        topSpacing: LorvexDesign.Spacing.s
      )
      .padding(.horizontal, LorvexDesign.Spacing.l)

      VStack(spacing: 0) {
        ForEach(events) { event in
          TodayScheduleEventRow(event: event)
        }
      }
      .padding(.horizontal, LorvexDesign.Spacing.m)
      .padding(.vertical, LorvexDesign.Spacing.s)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        .quaternary.opacity(0.08), in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.s)
      )
      .overlay {
        RoundedRectangle(cornerRadius: LorvexDesign.Radius.s)
          .stroke(.separator.opacity(0.18), lineWidth: 0.5)
      }
      .padding(.horizontal, LorvexDesign.Spacing.m)
      .accessibilityIdentifier("today.schedule.panel")
    }
  }
}

private struct TodayScheduleEventRow: View {
  let event: CalendarTimelineEvent

  var body: some View {
    HStack(spacing: 12) {
      Text(timeLabel)
        .font(LorvexDesign.Typography.tertiaryText.monospacedDigit().weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary, in: Capsule())
        .frame(minWidth: 52)
        .accessibilityLabel(timeAccessibilityLabel)

      Image(systemName: event.allDay ? "sun.max" : "calendar")
        .foregroundStyle(.secondary)
        .frame(width: 18)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 2) {
        Text(event.title)
          .lineLimit(1)
        if let subtitle {
          Text(subtitle)
            .font(LorvexDesign.Typography.tertiaryText)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
      Spacer(minLength: 0)

      if event.isRecurring || event.supportsScopedMutation {
        Image(systemName: "repeat")
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.tertiary)
          .accessibilityLabel(
            String(
              localized: "calendar.repeating_event.a11y", defaultValue: "Repeating event",
              table: "Localizable",
              bundle: LorvexL10n.bundle))
      }
    }
    .padding(.vertical, 3)
    .accessibilityElement(children: .combine)
  }

  /// The leading time capsule: "All day" for all-day events, otherwise the
  /// start time (the end time rides in the subtitle to keep the capsule narrow).
  private var timeLabel: String {
    if event.allDay {
      return String(
        localized: "calendar.all_day_short", defaultValue: "All day", table: "Localizable",
        bundle: LorvexL10n.bundle)
    }
    return event.startTime.map(lorvexClockTimeLabel)
      ?? String(
        localized: "calendar.time_unset_short", defaultValue: "—",
        table: "Localizable",
        bundle: LorvexL10n.bundle)
  }

  /// The end time and location, joined — the calm detail under the title. Nil
  /// for an all-day event with no location, so the row stays a clean title.
  private var subtitle: String? {
    var parts: [String] = []
    if !event.allDay, let end = event.endTime {
      parts.append(
        String(
          format: String(
            localized: "today.schedule.until", defaultValue: "until %@", table: "Localizable",
            bundle: LorvexL10n.bundle),
          lorvexClockTimeLabel(end)))
    }
    if let location = event.location, !location.isEmpty { parts.append(location) }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }

  private var timeAccessibilityLabel: String {
    if event.allDay {
      return String(
        localized: "calendar.all_day", defaultValue: "all day", table: "Localizable",
        bundle: LorvexL10n.bundle)
    }
    if let start = event.startTime, let end = event.endTime {
      return String(
        format: String(
          localized: "focus.schedule.block.time_accessibility", defaultValue: "%@ to %@",
          table: "Localizable",
          bundle: LorvexL10n.bundle),
        lorvexClockTimeLabel(start), lorvexClockTimeLabel(end))
    }
    return event.startTime.map(lorvexClockTimeLabel) ?? ""
  }
}

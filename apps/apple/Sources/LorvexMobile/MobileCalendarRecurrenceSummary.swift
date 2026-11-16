import LorvexCore
import SwiftUI

/// The stored repeat rule and, when different from the displayed times, the
/// clock it follows. Shared by the event editor and read-only event detail.
struct MobileCalendarRecurrenceSummary: View {
  let event: CalendarTimelineEvent

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
      Text(userContent: event.recurrenceDescription(generic: MobileCalendarEventCopy.repeatingEvent))
        .font(LorvexDesign.Typography.primaryText)
        .textSelection(.enabled)
      if let zoneNote = event.recurrenceTimeZoneNote {
        Text(zoneNote)
          .font(LorvexDesign.Typography.secondaryText)
          .foregroundStyle(.secondary)
      }
    }
    .fixedSize(horizontal: false, vertical: true)
    .accessibilityElement(children: .combine)
  }
}

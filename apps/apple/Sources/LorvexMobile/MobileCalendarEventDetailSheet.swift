import LorvexCore
import SwiftUI

/// The detail of a calendar event that Lorvex only shows: one mirrored from
/// the device's calendars, which Lorvex cannot change. It reads what the
/// event holds, in the order the Mac inspector lists it (when, where, how it
/// repeats, who is invited, the link, the notes, and the calendar it lives
/// in), and offers the text for sharing or copying. An event Lorvex owns opens
/// its editor instead (``MobileStoreCalendarEventSheet``).
struct MobileCalendarEventDetailSheet: View {
  let event: CalendarTimelineEvent
  @Binding var isPresented: Bool

  var body: some View {
    NavigationStack {
      ScrollView {
        MobileCalendarEventDetailContent(event: event)
          .padding(.horizontal, LorvexDesign.Spacing.l)
          .padding(.vertical, LorvexDesign.Spacing.m)
      }
      .background(LorvexDesign.Palette.groupedBackground)
      .mobileSheetTitle(
        String(
          localized: "calendar.section.event", defaultValue: "Event", table: "Localizable",
          bundle: MobileL10n.bundle)
      )
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          ShareLink(item: MobileShareText.event(event)) {
            Label(
              String(
                localized: "common.share", defaultValue: "Share", table: "Localizable",
                bundle: MobileL10n.bundle),
              systemImage: "square.and.arrow.up")
          }
          .labelStyle(.iconOnly)
          .accessibilityIdentifier("mobileCalendarEventDetail.share")
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(
            String(
              localized: "common.done", defaultValue: "Done", table: "Localizable",
              bundle: MobileL10n.bundle)
          ) {
            isPresented = false
          }
          .accessibilityIdentifier("mobileCalendarEventDetail.done")
        }
      }
    }
    .mobileCompactEditorSheetPresentation()
  }
}

/// The rows of an event's detail: its title with the event's color, then one
/// row per field the event has. A row names its field above its value, so a
/// long place, a long note, or a text size at the top of the scale wraps
/// inside the row instead of squeezing a label beside it.
struct MobileCalendarEventDetailContent: View {
  let event: CalendarTimelineEvent

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.l) {
      header
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
        whenRow
        if let location = nonBlank(event.location) {
          row(icon: "mappin.and.ellipse", label: MobileCalendarEventCopy.location) {
            valueText(location)
          }
        }
        if event.hasRecurrenceRow {
          row(icon: "repeat", label: MobileCalendarEventCopy.repeats) {
            valueText(event.recurrenceDescription(generic: MobileCalendarEventCopy.repeatingEvent))
          }
        }
        if let attendees = attendeeNames, !attendees.isEmpty {
          row(icon: "person.2", label: MobileCalendarEventCopy.attendees) {
            VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
              ForEach(attendees, id: \.self) { valueText($0) }
            }
          }
        }
        if let urlString = nonBlank(event.url), let url = URL(string: urlString) {
          row(icon: "link", label: MobileCalendarEventCopy.url) {
            Link(urlString, destination: url)
              .font(LorvexDesign.Typography.primaryText)
              .multilineTextAlignment(.leading)
          }
        }
        if let notes = nonBlank(event.notes) {
          row(icon: "note.text", label: MobileCalendarEventCopy.notes) { valueText(notes) }
        }
        row(icon: "lock", label: MobileCalendarEventCopy.calendar) {
          valueText(MobileCalendarEventCopy.systemCalendar)
        }
      }
      .lorvexCard()
    }
    .accessibilityIdentifier("mobileCalendarEventDetail.content")
  }

  private var header: some View {
    HStack(alignment: .top, spacing: LorvexDesign.Spacing.s) {
      Capsule()
        .fill(LorvexDesign.Palette.eventTint(event.color))
        .frame(width: 4)
        .accessibilityHidden(true)
      Text(userContent: event.title)
        .font(LorvexDesign.Typography.detailTitle)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("mobileCalendarEventDetail.title")
    }
    .fixedSize(horizontal: false, vertical: true)
  }

  private var whenRow: some View {
    let when = event.whenLines(allDay: MobileCalendarEventCopy.allDay)
    return row(icon: "calendar", label: MobileCalendarEventCopy.when) {
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
        valueText(when.first)
        if let second = when.second {
          Text(verbatim: second)
            .font(LorvexDesign.Typography.secondaryText)
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  private var attendeeNames: [String]? {
    event.attendees?.compactMap { nonBlank($0.name) ?? nonBlank($0.email) }
  }

  private func row<Content: View>(
    icon: String, label: String, @ViewBuilder content: () -> Content
  ) -> some View {
    HStack(alignment: .top, spacing: LorvexDesign.Spacing.s) {
      Image(systemName: icon)
        .font(LorvexDesign.Typography.secondaryText)
        .foregroundStyle(.secondary)
        .frame(width: 22)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
        Text(verbatim: label)
          .font(LorvexDesign.Typography.tertiaryText.weight(.semibold))
          .foregroundStyle(.secondary)
        content()
      }
      Spacer(minLength: 0)
    }
    .accessibilityElement(children: .combine)
  }

  private func valueText(_ value: String) -> some View {
    Text(userContent: value)
      .font(LorvexDesign.Typography.primaryText)
      .textSelection(.enabled)
      .fixedSize(horizontal: false, vertical: true)
  }

  private func nonBlank(_ text: String?) -> String? {
    guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return text
  }
}

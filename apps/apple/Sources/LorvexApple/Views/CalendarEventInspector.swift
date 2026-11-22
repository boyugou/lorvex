import LorvexCore
import SwiftUI

/// An event's detail panel: the Calendar workspace's third pane, which opens
/// when an event is clicked, the main window's inspector for an event opened
/// from Today's schedule, and the popover an event row opens in Daily Review.
/// Imported (non-`editable`) events render read-only with a "managed by
/// source" note. Resolving the event by id (via the caller) keeps it live
/// across timeline refreshes.
struct CalendarEventInspector: View {
  /// What the panel offers below the event's facts.
  enum Actions {
    /// Edit and Delete for a Lorvex-owned event, and the link to Apple
    /// Calendar for an imported one. The panel fills the height it is given.
    case manage(edit: () -> Void, requestDelete: () -> Void)
    /// One button that hands the displayed copy to the caller, which shows it
    /// in the Calendar workspace. The panel is as tall as its facts, up to a
    /// cap past which they scroll, so it suits a popover.
    case preview(openCalendar: (CalendarTimelineEvent) -> Void)
  }

  let event: CalendarTimelineEvent
  let actions: Actions
  let close: () -> Void
  /// Live origin fallback for a legacy observation without cached provenance.
  /// Defaults to no-op for previews/tests.
  var resolveSource: (CalendarTimelineEvent) async -> EventKitEventSource? = { _ in nil }
  /// The panel's width beside the Calendar grid. Nil fills the width it is
  /// given, as in the main window's resizable inspector column.
  var fixedWidth: CGFloat? = 320
  var selectCopy: (CalendarTimelineEvent) -> Void = { _ in }

  @State private var selectedCopyID = ""
  private var copies: [CalendarTimelineEvent] { event.displayCopies }
  private var displayedEvent: CalendarTimelineEvent {
    copies.first { $0.id == selectedCopyID } ?? event.displayCopies[0]
  }

  @State private var previewFactsHeight: CGFloat = 340
  @State private var resolvedSource: EventKitEventSource?

  private var tint: Color { LorvexDesign.Palette.eventTint(displayedEvent.color) }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
      switch actions {
      case .manage(let edit, let requestDelete):
        ScrollView { facts }
        if displayedEvent.editable {
          Divider()
          actionBar(edit: edit, requestDelete: requestDelete)
        }
      case .preview(let openCalendar):
        ScrollView {
          facts.onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
            previewFactsHeight = height
          }
        }
        .frame(height: min(340, previewFactsHeight))
        .scrollBounceBehavior(.basedOnSize)
        Divider()
        Button {
          openCalendar(displayedEvent)
        } label: {
          Label(String(localized: "review.event.show_in_calendar", defaultValue: "Show in Lorvex Calendar",
            table: "Localizable", bundle: LorvexL10n.bundle), systemImage: "calendar")
        }
        .accessibilityIdentifier("reviews.daily.event.openCalendar")
        .padding(LorvexDesign.Spacing.m)
      }
    }
    .frame(width: fixedWidth)
    .frame(maxWidth: fixedWidth == nil ? .infinity : nil)
    .background(.background)
    .accessibilityIdentifier("calendar.event.inspector")
    .onChange(of: event.id) { _, id in selectedCopyID = id }
    .task(id: displayedEvent.id) {
      resolvedSource = nil
      guard displayedEvent.origin == nil else { return }
      let source = await resolveSource(displayedEvent)
      guard !Task.isCancelled else { return }
      resolvedSource = source
    }
  }

  private var facts: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.l) {
      if copies.count > 1 {
        CalendarEventCopyPicker(copies: copies, selectedID: Binding(
          get: { displayedEvent.id }, set: { id in
            selectedCopyID = id
            if let copy = copies.first(where: { $0.id == id }) { selectCopy(copy) }
          }))
      }
      scheduleRow
      if let location = displayedEvent.location, !location.isEmpty {
        detailRow(icon: "mappin.and.ellipse", title: locationTitle) { plainText(location) }
      }
      if displayedEvent.hasRecurrenceRow {
        detailRow(icon: "repeat", title: recurrenceTitle) {
          VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
            plainText(Self.recurrenceLabel(for: displayedEvent))
            if let zoneNote = displayedEvent.recurrenceTimeZoneNote {
              Text(zoneNote)
                .font(LorvexDesign.Typography.secondaryText)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
        }
      }
      if let notes = displayedEvent.notes, !notes.isEmpty {
        detailRow(icon: "note.text", title: notesTitle) { plainText(notes) }
      }
      if let attendees = displayedEvent.attendees, !attendees.isEmpty {
        detailRow(icon: "person.2", title: attendeesTitle) {
          VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
            ForEach(attendees, id: \.email) { attendee in
              plainText(attendee.name ?? attendee.email)
            }
          }
        }
      }
      if let url = displayedEvent.openableURL, let urlString = displayedEvent.url {
        detailRow(icon: "link", title: urlTitle) {
          Link(urlString, destination: url).font(LorvexDesign.Typography.primaryText)
        }
      }
      sourceRow
      if case .manage = actions, !displayedEvent.editable, let calendarURL = displayedEvent.appleCalendarURL {
        Link(destination: calendarURL) {
          Label(openInCalendarTitle, systemImage: "arrow.up.forward.app")
        }
        .font(LorvexDesign.Typography.secondaryText)
        .accessibilityIdentifier("calendar.event.inspector.openInCalendar")
      }
    }
    .padding(LorvexDesign.Spacing.l)
  }

  private var header: some View {
    HStack(alignment: .top, spacing: LorvexDesign.Spacing.s) {
      RoundedRectangle(cornerRadius: LorvexDesign.Radius.s, style: .continuous)
        .fill(tint)
        .frame(width: 4, height: 28)
      Text(userContent: displayedEvent.title)
        .font(LorvexDesign.Typography.sectionHeader)
        .foregroundStyle(.primary)
        .lineLimit(3)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: LorvexDesign.Spacing.s)
      LorvexIconMenu(
        systemImage: "ellipsis",
        label: String(
          localized: "common.more", defaultValue: "More", table: "Localizable",
          bundle: LorvexL10n.bundle),
        accessibilityIdentifier: "calendar.event.inspector.more"
      ) {
        CalendarEventShareMenuItems(event: displayedEvent)
      }
      InspectorCloseButton(accessibilityIdentifier: "calendar.event.inspector.close", action: close)
    }
    .padding(LorvexDesign.Spacing.m)
  }

  private var scheduleRow: some View {
    let when = displayedEvent.whenLines(
      allDay: String(
        localized: "calendar.event.all_day", defaultValue: "All day", table: "Localizable",
        bundle: LorvexL10n.bundle))
    return detailRow(icon: "calendar", title: whenTitle) {
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
        plainText(when.first)
        if let second = when.second {
          Text(verbatim: second)
            .font(LorvexDesign.Typography.secondaryText)
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  @ViewBuilder
  private var sourceRow: some View {
    if let display = displaySource {
      detailRow(icon: displayedEvent.editable ? "calendar.badge.checkmark" : "lock", title: calendarTitle) {
        VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
          plainText(display.title)
          if let account = display.account, !account.isEmpty, account != display.title {
            Text(account)
              .font(LorvexDesign.Typography.secondaryText)
              .foregroundStyle(.secondary)
          }
        }
      }
    }
  }

  /// The calendar identity to show: the live EventKit calendar (title + account)
  /// when resolved; otherwise a meaningful label rather than the cache's opaque
  /// `provider` / `canonical` source sentinels — "Lorvex" for owned events, a
  /// generic system-calendar label for an unresolved provider event.
  private var displaySource: (title: String, account: String?)? {
    if let origin = displayedEvent.origin {
      return (origin.calendarTitle, origin.accountTitle)
    }
    if let resolvedSource {
      return (resolvedSource.calendarTitle, resolvedSource.accountTitle)
    }
    if displayedEvent.editable {
      return (
        String(
          localized: "calendar.event.source.lorvex", defaultValue: "Lorvex",
          table: "Localizable",
          bundle: LorvexL10n.bundle), nil
      )
    }
    guard !displayedEvent.source.isEmpty else { return nil }
    return (
      String(
        localized: "calendar.event.source.system", defaultValue: "System Calendar",
        table: "Localizable",
        bundle: LorvexL10n.bundle), nil
    )
  }

  private func actionBar(edit: @escaping () -> Void, requestDelete: @escaping () -> Void) -> some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      Button(action: edit) {
        Label(
          String(
            localized: "common.edit", defaultValue: "Edit", table: "Localizable",
            bundle: LorvexL10n.bundle), systemImage: "pencil")
      }
      .buttonStyle(.borderedProminent)
      .accessibilityIdentifier("calendar.event.inspector.edit")

      Button(role: .destructive, action: requestDelete) {
        Label(
          String(
            localized: "common.delete", defaultValue: "Delete", table: "Localizable",
            bundle: LorvexL10n.bundle), systemImage: "trash")
      }
      .buttonStyle(.bordered)
      .accessibilityIdentifier("calendar.event.inspector.delete")

      Spacer(minLength: 0)
    }
    .controlSize(.small)
    .padding(LorvexDesign.Spacing.m)
  }

  private func detailRow<Content: View>(
    icon: String, title: String, @ViewBuilder content: () -> Content
  ) -> some View {
    HStack(alignment: .top, spacing: LorvexDesign.Spacing.s) {
      Image(systemName: icon)
        .font(LorvexDesign.Typography.secondaryText)
        .foregroundStyle(.secondary)
        .frame(width: 18)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
        Text(title)
          .font(LorvexDesign.Typography.tertiaryText.weight(.semibold))
          .foregroundStyle(.secondary)
        content()
      }
      Spacer(minLength: 0)
    }
  }

  private func plainText(_ value: String) -> some View {
    Text(userContent: value)
      .font(LorvexDesign.Typography.primaryText)
      .foregroundStyle(.primary)
      .textSelection(.enabled)
      .fixedSize(horizontal: false, vertical: true)
  }

  /// How the event repeats, in the words the repeat editor uses ("Every 2
  /// weeks · Mon, Wed · 10 times"): the source's own summary for a mirrored
  /// event, else the stored rule's. A one-off change to a series occurrence
  /// carries no rule of its own and reads as a generic repeating event.
  static func recurrenceLabel(for event: CalendarTimelineEvent) -> String {
    event.recurrenceDescription(
      generic: String(
        localized: "calendar.event.repeats_generic", defaultValue: "Repeating event",
        table: "Localizable", bundle: LorvexL10n.bundle))
  }

  private var openInCalendarTitle: String {
    String(
      localized: "calendar.event.open_in_calendar", defaultValue: "Open in Calendar",
      table: "Localizable", bundle: LorvexL10n.bundle)
  }
  private var whenTitle: String {
    String(
      localized: "calendar.event.field.when", defaultValue: "When", table: "Localizable",
      bundle: LorvexL10n.bundle)
  }
  private var locationTitle: String {
    String(
      localized: "calendar.section.location", defaultValue: "Location", table: "Localizable",
      bundle: LorvexL10n.bundle)
  }
  private var recurrenceTitle: String {
    String(
      localized: "calendar.event.field.repeats", defaultValue: "Repeats", table: "Localizable",
      bundle: LorvexL10n.bundle)
  }
  private var notesTitle: String {
    String(
      localized: "calendar.section.notes", defaultValue: "Notes", table: "Localizable",
      bundle: LorvexL10n.bundle)
  }
  private var attendeesTitle: String {
    String(
      localized: "calendar.event.field.attendees", defaultValue: "Attendees", table: "Localizable",
      bundle: LorvexL10n.bundle)
  }
  private var urlTitle: String {
    String(
      localized: "calendar.event.field.url", defaultValue: "URL", table: "Localizable",
      bundle: LorvexL10n.bundle)
  }
  private var calendarTitle: String {
    String(
      localized: "calendar.event.field.calendar", defaultValue: "Calendar", table: "Localizable",
      bundle: LorvexL10n.bundle)
  }
}

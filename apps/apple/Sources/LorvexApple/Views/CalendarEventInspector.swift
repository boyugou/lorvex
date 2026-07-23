import LorvexCore
import SwiftUI

/// The calendar workspace's trailing detail panel — the third pane that opens
/// when an event is clicked. Imported (non-`editable`) events render read-only
/// with a "managed by source" note; Lorvex-owned events also offer Edit and
/// Delete. Resolving the event by id (via the caller) keeps it live across
/// timeline refreshes.
struct CalendarEventInspector: View {
  let event: CalendarTimelineEvent
  let edit: () -> Void
  let requestDelete: () -> Void
  let close: () -> Void
  /// Resolves the fine-grained origin calendar (title + account) live from
  /// EventKit, since the timeline cache only carries the opaque `provider` /
  /// `canonical` source sentinels. Defaults to no-op for previews/tests.
  var resolveSource: (CalendarTimelineEvent) async -> EventKitEventSource? = { _ in nil }

  @State private var resolvedSource: EventKitEventSource?

  private var tint: Color { Color(lorvexHex: event.color) ?? .accentColor }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: LorvexDesign.Spacing.l) {
          scheduleRow
          if let location = event.location, !location.isEmpty {
            detailRow(icon: "mappin.and.ellipse", title: locationTitle) { plainText(location) }
          }
          if event.isRecurring || event.supportsScopedMutation {
            detailRow(icon: "repeat", title: recurrenceTitle) {
              plainText(event.recurrenceSummary ?? repeatsFallback)
            }
          }
          if let notes = event.notes, !notes.isEmpty {
            detailRow(icon: "note.text", title: notesTitle) { plainText(notes) }
          }
          if let attendees = event.attendees, !attendees.isEmpty {
            detailRow(icon: "person.2", title: attendeesTitle) {
              VStack(alignment: .leading, spacing: 2) {
                ForEach(attendees, id: \.email) { attendee in
                  plainText(attendee.name ?? attendee.email)
                }
              }
            }
          }
          if let urlString = event.url, let url = URL(string: urlString) {
            detailRow(icon: "link", title: urlTitle) {
              Link(urlString, destination: url).font(LorvexDesign.Typography.primaryText)
            }
          }
          sourceRow
        }
        .padding(LorvexDesign.Spacing.l)
      }
      if event.editable {
        Divider()
        actionBar
      }
    }
    .frame(width: 320)
    .background(.background)
    .accessibilityIdentifier("calendar.event.inspector")
    .task(id: event.id) {
      resolvedSource = nil
      resolvedSource = await resolveSource(event)
    }
  }

  private var header: some View {
    HStack(alignment: .top, spacing: LorvexDesign.Spacing.s) {
      RoundedRectangle(cornerRadius: 2, style: .continuous)
        .fill(tint)
        .frame(width: 4, height: 28)
      Text(event.title)
        .font(LorvexDesign.Typography.sectionHeader)
        .foregroundStyle(.primary)
        .lineLimit(3)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: LorvexDesign.Spacing.s)
      InspectorCloseButton(accessibilityIdentifier: "calendar.event.inspector.close", action: close)
    }
    .padding(LorvexDesign.Spacing.m)
  }

  private var scheduleRow: some View {
    detailRow(icon: "calendar", title: whenTitle) {
      VStack(alignment: .leading, spacing: 2) {
        plainText(Self.dateLabel(event.startDate))
        if event.allDay {
          Text(
            LocalizedStringResource(
              "calendar.event.all_day", defaultValue: "All day", table: "Localizable",
              bundle: LorvexL10n.bundle)
          )
          .font(LorvexDesign.Typography.secondaryText)
          .foregroundStyle(.secondary)
        } else {
          let range = lorvexClockTimeRange(start: event.startTime, end: event.endTime)
          if !range.isEmpty {
            Text(range)
              .font(LorvexDesign.Typography.secondaryText)
              .foregroundStyle(.secondary)
          }
        }
      }
    }
  }

  @ViewBuilder
  private var sourceRow: some View {
    if let display = displaySource {
      detailRow(icon: event.editable ? "calendar.badge.checkmark" : "lock", title: calendarTitle) {
        VStack(alignment: .leading, spacing: 2) {
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
    if let resolvedSource {
      return (resolvedSource.calendarTitle, resolvedSource.accountTitle)
    }
    if event.editable {
      return (
        String(
          localized: "calendar.event.source.lorvex", defaultValue: "Lorvex",
          table: "Localizable",
          bundle: LorvexL10n.bundle), nil
      )
    }
    guard !event.source.isEmpty else { return nil }
    return (
      String(
        localized: "calendar.event.source.system", defaultValue: "System Calendar",
        table: "Localizable",
        bundle: LorvexL10n.bundle), nil
    )
  }

  private var actionBar: some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      Button(action: edit) {
        Label(
          String(
            localized: "common.edit", defaultValue: "Edit", table: "Localizable",
            bundle: LorvexL10n.bundle), systemImage: "pencil")
      }
      .buttonStyle(.lorvexPrimary)
      .accessibilityIdentifier("calendar.event.inspector.edit")

      Button(role: .destructive, action: requestDelete) {
        Label(
          String(
            localized: "common.delete", defaultValue: "Delete", table: "Localizable",
            bundle: LorvexL10n.bundle), systemImage: "trash")
      }
      .buttonStyle(.lorvexSecondary)
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
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(LorvexDesign.Typography.tertiaryText.weight(.semibold))
          .foregroundStyle(.secondary)
        content()
      }
      Spacer(minLength: 0)
    }
  }

  private func plainText(_ value: String) -> some View {
    Text(value)
      .font(LorvexDesign.Typography.primaryText)
      .foregroundStyle(.primary)
      .textSelection(.enabled)
      .fixedSize(horizontal: false, vertical: true)
  }

  private static let displayDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.setLocalizedDateFormatFromTemplate("EEEEMMMMd")
    return f
  }()

  /// Render a `yyyy-MM-dd` event date as a localized weekday + month-day label,
  /// falling back to the raw key if it can't be parsed. The day key is a
  /// current-time-zone anchor (matching the localized label's default zone), so
  /// parse it through the shared current-tz `ymd` formatter.
  static func dateLabel(_ ymd: String) -> String {
    guard let date = LorvexDateFormatters.ymd.date(from: ymd) else { return ymd }
    return displayDateFormatter.string(from: date)
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
  private var repeatsFallback: String {
    String(
      localized: "calendar.event.repeats_generic", defaultValue: "Repeating event",
      table: "Localizable", bundle: LorvexL10n.bundle)
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

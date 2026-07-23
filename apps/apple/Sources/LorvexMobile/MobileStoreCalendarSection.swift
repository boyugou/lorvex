import LorvexCore
import SwiftUI

struct MobileStoreCalendarSection: View {
  let events: [CalendarTimelineEvent]?
  let isMutating: Bool
  let isExporting: Bool
  /// Maximum number of events to display. `nil` shows all events (standalone calendar view).
  /// Pass `4` for the Today-embedded summary to keep the list compact.
  let displayLimit: Int?
  /// Section header. Defaults to "Calendar" (the standalone Calendar surface);
  /// the Today-embedded instance passes "Schedule" since there it shows the
  /// day's agenda, not the full calendar.
  var title: String = String(
    localized: "destination.calendar", defaultValue: "Calendar", table: "Localizable",
    bundle: MobileL10n.bundle)
  /// Drop the date from each row's subtitle. The Today-embedded "Schedule" is
  /// today-only, so the date is redundant noise — show just the time. The
  /// standalone Calendar surface spans days, so it keeps the date (default).
  var hidesEventDate: Bool = false
  let createEvent: () -> Void
  let editEvent: (CalendarTimelineEvent) -> Void
  let deleteEvent: (CalendarTimelineEvent) async -> Bool
  let deleteScopedEvent: (CalendarTimelineEvent, CalendarEventEditScope) async -> Bool
  let exportICS: () async -> String?
  var viewAll: (() -> Void)? = nil
  /// When false (the Today-embedded summary), the New Event + Export ICS footer
  /// actions are hidden — creating/exporting belongs on the dedicated Calendar
  /// tab, so Today only shows the day's events (+ a "View all" link).
  var showsActions: Bool = true
  @State private var exportItem: MobileCalendarICSTransferable?
  @State private var exportStatus: MobileCalendarICSExportStatus = .idle
  @State private var eventAwaitingDeleteScope: CalendarTimelineEvent?

  private var actionAccent: Color { .accentColor }
  private var loadedEvents: [CalendarTimelineEvent] { events ?? [] }
  private var visibleEventCount: Int {
    displayLimit.map { min(loadedEvents.count, $0) } ?? loadedEvents.count
  }
  private var hiddenEventCount: Int { max(0, loadedEvents.count - visibleEventCount) }

  var body: some View {
    Section(title) {
      if events == nil {
        MobileSkeletonRows(count: displayLimit ?? 4)
      } else if loadedEvents.isEmpty {
        MobileEmptyState(
          icon: "calendar",
          title: String(
            localized: "calendar.empty.no_events", defaultValue: "No Events", table: "Localizable",
            bundle: MobileL10n.bundle),
          message: String(
            localized: "calendar.empty.no_events.message",
            defaultValue: "Events for this day show up here.", table: "Localizable",
            bundle: MobileL10n.bundle))
      } else {
        let visibleEvents = loadedEvents.prefix(visibleEventCount)
        ForEach(visibleEvents) { event in
          row(for: event)
        }
        if let viewAll, hiddenEventCount > 0 {
          Button {
            viewAll()
          } label: {
            Label(viewAllTitle, systemImage: "calendar")
          }
          .accessibilityIdentifier("mobileCalendar.viewAll")
        }
      }

      if showsActions {
        Button {
          createEvent()
        } label: {
          Label(
            String(
              localized: "calendar.new_event", defaultValue: "New Event", table: "Localizable",
              bundle: MobileL10n.bundle), systemImage: "plus")
        }
        .accessibilityIdentifier("mobileCalendar.create")

        exportControl

        if let message = exportStatus.message {
          Text(message)
            .font(LorvexDesign.Typography.tertiaryText)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("mobileCalendar.exportStatus")
        }
      }
    }
    .mobileCalendarDeleteScopeDialog(
      event: $eventAwaitingDeleteScope,
      delete: deleteScopedEvent)
  }

  @ViewBuilder
  private var exportControl: some View {
    if let exportItem {
      ShareLink(
        item: exportItem,
        preview: SharePreview("lorvex-calendar.ics", image: Image(systemName: "calendar"))
      ) {
        Label(
          String(
            localized: "calendar.share_ics", defaultValue: "Share ICS", table: "Localizable",
            bundle: MobileL10n.bundle), systemImage: "square.and.arrow.up")
      }
      .accessibilityIdentifier("mobileCalendar.shareICS")
    } else {
      Button {
        Task { await prepareExport() }
      } label: {
        Label {
          Text(
            isExporting
              ? String(
                localized: "calendar.preparing_ics", defaultValue: "Preparing ICS",
                table: "Localizable", bundle: MobileL10n.bundle)
              : String(
                localized: "calendar.export_ics", defaultValue: "Export ICS", table: "Localizable",
                bundle: MobileL10n.bundle))
        } icon: {
          if isExporting {
            ProgressView()
          } else {
            Image(systemName: "square.and.arrow.up")
          }
        }
      }
      .disabled(isExporting)
      .accessibilityIdentifier("mobileCalendar.exportICS")
    }
  }

  @MainActor
  private func prepareExport() async {
    exportStatus = .exporting
    guard let ics = await exportICS() else {
      exportStatus = .failed
      exportItem = nil
      return
    }
    exportItem = MobileCalendarICSTransferable(content: ics)
    exportStatus = .ready
  }

  private func row(for event: CalendarTimelineEvent) -> some View {
    HStack(spacing: 12) {
      Image(systemName: event.allDay ? "sun.max" : "calendar")
        .foregroundStyle(.secondary)
        .frame(width: 20)
      VStack(alignment: .leading, spacing: 2) {
        Text(event.title)
          .font(LorvexDesign.Typography.primaryEmphasis)
          .lineLimit(1)
        Text(subtitle(for: event))
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Spacer(minLength: 8)
      if event.isRecurring || event.supportsScopedMutation {
        Image(systemName: "repeat")
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.secondary)
          .accessibilityLabel(
            String(
              localized: "calendar.repeating_event.a11y", defaultValue: "Repeating event",
              table: "Localizable", bundle: MobileL10n.bundle))
      }
    }
    .accessibilityElement(children: .combine)
    // `allowsFullSwipe: false` — full-swipe delete on a calendar event is
    // a one-finger-flick away from removing an EventKit event with no
    // confirm. Tap-to-reveal-and-tap-again gives the user a deliberate
    // commit instead of an accidental destroy.
    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
      if event.editable {
        Button(role: .destructive) {
          requestDelete(event)
        } label: {
          Label(
            String(
              localized: "common.delete", defaultValue: "Delete", table: "Localizable",
              bundle: MobileL10n.bundle), systemImage: "trash")
        }
        .disabled(isMutating)
        .accessibilityIdentifier("mobileCalendar.delete.\(event.id)")
      }
    }
    .swipeActions(edge: .leading, allowsFullSwipe: false) {
      if event.editable {
        Button {
          editEvent(event)
        } label: {
          Label(
            String(
              localized: "common.edit", defaultValue: "Edit", table: "Localizable",
              bundle: MobileL10n.bundle), systemImage: "pencil")
        }
        .tint(actionAccent)
        .disabled(isMutating)
        .accessibilityIdentifier("mobileCalendar.edit.\(event.id)")
      }
    }
    .contextMenu {
      if event.editable {
        Button {
          editEvent(event)
        } label: {
          Label(
            String(
              localized: "common.edit", defaultValue: "Edit", table: "Localizable",
              bundle: MobileL10n.bundle), systemImage: "pencil")
        }
        .disabled(isMutating)

        Button(role: .destructive) {
          requestDelete(event)
        } label: {
          Label(
            String(
              localized: "common.delete", defaultValue: "Delete", table: "Localizable",
              bundle: MobileL10n.bundle), systemImage: "trash")
        }
        .disabled(isMutating)
      }
    }
  }

  private func requestDelete(_ event: CalendarTimelineEvent) {
    if event.supportsScopedMutation {
      eventAwaitingDeleteScope = event
    } else {
      Task { _ = await deleteEvent(event) }
    }
  }

  private func subtitle(for event: CalendarTimelineEvent) -> String {
    let location = event.location.flatMap { $0.isEmpty ? nil : $0 }
    if hidesEventDate {
      // Today's Schedule is today-only: show the time span, not the date.
      let timePart: String
      if event.allDay {
        timePart = String(
          localized: "calendar.all_day", defaultValue: "all day", table: "Localizable",
          bundle: MobileL10n.bundle)
      } else if let start = event.startTime, let end = event.endTime {
        timePart = "\(lorvexClockTimeLabel(start)) – \(lorvexClockTimeLabel(end))"
      } else {
        timePart =
          event.startTime.map(lorvexClockTimeLabel)
          ?? String(
            localized: "calendar.time_unset", defaultValue: "time unset", table: "Localizable",
            bundle: MobileL10n.bundle)
      }
      return location.map { "\(timePart) · \($0)" } ?? timePart
    }
    let dateLabel = Self.formattedDate(event.startDate)
    let time =
      event.allDay
      ? String(
        localized: "calendar.all_day", defaultValue: "all day", table: "Localizable",
        bundle: MobileL10n.bundle)
      : event.startTime.map(lorvexClockTimeLabel)
        ?? String(
          localized: "calendar.time_unset", defaultValue: "time unset", table: "Localizable",
          bundle: MobileL10n.bundle)
    return location.map { "\(dateLabel) \(time) · \($0)" } ?? "\(dateLabel) \(time)"
  }

  private var viewAllTitle: String {
    String(
      format: String(
        localized: "calendar.view_all", defaultValue: "View all (%lld more)", table: "Localizable",
        bundle: MobileL10n.bundle),
      hiddenEventCount
    )
  }

  private static var isoFormatter: DateFormatter { LorvexDateFormatters.ymd }

  private static let displayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = MobileL10n.locale
    f.calendar = Calendar(identifier: .gregorian)
    f.dateStyle = .medium
    f.timeStyle = .none
    return f
  }()

  private static func formattedDate(_ isoDate: String) -> String {
    guard let date = isoFormatter.date(from: isoDate) else { return isoDate }
    return displayFormatter.string(from: date)
  }
}

private enum MobileCalendarICSExportStatus {
  case idle
  case exporting
  case ready
  case failed

  var message: String? {
    switch self {
    case .idle:
      nil
    case .exporting:
      String(
        localized: "calendar.export.preparing", defaultValue: "Preparing calendar export…",
        table: "Localizable", bundle: MobileL10n.bundle)
    case .ready:
      String(
        localized: "calendar.export.ready", defaultValue: "Calendar export is ready to share.",
        table: "Localizable", bundle: MobileL10n.bundle)
    case .failed:
      String(
        localized: "calendar.export.failed", defaultValue: "Couldn't export to Calendar.",
        table: "Localizable", bundle: MobileL10n.bundle)
    }
  }
}

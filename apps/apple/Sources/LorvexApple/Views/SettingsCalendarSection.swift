import AppKit
import LorvexCore
import LorvexDomain
import SwiftUI

// MARK: - Calendar tab

extension SettingsView {
  @ViewBuilder
  var calendarSection: some View {
    Section(String(localized: "settings.calendar.apple_calendar", defaultValue: "Calendar Sync", table: "Localizable", bundle: LorvexL10n.bundle)) {
      SettingsCalendarAccessRecoveryPanel(settingsURL: calendarPrivacySettingsURL)
      SettingsCalendarControlPanel(settings: settings, store: store)
    }

    Section(String(localized: "settings.calendar.status_section", defaultValue: "Calendar Status", table: "Localizable", bundle: LorvexL10n.bundle)) {
      SettingsCalendarStatusPanel(
        importReport: store.lastCalendarImportReport,
        exportReport: store.lastCalendarExportReport
      )
    }
  }

  private var calendarPrivacySettingsURL: URL? {
    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
  }
}

/// Shown only when calendar access needs System Settings recovery. The
/// authorization status is read on appear and re-read when the app regains focus
/// (so returning from System Settings reflects a fresh grant), never on every
/// render — `EKEventStore.authorizationStatus(for:)` should not run per body.
private struct SettingsCalendarAccessRecoveryPanel: View {
  let settingsURL: URL?
  @State private var needsRecovery = false

  var body: some View {
    Group {
      if needsRecovery {
        Label {
          Text(LocalizedStringResource(
            "settings.calendar.access_denied",
            defaultValue: "Calendar access has been denied. Open System Settings to grant access.",
            table: "Localizable",
            bundle: LorvexL10n.bundle
          ))
          .fixedSize(horizontal: false, vertical: true)
        } icon: {
          Image(systemName: "calendar.badge.exclamationmark")
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(Color.orange)
        }

        if let settingsURL {
          OpenSystemSettingsButton(
            label: String(localized: "settings.calendar.open_system_settings", defaultValue: "Open System Settings", table: "Localizable", bundle: LorvexL10n.bundle),
            settingsURL: settingsURL
          )
        }
      }
    }
    .accessibilityIdentifier("settings.calendar.accessRecovery")
    .task { needsRecovery = EventKitAuthorizationHelper().needsSettingsRecovery }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      needsRecovery = EventKitAuthorizationHelper().needsSettingsRecovery
    }
  }
}

private struct SettingsCalendarStatusPanel: View {
  let importReport: CalendarIntegrationReport
  let exportReport: CalendarIntegrationReport

  private var rows: [SettingsCalendarStatusRow] {
    var rows = [
      SettingsCalendarStatusRow(
        id: "ingest",
        title: String(localized: "settings.calendar.ingest_status", defaultValue: "Ingest Status", table: "Localizable", bundle: LorvexL10n.bundle),
        value: importReport.localizedSettingsStatus,
        systemImage: "arrow.down.circle",
        level: level(for: importReport.status)
      ),
      SettingsCalendarStatusRow(
        id: "events-mirrored",
        title: String(localized: "settings.calendar.events_mirrored", defaultValue: "Events Mirrored", table: "Localizable", bundle: LorvexL10n.bundle),
        value: "\(importReport.eventCount)",
        systemImage: "calendar.badge.checkmark",
        level: .neutral
      ),
      SettingsCalendarStatusRow(
        id: "write-back",
        title: String(localized: "settings.calendar.write_back", defaultValue: "Calendar Write-Back", table: "Localizable", bundle: LorvexL10n.bundle),
        value: exportReport.localizedSettingsStatus,
        systemImage: "arrow.up.circle",
        level: level(for: exportReport.status)
      ),
    ]

    if importReport.errorMessage != nil {
      rows.append(errorRow(id: "ingest-error"))
    }
    if let exportedEventID = exportReport.eventID {
      rows.append(SettingsCalendarStatusRow(
        id: "last-event",
        title: String(localized: "settings.calendar.last_event", defaultValue: "Last Event", table: "Localizable", bundle: LorvexL10n.bundle),
        value: exportedEventID,
        systemImage: "calendar.badge.clock",
        level: .neutral
      ))
    }
    if exportReport.errorMessage != nil {
      rows.append(errorRow(id: "write-back-error"))
    }

    return rows
  }

  var body: some View {
    ForEach(rows) { row in
      SettingsCalendarStatusRowView(row: row)
    }
    .accessibilityIdentifier("settings.calendar.status")
  }

  private func level(for status: CalendarIntegrationReport.Status) -> SettingsStatusLevel {
    switch status {
    case .notStarted:
      .neutral
    case .succeeded:
      .success
    case .skipped:
      .warning
    case .failed:
      .error
    }
  }

  /// Shows an actionable hint rather than the raw underlying error
  /// (e.g. "LorvexSync.EnqueueError error 2"), which means nothing to a user.
  private func errorRow(id: String) -> SettingsCalendarStatusRow {
    SettingsCalendarStatusRow(
      id: id,
      title: String(localized: "common.error", defaultValue: "Error", table: "Localizable", bundle: LorvexL10n.bundle),
      value: String(
        localized: "settings.calendar.sync_error_friendly",
        defaultValue:
          "Calendar sync didn’t finish. Check that Lorvex has calendar access in System Settings, then try again.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      ),
      systemImage: "exclamationmark.triangle.fill",
      level: .error
    )
  }
}

private struct SettingsCalendarStatusRow: Identifiable {
  let id: String
  let title: String
  let value: String
  let systemImage: String
  let level: SettingsStatusLevel
}

private struct SettingsCalendarStatusRowView: View {
  let row: SettingsCalendarStatusRow

  var body: some View {
    LabeledContent {
      Text(row.value)
        .foregroundStyle(row.level == .neutral ? AnyShapeStyle(.primary) : AnyShapeStyle(row.level.color))
        .textSelection(.enabled)
        .multilineTextAlignment(.trailing)
        .lineLimit(2)
    } label: {
      Label(row.title, systemImage: row.systemImage)
        .foregroundStyle(row.level == .error ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("settings.calendar.status.\(row.id)")
  }
}

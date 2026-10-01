import AppKit
import LorvexCore
import LorvexDomain
import SwiftUI

// MARK: - Calendar tab

extension SettingsView {
  var calendarSection: some View {
    SettingsCalendarSyncSection(settings: settings, store: store)
  }
}

/// The Calendar page's one group: two-way sync with the user's calendars and
/// what Lorvex may see of them, led by whatever needs attention
/// (``SettingsCalendarNotice``) and silent while all is well. Lorvex reads the
/// calendars on every refresh, so the page offers no read-now action.
///
/// The authorization status is read on appear and re-read when the app regains
/// focus (so returning from System Settings reflects a fresh grant), never on
/// every render — `EKEventStore.authorizationStatus(for:)` should not run per
/// body. Both reads hang off the section, which always draws its controls, so
/// they run even while no notice shows.
private struct SettingsCalendarSyncSection: View {
  @Bindable var settings: AppSettingsStore
  @Bindable var store: AppStore
  @State private var needsAccessRecovery = false

  var body: some View {
    Section(String(localized: "settings.calendar.apple_calendar", defaultValue: "Calendar Sync", table: "Localizable", bundle: LorvexL10n.bundle)) {
      ForEach(notices, id: \.self) { notice in
        noticeRow(notice)
      }
      SettingsCalendarControlPanel(settings: settings, store: store)
    }
    .task { needsAccessRecovery = EventKitAuthorizationHelper().needsSettingsRecovery }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      needsAccessRecovery = EventKitAuthorizationHelper().needsSettingsRecovery
    }
  }

  private var notices: [SettingsCalendarNotice] {
    SettingsCalendarNotice.notices(
      needsAccessRecovery: needsAccessRecovery,
      isSyncEnabled: settings.eventKitEnabled,
      importReport: store.lastCalendarImportReport,
      exportReport: store.lastCalendarExportReport)
  }

  @ViewBuilder
  private func noticeRow(_ notice: SettingsCalendarNotice) -> some View {
    switch notice {
    case .accessDenied:
      Group {
        noticeLabel(
          LocalizedStringResource(
            "settings.calendar.access_denied",
            defaultValue: "Calendar access has been denied. Open System Settings to grant access.",
            table: "Localizable",
            bundle: LorvexL10n.bundle),
          systemImage: "calendar.badge.exclamationmark",
          tint: LorvexDesign.Palette.warning)
        if let settingsURL = Self.calendarPrivacySettingsURL {
          OpenSystemSettingsButton(
            label: String(localized: "settings.calendar.open_system_settings", defaultValue: "Open System Settings", table: "Localizable", bundle: LorvexL10n.bundle),
            settingsURL: settingsURL
          )
        }
      }
      .accessibilityIdentifier("settings.calendar.accessRecovery")
    case .readFailed:
      noticeLabel(
        LocalizedStringResource(
          "settings.calendar.read_failed",
          defaultValue: "Lorvex couldn’t read your calendars. It will try again automatically.",
          table: "Localizable",
          bundle: LorvexL10n.bundle),
        systemImage: "exclamationmark.triangle.fill",
        tint: LorvexDesign.Palette.error)
      .accessibilityIdentifier("settings.calendar.readFailed")
    case .writeFailed:
      noticeLabel(
        LocalizedStringResource(
          "settings.calendar.write_failed",
          defaultValue: "An event you saved in Lorvex didn’t reach your calendar. Save it again to retry.",
          table: "Localizable",
          bundle: LorvexL10n.bundle),
        systemImage: "exclamationmark.triangle.fill",
        tint: LorvexDesign.Palette.error)
      .accessibilityIdentifier("settings.calendar.writeFailed")
    }
  }

  /// The status color marks the icon only, so the sentence reads as text
  /// rather than as a link.
  private func noticeLabel(
    _ text: LocalizedStringResource, systemImage: String, tint: Color
  ) -> some View {
    Label {
      Text(text)
        .fixedSize(horizontal: false, vertical: true)
    } icon: {
      Image(systemName: systemImage)
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(tint)
    }
  }

  private static let calendarPrivacySettingsURL = URL(
    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
}

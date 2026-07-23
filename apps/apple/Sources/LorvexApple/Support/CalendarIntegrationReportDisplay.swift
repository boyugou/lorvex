import Foundation

extension CalendarIntegrationReport {
  var localizedSettingsStatus: String {
    switch status {
    case .notStarted:
      String(
        localized: "settings.calendar.status.not_started",
        defaultValue: "Not Started",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      )
    case .succeeded:
      String(
        localized: "settings.calendar.status.succeeded",
        defaultValue: "Succeeded",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      )
    case .skipped:
      String(
        localized: "settings.calendar.status.skipped",
        defaultValue: "Skipped",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      )
    case .failed:
      String(
        localized: "settings.calendar.status.failed",
        defaultValue: "Failed",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      )
    }
  }
}

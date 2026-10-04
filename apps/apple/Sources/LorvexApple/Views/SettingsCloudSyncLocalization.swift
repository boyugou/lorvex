import Foundation
import LorvexCloudSync
import LorvexCore
import SwiftUI

extension CloudKitAccountAvailability {
  var localizedSettingsStatusLabel: String {
    switch self {
    case .available:
      String(localized: "settings.cloud_sync.account.signed_in", defaultValue: "Signed in", table: "Localizable", bundle: LorvexL10n.bundle)
    case .noAccount:
      String(localized: "settings.cloud_sync.account.not_signed_in", defaultValue: "Not signed in", table: "Localizable", bundle: LorvexL10n.bundle)
    case .restricted:
      String(localized: "settings.cloud_sync.account.restricted", defaultValue: "Restricted", table: "Localizable", bundle: LorvexL10n.bundle)
    case .couldNotDetermine:
      String(localized: "settings.cloud_sync.account.unknown", defaultValue: "Unknown", table: "Localizable", bundle: LorvexL10n.bundle)
    case .temporarilyUnavailable:
      String(
        localized: "settings.cloud_sync.account.temporarily_unavailable",
        defaultValue: "Temporarily unavailable",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      )
    }
  }
}

extension CloudSyncMode {
  /// The switch's label in Settings.
  static var localizedSettingsToggle: String {
    String(
      localized: "settings.cloud_sync.toggle", defaultValue: "Sync with iCloud", table: "Localizable",
      bundle: LorvexL10n.bundle)
  }

  /// The status row's title for the sync state.
  static var localizedSettingsStatusTitle: String {
    String(
      localized: "settings.cloud_sync.status_title", defaultValue: "iCloud Sync", table: "Localizable",
      bundle: LorvexL10n.bundle)
  }

  /// The state as a status value: "On" or "Off".
  var localizedSettingsTitle: String {
    switch self {
    case .off:
      String(localized: "settings.cloud_sync.state.off", defaultValue: "Off", table: "Localizable", bundle: LorvexL10n.bundle)
    case .live:
      String(localized: "settings.cloud_sync.state.on", defaultValue: "On", table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }

  /// What the state means for the user's data, under the switch.
  var localizedSettingsDetail: String {
    switch self {
    case .off:
      String(
        localized: "settings.cloud_sync.off_detail",
        defaultValue:
          "Your tasks stay on this Mac. Turn this on to see the same tasks, lists, and habits on your iPhone and other devices.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      )
    case .live:
      String(
        localized: "settings.cloud_sync.live_detail",
        defaultValue:
          "Your tasks, lists, and habits stay the same on every device signed in to your iCloud account.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      )
    }
  }
}

extension CloudSyncStatusReport {
  var localizedSettingsSummary: String {
    switch mode {
    case .off:
      return String(localized: "settings.cloud_sync.summary.off", defaultValue: "iCloud Sync is off.", table: "Localizable", bundle: LorvexL10n.bundle)
    case .live:
      return liveLocalizedSettingsSummary
    }
  }

  private var liveLocalizedSettingsSummary: String {
    switch accountAvailability {
    case .available:
      if let lastPushAt {
        return lorvexSingleFinalPeriod(
          String(
            format: String(
              localized: "settings.cloud_sync.summary.live_last_push",
              defaultValue: "Live sync active. Last push %@.",
              table: "Localizable",
              bundle: LorvexL10n.bundle
            ),
            cloudSyncRelativeDateString(for: lastPushAt)
          )
        )
      }
      return String(
        localized: "settings.cloud_sync.summary.live_no_push",
        defaultValue: "Live sync active. No push yet.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      )
    case .noAccount:
      return String(
        localized: "settings.cloud_sync.account.no_account_message",
        defaultValue: "No iCloud account. Sign in via System Settings > Apple Account.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      )
    case .restricted:
      return String(
        localized: "settings.cloud_sync.account.restricted_message",
        defaultValue: "iCloud is restricted by a device management profile.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      )
    case .couldNotDetermine:
      return String(
        localized: "settings.cloud_sync.account.unknown_message",
        defaultValue: "Unable to determine iCloud account status.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      )
    case .temporarilyUnavailable:
      return String(
        localized: "settings.cloud_sync.account.temporarily_unavailable_message",
        defaultValue: "iCloud account is temporarily unavailable.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      )
    }
  }

}

/// Abbreviated relative-time string ("3m", "2h") for the CloudSync settings
/// surface, relative to now. Shared by both CloudSync settings views.
func cloudSyncRelativeDateString(for date: Date) -> String {
  LorvexDateFormatters.relative(date, to: Date(), unitsStyle: .abbreviated, dateTimeStyle: .numeric)
}

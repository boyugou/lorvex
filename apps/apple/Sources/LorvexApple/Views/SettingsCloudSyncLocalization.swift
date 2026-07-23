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
  var localizedSettingsTitle: String {
    switch self {
    case .off:
      String(localized: "settings.cloud_sync.mode.off", defaultValue: "Off", table: "Localizable", bundle: LorvexL10n.bundle)
    case .recordPlan:
      String(
        localized: "settings.cloud_sync.mode.record_plan",
        defaultValue: "Record Plan (Debug)",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      )
    case .live:
      String(localized: "settings.cloud_sync.mode.live", defaultValue: "Live", table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }

  var localizedSettingsDetail: String {
    switch self {
    case .off:
      String(
        localized: "settings.cloud_sync.mode.off_detail",
        defaultValue: "iCloud sync is disabled. No data is pushed to or pulled from CloudKit.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      )
    case .recordPlan:
      String(
        localized: "settings.cloud_sync.mode.record_plan_detail",
        defaultValue: "Registers the CloudKit subscription but runs no sync cycle. For debugging only.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      )
    case .live:
      String(
        localized: "settings.cloud_sync.mode.live_detail",
        defaultValue: "Pushes records to the private CloudKit database and applies remote changes on arrival.",
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
    case .recordPlan:
      return String(
        localized: "settings.cloud_sync.summary.record_plan",
        defaultValue: "Record-plan debug mode: records are projected but not saved.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      )
    case .live:
      return liveLocalizedSettingsSummary
    }
  }

  private var liveLocalizedSettingsSummary: String {
    switch accountAvailability {
    case .available:
      if let lastPushAt {
        return String(
          format: String(
            localized: "settings.cloud_sync.summary.live_last_push",
            defaultValue: "Live sync active. Last push %@.",
            table: "Localizable",
            bundle: LorvexL10n.bundle
          ),
          cloudSyncRelativeDateString(for: lastPushAt)
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
  LorvexDateFormatters.abbreviatedRelative.localizedString(for: date, relativeTo: Date())
}

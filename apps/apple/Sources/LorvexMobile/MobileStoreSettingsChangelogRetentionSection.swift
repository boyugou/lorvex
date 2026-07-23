import LorvexCore
import LorvexDomain
import SwiftUI

/// Retention control for the AI changelog on the mobile Settings screen: how long
/// the assistant-write audit trail is kept before the sync sweep trims it. "Off"
/// stops recording new entries and clears existing ones on every synced device.
/// Writes the account-scoped virtual `ai_changelog_retention_policy` preference
/// (``ChangelogRetentionPolicy``).
struct MobileStoreSettingsChangelogRetentionSection: View {
  @Bindable var store: MobileStore

  @State private var current: ChangelogRetentionPolicy = .maximum
  @State private var selection: String = ChangelogRetentionPolicy.maximum.wireValue
  @State private var isLoaded = false

  private static let presets: [ChangelogRetentionPolicy] = [
    .maximum, .days(90), .days(30), .days(7), .off,
  ]

  var body: some View {
    Section {
      Picker(
        String(
          localized: "settings.activity.retention.label", defaultValue: "Keep AI activity log",
          table: "Localizable", bundle: MobileL10n.bundle),
        selection: $selection
      ) {
        ForEach(options, id: \.wireValue) { policy in
          Text(Self.label(for: policy)).tag(policy.wireValue)
        }
      }
      .onChange(of: selection) { _, newValue in persist(newValue) }
      .accessibilityIdentifier("settings.activity.retention.picker")
    } header: {
      Text(
        String(
          localized: "settings.activity.retention.title", defaultValue: "Activity Log Retention",
          table: "Localizable", bundle: MobileL10n.bundle))
    } footer: {
      Text(footnote)
    }
    .task {
      let policy = await store.loadChangelogRetentionPolicy()
      current = policy
      selection = policy.wireValue
      isLoaded = true
    }
  }

  /// Preset options plus the current stored policy when it is a custom day count
  /// (an assistant can set any positive N via `set_preference`), so the picker
  /// always has a tag matching the selection and never silently rewrites it.
  private var options: [ChangelogRetentionPolicy] {
    var result = Self.presets
    if !result.contains(where: { $0.wireValue == current.wireValue }) {
      result.append(current)
    }
    return result
  }

  private var footnote: String {
    if case .off = ChangelogRetentionPolicy.parse(selection) {
      return String(
        localized: "settings.activity.retention.footer.off",
        defaultValue: "Off stops recording and clears existing entries on all your devices.",
        table: "Localizable", bundle: MobileL10n.bundle)
    }
    return String(
      localized: "settings.activity.retention.footer",
      defaultValue:
        "Older entries are trimmed on sync. Off stops recording and clears existing entries on all your devices.",
      table: "Localizable", bundle: MobileL10n.bundle)
  }

  private func persist(_ wire: String) {
    guard isLoaded else { return }
    let policy = ChangelogRetentionPolicy.parse(wire)
    current = policy
    Task { await store.saveChangelogRetentionPolicy(policy) }
  }

  private static func label(for policy: ChangelogRetentionPolicy) -> String {
    switch policy {
    case .maximum:
      return String(
        localized: "settings.activity.retention.maximum", defaultValue: "Maximum (10,000 entries)",
        table: "Localizable", bundle: MobileL10n.bundle)
    case .off:
      return String(
        localized: "settings.activity.retention.off", defaultValue: "Off (never store)",
        table: "Localizable", bundle: MobileL10n.bundle)
    case .days(let n):
      switch n {
      case 90:
        return String(
          localized: "settings.activity.retention.days.90", defaultValue: "90 days",
          table: "Localizable", bundle: MobileL10n.bundle)
      case 30:
        return String(
          localized: "settings.activity.retention.days.30", defaultValue: "30 days",
          table: "Localizable", bundle: MobileL10n.bundle)
      case 7:
        return String(
          localized: "settings.activity.retention.days.7", defaultValue: "7 days",
          table: "Localizable", bundle: MobileL10n.bundle)
      default:
        return String(
          localized: "settings.activity.retention.days.custom", defaultValue: "\(Int(n)) days",
          table: "Localizable", bundle: MobileL10n.bundle)
      }
    }
  }
}

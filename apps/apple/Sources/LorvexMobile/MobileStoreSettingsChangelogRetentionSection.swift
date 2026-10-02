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
    // Skip a no-op write. The load assigns `selection` and flips `isLoaded` in
    // one synchronous batch, so `.onChange` fires with `isLoaded` already true;
    // without the value check every Settings appearance would re-persist the
    // loaded policy — churning the retention version fleet-wide and writing a
    // phantom `ai_changelog` row into the very log the user is trimming.
    guard isLoaded, wire != current.wireValue else { return }
    let policy = ChangelogRetentionPolicy.parse(wire)
    current = policy
    Task { await store.saveChangelogRetentionPolicy(policy) }
  }

  private static func label(for policy: ChangelogRetentionPolicy) -> String {
    switch policy {
    case .maximum:
      let entries = Int(SyncNaming.auditMaxEntriesSafeguard)
      return String(
        localized: "settings.activity.retention.maximum", defaultValue: "Maximum (\(entries) entries)",
        table: "Localizable", bundle: MobileL10n.bundle)
    case .off:
      return String(
        localized: "settings.activity.retention.off", defaultValue: "Off (never store)",
        table: "Localizable", bundle: MobileL10n.bundle)
    case .days(let n):
      return String(
        localized: "settings.activity.retention.days", defaultValue: "\(Int(n)) days",
        table: "Localizable", bundle: MobileL10n.bundle)
    }
  }
}

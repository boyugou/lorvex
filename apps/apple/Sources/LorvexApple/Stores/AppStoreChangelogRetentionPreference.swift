import Foundation
import LorvexCore
import LorvexDomain

/// Read/write surface for the virtual `ai_changelog_retention_policy` API — this
/// device's choice of how long the AI activity log is kept before it is trimmed.
/// The log never leaves the device, and neither does the policy; `.off`
/// additionally stops recording new entries and purges existing ones. A missing
/// or malformed value reads as `.maximum`. Only the user writes it (an assistant's
/// `set_preference` for it is refused).
extension AppStore {
  func loadChangelogRetentionPolicy() async -> ChangelogRetentionPolicy {
    let raw = try? await core.getPreference(key: PreferenceKeys.prefAiChangelogRetentionPolicy)
    return ChangelogRetentionPolicy.parse(raw ?? nil)
  }

  @discardableResult
  func saveChangelogRetentionPolicy(_ policy: ChangelogRetentionPolicy) async -> Bool {
    do {
      _ = try await core.setPreference(
        key: PreferenceKeys.prefAiChangelogRetentionPolicy, value: policy.wireValue)
      return true
    } catch {
      await presentUserFacingError(error)
      return false
    }
  }
}

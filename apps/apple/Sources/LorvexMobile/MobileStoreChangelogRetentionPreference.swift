import Foundation
import LorvexCore
import LorvexDomain

/// Read/write surface for the virtual `ai_changelog_retention_policy` API on the
/// mobile settings screen; mirrors the macOS semantics. Dedicated account-scoped
/// metadata propagates the choice across devices; `.off` also stops recording
/// new entries and purges existing ones. A missing or malformed value reads as
/// `.maximum`.
extension MobileStore {
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

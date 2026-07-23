import Foundation
import LorvexCore
import LorvexDomain

/// Read/write surface for the `notification_show_task_notes` preference: the
/// local, per-device choice to let a task's freeform notes appear as the body
/// of its reminder notification. OFF by default — notes can carry sensitive
/// freeform text the author didn't necessarily intend to expose on a lock
/// screen or banner, so reminders show only non-sensitive fallback copy unless
/// the user opts in on this Mac.
extension AppStore {
  func loadShowTaskNotesInNotificationsPreference() async -> Bool {
    let raw = try? await core.getPreference(key: PreferenceKeys.prefNotificationShowTaskNotes)
    return raw == "true"
  }

  @discardableResult
  func saveShowTaskNotesInNotificationsPreference(_ enabled: Bool) async -> Bool {
    do {
      _ = try await core.setPreference(
        key: PreferenceKeys.prefNotificationShowTaskNotes, value: enabled ? "true" : "false")
      return true
    } catch {
      await presentUserFacingError(error)
      return false
    }
  }
}

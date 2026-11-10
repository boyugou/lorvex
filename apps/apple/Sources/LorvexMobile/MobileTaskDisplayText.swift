import Foundation
import LorvexCore

public enum MobileTaskDisplayText {
  /// The word on the badge of a task whose dependencies are still open.
  public static var blocked: String {
    String(
      localized: "task.status.blocked", defaultValue: "Blocked", table: "Localizable",
      bundle: MobileL10n.bundle)
  }

  /// The words of a task's hand-off marker, on its row and in its detail.
  public static func delegation(_ marker: LorvexTaskDelegationMarker) -> String {
    switch marker {
    case .withAssistant:
      String(
        localized: "task.delegation.with_assistant", defaultValue: "With assistant",
        table: "Localizable", bundle: MobileL10n.bundle)
    case .assistantReplied:
      String(
        localized: "task.delegation.assistant_replied", defaultValue: "Assistant replied",
        table: "Localizable", bundle: MobileL10n.bundle)
    }
  }
}

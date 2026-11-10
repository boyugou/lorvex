import Foundation
import LorvexCore

public enum TaskDisplayText {
  /// The word on the badge of a task whose dependencies are still open.
  public static var blocked: String {
    String(localized: "task.status.blocked", defaultValue: "Blocked", table: "Localizable", bundle: LorvexL10n.bundle)
  }

  /// What a task's completion circle does: Complete for an open task, Reopen
  /// for a done one. Rows show it as the circle's tooltip and offer it to
  /// VoiceOver as a named action.
  public static func completionToggle(isDone: Bool) -> String {
    isDone
      ? String(localized: "common.reopen", defaultValue: "Reopen", table: "Localizable", bundle: LorvexL10n.bundle)
      : String(localized: "common.complete", defaultValue: "Complete", table: "Localizable", bundle: LorvexL10n.bundle)
  }

  /// "Hidden until Oct 3": the day a task set aside until then comes back
  /// into view, given as a short label.
  public static func hiddenUntil(_ day: String) -> String {
    String(
      format: String(localized: "task.row.hidden_until", defaultValue: "Hidden until %@", table: "Localizable", bundle: LorvexL10n.bundle),
      day)
  }

  /// The words of a task's hand-off marker, on its row and in its inspector.
  public static func delegation(_ marker: LorvexTaskDelegationMarker) -> String {
    switch marker {
    case .withAssistant:
      String(
        localized: "task.delegation.with_assistant", defaultValue: "With assistant", table: "Localizable",
        bundle: LorvexL10n.bundle)
    case .assistantReplied:
      String(
        localized: "task.delegation.assistant_replied", defaultValue: "Assistant replied", table: "Localizable",
        bundle: LorvexL10n.bundle)
    }
  }

  /// The menu item of a hand-off action.
  public static func delegationAction(_ action: LorvexTaskDelegationAction) -> String {
    switch action {
    case .handToAssistant:
      String(
        localized: "task.action.hand_to_assistant", defaultValue: "Hand to Assistant", table: "Localizable",
        bundle: LorvexL10n.bundle)
    case .takeBack:
      String(
        localized: "task.action.take_back", defaultValue: "Take Back", table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }
}

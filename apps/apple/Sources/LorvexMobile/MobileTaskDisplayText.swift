import Foundation
import LorvexCore

public enum MobileTaskDisplayText {
  /// The word on the badge of a task whose dependencies are still open.
  public static var blocked: String {
    String(
      localized: "task.status.blocked", defaultValue: "Blocked", table: "Localizable",
      bundle: MobileL10n.bundle)
  }
}

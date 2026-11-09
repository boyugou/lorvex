import Observation

/// The state behind Settings' "Open at Login" switch.
///
/// The switch shows what the system reports and asks it again after every
/// change, so it also follows a change the user made in System Settings once
/// ``refresh()`` runs. Turning it on can leave the item waiting for the user's
/// approval there (``LoginItemStatus/needsApproval``), which still counts as
/// on: the choice was made and only the allowance is missing.
@MainActor
@Observable
final class OpenAtLoginModel {
  @ObservationIgnored private let loginItem: any LoginItemControlling

  /// What the system last reported. It is read once when the model is made,
  /// on every ``refresh()``, and after every change, never while a view
  /// renders: each read is a blocking round trip to a system service (about
  /// 60 ms on macOS 27), and the Settings pane read it a dozen times per
  /// update, which macOS reported as a hang.
  private(set) var status: LoginItemStatus

  /// Whether the last change ended somewhere other than where it was asked to.
  /// The switch then shows where the item really is, with a note.
  private(set) var lastChangeFailed = false

  init(loginItem: any LoginItemControlling) {
    self.loginItem = loginItem
    status = loginItem.status
  }

  /// Whether the switch is on: the item is on, or waits only for approval.
  var isOn: Bool { status != .off }

  /// Turns the login item on or off. A failure is judged by where the item
  /// ended up, not by the error: registering an item that is already on throws
  /// and still leaves it on.
  func setOn(_ on: Bool) {
    do {
      if on { try loginItem.register() } else { try loginItem.unregister() }
    } catch {
      // Judged below.
    }
    status = loginItem.status
    lastChangeFailed = (status != .off) != on
  }

  /// Asks the system again, dropping the note about an earlier failure.
  func refresh() {
    lastChangeFailed = false
    status = loginItem.status
  }

  func openSystemSettings() {
    loginItem.openSystemSettings()
  }
}

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
  /// Bumped whenever the system's answer may have changed, so views that read
  /// ``status`` ask again.
  private var revision = 0

  /// Whether the last change ended somewhere other than where it was asked to.
  /// The switch then shows where the item really is, with a note.
  private(set) var lastChangeFailed = false

  init(loginItem: any LoginItemControlling) {
    self.loginItem = loginItem
  }

  var status: LoginItemStatus {
    _ = revision
    return loginItem.status
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
    lastChangeFailed = (loginItem.status != .off) != on
    revision += 1
  }

  /// Asks the system again, dropping the note about an earlier failure.
  func refresh() {
    lastChangeFailed = false
    revision += 1
  }

  func openSystemSettings() {
    loginItem.openSystemSettings()
  }
}

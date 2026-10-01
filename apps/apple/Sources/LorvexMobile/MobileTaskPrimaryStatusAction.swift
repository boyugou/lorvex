import LorvexCore
import SwiftUI

/// The one status transition the task detail exposes as its prominent action:
/// the toolbar's on a screen of its own, the header row's in a split's detail
/// pane. Every `LorvexTask.Status` maps to exactly one case: an
/// active task (open or in progress) completes, a resolved task (completed or
/// cancelled) reopens, and a parked (someday) task moves back to open. The
/// parked case drives the same reopen transition as `reopen`; it only reads as
/// "Move to Open" because the task was never finished.
enum MobileTaskPrimaryStatusAction: Equatable {
  case complete
  case reopen
  case moveToOpen

  init(status: LorvexTask.Status) {
    switch status {
    case .open, .inProgress:
      self = .complete
    case .completed, .cancelled:
      self = .reopen
    case .someday:
      self = .moveToOpen
    }
  }

  var title: String {
    switch self {
    case .complete:
      return String(
        localized: "action.complete", defaultValue: "Complete", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .reopen:
      return String(
        localized: "action.reopen", defaultValue: "Reopen", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .moveToOpen:
      return String(
        localized: "action.move_to_open", defaultValue: "Move to Open", table: "Localizable",
        bundle: MobileL10n.bundle)
    }
  }

  var systemImage: String {
    switch self {
    case .complete: return "checkmark.circle"
    case .reopen: return "arrow.counterclockwise"
    case .moveToOpen: return "arrow.up.circle"
    }
  }

  /// Completing is tinted with the done color so it reads as the finishing
  /// step; both reopening actions keep the accent tint (`nil`).
  var tint: Color? {
    self == .complete ? LorvexDesign.Palette.done : nil
  }

  var accessibilityIdentifier: String {
    switch self {
    case .complete: return "task.detail.complete"
    case .reopen: return "task.detail.reopen"
    case .moveToOpen: return "task.detail.moveToOpen"
    }
  }

  /// `true` when performing the action drives the store's reopen transition
  /// (`reopen` and `moveToOpen`); `false` when it drives the complete transition.
  var performsReopen: Bool {
    self != .complete
  }
}

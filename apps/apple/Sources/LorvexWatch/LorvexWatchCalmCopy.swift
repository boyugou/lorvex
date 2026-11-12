import Foundation
import LorvexCore

/// The words of the watch pages.
enum LorvexWatchCalmCopy {
  static var todayTitle: String {
    String(localized: "watch.today.title", defaultValue: "Today", table: "Localizable", bundle: WatchL10n.bundle)
  }

  /// "Until 10:45 AM" while a task's saved time runs.
  static func until(_ minutes: Int) -> String {
    String(
      format: String(localized: "watch.calm.until", defaultValue: "Until %@", table: "Localizable", bundle: WatchL10n.bundle),
      lorvexClockTimeLabel(minutes: minutes))
  }

  /// The list's footer once the phone's copy has aged: "Synced 3h ago".
  static func synced(_ age: String) -> String {
    String(
      format: String(localized: "watch.status.synced_at", defaultValue: "Synced %@", table: "Localizable", bundle: WatchL10n.bundle),
      age)
  }

  /// A task or habit action that failed to save on the watch.
  static var actionFailed: String {
    String(
      localized: "watch.error.action_failed", defaultValue: "That change didn’t save. Try again.",
      table: "Localizable", bundle: WatchL10n.bundle)
  }

  /// An action that cannot save until the iPhone has sent the watch its first
  /// copy of Today.
  static var openPhoneFirst: String {
    String(
      localized: "watch.error.open_phone_first",
      defaultValue: "Open Lorvex on your iPhone first, then try again.",
      table: "Localizable", bundle: WatchL10n.bundle)
  }

  /// The headline of an action the iPhone did not apply, naming the action.
  static func notApplied(_ mutation: LorvexWatchMutation) -> String {
    switch mutation {
    case .completeTask:
      String(
        localized: "watch.delivery.rejected.complete", defaultValue: "Couldn’t complete",
        table: "Localizable", bundle: WatchL10n.bundle)
    case .startTask:
      String(
        localized: "watch.delivery.rejected.start", defaultValue: "Couldn’t start",
        table: "Localizable", bundle: WatchL10n.bundle)
    case .pauseTask:
      String(
        localized: "watch.delivery.rejected.pause", defaultValue: "Couldn’t pause",
        table: "Localizable", bundle: WatchL10n.bundle)
    case .deferTaskToTomorrow:
      String(
        localized: "watch.delivery.rejected.tomorrow", defaultValue: "Couldn’t move to tomorrow",
        table: "Localizable", bundle: WatchL10n.bundle)
    case .cancelTask:
      String(
        localized: "watch.delivery.rejected.cancel", defaultValue: "Couldn’t cancel",
        table: "Localizable", bundle: WatchL10n.bundle)
    case .captureTask:
      String(
        localized: "watch.delivery.rejected.capture", defaultValue: "Couldn’t add task",
        table: "Localizable", bundle: WatchL10n.bundle)
    case .completeHabit:
      String(
        localized: "watch.delivery.rejected.habit", defaultValue: "Couldn’t check in",
        table: "Localizable", bundle: WatchL10n.bundle)
    }
  }

  static var overdue: String {
    String(localized: "watch.task.overdue", defaultValue: "Overdue", table: "Localizable", bundle: WatchL10n.bundle)
  }

  static var started: String {
    String(localized: "watch.task.started", defaultValue: "Started", table: "Localizable", bundle: WatchL10n.bundle)
  }

  /// A task that waits on an unfinished task, so it cannot be started yet.
  static var blocked: String {
    String(localized: "watch.task.blocked", defaultValue: "Blocked", table: "Localizable", bundle: WatchL10n.bundle)
  }

  static func complete(_ title: String) -> String {
    String(
      format: String(
        localized: "watch.action.complete.a11y", defaultValue: "Mark %@ complete", table: "Localizable",
        bundle: WatchL10n.bundle), title)
  }

  /// The hint on a task's title, which opens its actions.
  static var actionsHint: String {
    String(
      localized: "watch.task.actions.hint", defaultValue: "Shows this task’s actions", table: "Localizable",
      bundle: WatchL10n.bundle)
  }

  static var habitsLabel: String {
    String(localized: "watch.section.habits", defaultValue: "Habits", table: "Localizable", bundle: WatchL10n.bundle)
  }

  /// The line under the last row when the phone sent only the head of a long
  /// list: how many more tasks Today holds.
  static func moreToday(_ count: Int) -> String {
    String(
      localized: "watch.today.more", defaultValue: "\(count) more today", table: "Localizable",
      bundle: WatchL10n.bundle)
  }

  static var done: String {
    String(localized: "watch.calm.done", defaultValue: "Done", table: "Localizable", bundle: WatchL10n.bundle)
  }

  /// A habit set aside for today, read by VoiceOver on its ring.
  static var skippedToday: String {
    String(
      localized: "watch.habit.skipped_today", defaultValue: "Skipped today", table: "Localizable",
      bundle: WatchL10n.bundle)
  }

  /// The empty Today page's headline, the same words the widgets use.
  static var allClear: String {
    String(localized: "watch.today.all_clear", defaultValue: "All clear", table: "Localizable", bundle: WatchL10n.bundle)
  }

  /// The empty Today page's second line: how many tasks got done today, or
  /// that nothing is left when none did.
  static func emptyLine(done: Int) -> String {
    guard done > 0 else {
      return String(
        localized: "watch.today.nothing_left", defaultValue: "Nothing left for today.", table: "Localizable",
        bundle: WatchL10n.bundle)
    }
    return String(
      localized: "watch.today.done_count", defaultValue: "\(done) done today", table: "Localizable",
      bundle: WatchL10n.bundle)
  }
}

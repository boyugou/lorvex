import Foundation

/// Durable handoff for a notification-action failure (Complete / Defer / Snooze)
/// that happened before any live observer could surface it.
///
/// `LorvexMobileAppDelegate` can run a background notification action at a cold
/// (background) launch — woken by the tapped action itself — before SwiftUI
/// attaches the store and starts `observeNotificationActionErrors`. At that
/// moment the in-process `.lorvexNotificationActionError` post has no observer
/// and vanishes: the write failed, the notification was consumed, and nothing is
/// ever shown. The delegate records the failure here (`record`); `MobileStore`
/// drains it on the next foreground (`consumePendingNotificationActionError`)
/// into its error banner. The live observer clears any recorded breadcrumb when
/// it surfaces the same failure, so a warm failure is shown exactly once.
///
/// Persisted in `UserDefaults` (`.standard` by default, matching the store's
/// defaults wiring) so it survives a background launch whose process exits before
/// the UI attaches.
public struct MobileNotificationActionErrorHandoff {
  public static let pendingErrorKey = "pendingNotificationActionError"

  let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  /// Whether a failure is waiting to be surfaced. The key's mere presence is the
  /// flag; an empty stored value means "pending, no message" (the store applies a
  /// localized fallback).
  public var hasPendingError: Bool {
    defaults.object(forKey: Self.pendingErrorKey) != nil
  }

  /// The pending failure's message, or nil when there is a pending failure with
  /// no message (or nothing pending — disambiguate with ``hasPendingError``).
  public var pendingMessage: String? {
    let value = defaults.string(forKey: Self.pendingErrorKey)
    return (value?.isEmpty ?? true) ? nil : value
  }

  /// Record a failure. An empty string stands in for "no message", keeping the
  /// key present as the pending flag. Record BEFORE the in-process post so the
  /// live observer can't clear the breadcrumb before it exists.
  public func record(message: String?) {
    defaults.set(message ?? "", forKey: Self.pendingErrorKey)
  }

  public func clear() {
    defaults.removeObject(forKey: Self.pendingErrorKey)
  }
}

import Foundation
import LorvexCore

/// Durable handoff for a notification-action failure (Complete / Defer / Snooze)
/// that happened before any live observer could surface it.
///
/// `LorvexMobileAppDelegate` can run a background notification action at a cold
/// (background) launch — woken by the tapped action itself — before SwiftUI
/// attaches the store and starts `observeNotificationActionErrors`. At that
/// moment the in-process `.lorvexNotificationActionError` post has no observer
/// and vanishes: the write failed, the notification was consumed, and nothing is
/// ever shown. The delegate records the failure's
/// ``UserFacingError/Classification`` here (``record(_:)``); `MobileStore` drains
/// it on the next foreground (`consumePendingNotificationActionError`) into its
/// error banner. The live observer clears any recorded breadcrumb when it
/// surfaces the same failure, so a warm failure is shown exactly once.
///
/// Persisted in `UserDefaults` (`.standard` by default, matching the store's
/// defaults wiring) as JSON so it survives a background launch whose process
/// exits before the UI attaches.
public struct MobileNotificationActionErrorHandoff {
  public static let pendingErrorKey = "pendingNotificationActionError"

  let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  /// Whether a failure is waiting to be surfaced. The key's mere presence is the
  /// flag; an empty stored value means "pending, no detail" (the store applies a
  /// localized fallback).
  public var hasPendingError: Bool {
    defaults.object(forKey: Self.pendingErrorKey) != nil
  }

  /// The pending failure's classification, or nil when the pending failure
  /// carries no detail (any stored value that does not decode as a
  /// classification counts as no detail) or nothing is pending — disambiguate
  /// with ``hasPendingError``.
  public var pendingClassification: UserFacingError.Classification? {
    guard let data = defaults.data(forKey: Self.pendingErrorKey), !data.isEmpty else {
      return nil
    }
    return try? JSONDecoder().decode(UserFacingError.Classification.self, from: data)
  }

  /// Record a failure. Empty data stands in for "no detail", keeping the key
  /// present as the pending flag. Record BEFORE the in-process post so the
  /// live observer can't clear the breadcrumb before it exists.
  public func record(_ classification: UserFacingError.Classification?) {
    let data = classification.flatMap { try? JSONEncoder().encode($0) } ?? Data()
    defaults.set(data, forKey: Self.pendingErrorKey)
  }

  public func clear() {
    defaults.removeObject(forKey: Self.pendingErrorKey)
  }
}

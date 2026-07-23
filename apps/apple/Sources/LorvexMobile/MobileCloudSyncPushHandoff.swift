import Foundation

/// Durable handoff for a CloudKit silent push that arrived before anyone could
/// drain it.
///
/// `LorvexMobileAppDelegate` can receive the private-database push before
/// SwiftUI has attached the store to it (a cold launch — especially a
/// background launch woken by the push itself). At that moment the in-process
/// `.lorvexCloudKitRemoteChange` notification may have no observer, so the
/// wake-up would vanish and nothing would drain the inbound backlog until an
/// unrelated future trigger. The delegate records the pending push here
/// (`recordPendingPush`); `MobileStore` consumes it on store attachment
/// (`consumePendingCloudSyncPushHandoffIfNeeded`) by running the drain the
/// push asked for. Every arrival replaces the persisted token; a completed
/// refresh may clear only the exact token it owns. This compare-and-clear
/// contract prevents an older coalesced refresh waiter from acknowledging a
/// newer push that arrived while the waiter was resuming.
///
/// Persisted in `UserDefaults` (`.standard` by default, matching the store's
/// own defaults wiring via `MobileSetupPreferences`) so the handoff survives a
/// background launch whose process exits before the UI ever attaches.
public struct MobileCloudSyncPushHandoff {
  public static let pendingPushKey = "pendingCloudSyncPushHandoff"

  let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  public var hasPendingPush: Bool {
    pendingToken != nil
  }

  public var pendingToken: String? {
    defaults.string(forKey: Self.pendingPushKey)
  }

  /// Record a fresh push generation and return the token its eventual successful
  /// foreground drain must acknowledge. A later arrival replaces this token, so
  /// an older owner can no longer clear the newer debt.
  @discardableResult
  public func recordPendingPush() -> String {
    let token = UUID().uuidString.lowercased()
    defaults.set(token, forKey: Self.pendingPushKey)
    return token
  }

  /// Clear the durable debt only when it still belongs to `token`.
  @discardableResult
  public func acknowledgePendingPush(token: String) -> Bool {
    guard pendingToken == token else { return false }
    defaults.removeObject(forKey: Self.pendingPushKey)
    return true
  }
}

@preconcurrency import EventKit
import Foundation

/// Listens for EKEventStoreChanged notifications and calls a refresh closure
/// on the MainActor when the system calendar database changes.
///
/// Wire this into the app lifecycle via `.task` on the root view or in
/// `AppStoreRuntimeLifecycle`. The observation runs for the lifetime of the
/// async task that calls `observe()`.
struct EventKitChangeObserver: Sendable {
  let onChanged: @Sendable () async -> Void

  /// Begins observing EKEventStoreChanged notifications. Suspends until the
  /// task is cancelled. Call once at app startup.
  func observe() async {
    let notifications = NotificationCenter.default.notifications(
      named: .EKEventStoreChanged
    )
    for await _ in notifications {
      await onChanged()
    }
  }
}

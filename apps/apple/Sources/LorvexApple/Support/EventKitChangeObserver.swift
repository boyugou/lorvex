@preconcurrency import EventKit
import Foundation
import LorvexCore

/// Listens for EKEventStoreChanged notifications and calls a refresh closure
/// when the system calendar database changes.
///
/// Wire this into the app lifecycle via `.task` on the root view or in
/// `AppStoreRuntimeLifecycle`. The observation runs for the lifetime of the
/// async task that calls `observe()`.
///
/// A calendar sync posts a burst of notifications. Each one signals a
/// ``BurstCoalescer`` rather than awaiting the refresh, so a burst runs the
/// refresh once, plus once more when a notification arrived while it was
/// reading.
struct EventKitChangeObserver: Sendable {
  let onChanged: @Sendable () async -> Void

  /// Begins observing EKEventStoreChanged notifications. Suspends until the
  /// task is cancelled. Call once at app startup.
  func observe() async {
    let coalescer = BurstCoalescer()
    let notifications = NotificationCenter.default.notifications(
      named: .EKEventStoreChanged
    )
    for await _ in notifications {
      await coalescer.signal(onChanged)
    }
  }
}

#if canImport(EventKit)
  @preconcurrency import EventKit
  import Foundation
  import LorvexCore

  /// Calls a refresh closure when the system calendar database changes.
  ///
  /// A calendar sync posts a burst of EKEventStoreChanged notifications. Each
  /// one signals a ``BurstCoalescer`` rather than awaiting the refresh, so a
  /// burst runs the refresh once, plus once more when a notification arrived
  /// while it was reading.
  struct MobileEventKitChangeObserver: Sendable {
    let onChanged: @Sendable () async -> Void

    /// Begins observing EKEventStoreChanged notifications. Suspends until the
    /// task is cancelled.
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
#endif

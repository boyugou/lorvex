#if canImport(EventKit)
  @preconcurrency import EventKit
  import Foundation

  struct MobileEventKitChangeObserver: Sendable {
    let onChanged: @Sendable () async -> Void

    func observe() async {
      let notifications = NotificationCenter.default.notifications(
        named: .EKEventStoreChanged
      )
      for await _ in notifications {
        await onChanged()
      }
    }
  }
#endif

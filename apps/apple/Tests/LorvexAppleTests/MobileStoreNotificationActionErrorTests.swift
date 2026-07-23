import Foundation
import LorvexCloudSync
import LorvexCore
import Testing

@testable import LorvexMobile

/// C-9: a failed notification action (Complete / Defer / Snooze from a
/// reminder's buttons) must reach the user. The iOS/visionOS app delegates post
/// `.lorvexNotificationActionError` on failure; `MobileStore` observes it and
/// routes the message into `errorMessage`, which drives the shell's alert.
///
/// Serialized because both tests drive the process-wide `NotificationCenter.default`
/// (the observer subscribes there): running them concurrently would let one
/// test's post land in the other's observer.
@Suite(.serialized)
@MainActor
struct MobileStoreNotificationActionErrorTests {
  @Test("surfaces a posted notification-action error as errorMessage")
  func surfacesNotificationActionError() async throws {
    let store = MobileStore(core: try await makeSeededInMemoryCore())
    let observer = Task { await store.observeNotificationActionErrors() }
    defer { observer.cancel() }

    let expected = "Complete failed: task not found"
    // The async notification stream subscribes only once iteration begins, so a
    // post can race ahead of the subscription; repost until it lands.
    for _ in 0..<200 where store.errorMessage == nil {
      NotificationCenter.default.post(
        name: .lorvexNotificationActionError,
        object: nil,
        userInfo: ["errorMessage": expected]
      )
      try? await Task.sleep(for: .milliseconds(5))
    }

    #expect(store.errorMessage == expected)
  }

  @Test("falls back to a generic message when the post carries none")
  func fallsBackWhenNotificationActionErrorHasNoMessage() async throws {
    let store = MobileStore(core: try await makeSeededInMemoryCore())
    let observer = Task { await store.observeNotificationActionErrors() }
    defer { observer.cancel() }

    for _ in 0..<200 where store.errorMessage == nil {
      NotificationCenter.default.post(
        name: .lorvexNotificationActionError,
        object: nil,
        userInfo: [:]
      )
      try? await Task.sleep(for: .milliseconds(5))
    }

    #expect(store.errorMessage?.isEmpty == false)
  }
}

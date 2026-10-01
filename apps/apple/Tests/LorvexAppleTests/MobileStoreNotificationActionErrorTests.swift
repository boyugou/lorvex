import Foundation
import LorvexCloudSync
import LorvexCore
import Testing

@testable import LorvexMobile

/// C-9: a failed notification action (Complete / Defer / Snooze from a
/// reminder's buttons) must reach the user. The iOS app delegate posts
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

  // C-9 durable path: a background notification action can fail at a cold launch
  // before any observer is live, so the post is dropped. The delegate records a
  // breadcrumb the store drains on the next foreground.
  @Test("consumes a recorded breadcrumb into errorMessage and clears it")
  func consumesPendingNotificationActionErrorBreadcrumb() async throws {
    let suiteName = "test.notifActionError.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let expected = "Defer failed: task not found"
    MobileNotificationActionErrorHandoff(defaults: defaults).record(message: expected)
    let store = MobileStore(core: try await makeSeededInMemoryCore(), defaults: defaults)

    await store.consumePendingNotificationActionError()

    #expect(store.errorMessage == expected)
    #expect(MobileNotificationActionErrorHandoff(defaults: defaults).hasPendingError == false)
  }

  @Test("drains a message-less breadcrumb to the generic fallback")
  func consumesMessagelessBreadcrumbWithFallback() async throws {
    let suiteName = "test.notifActionError.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    MobileNotificationActionErrorHandoff(defaults: defaults).record(message: nil)
    let store = MobileStore(core: try await makeSeededInMemoryCore(), defaults: defaults)

    await store.consumePendingNotificationActionError()

    #expect(store.errorMessage?.isEmpty == false)
    #expect(MobileNotificationActionErrorHandoff(defaults: defaults).hasPendingError == false)
  }

  @Test("does nothing when no breadcrumb is pending")
  func consumeIsNoOpWithoutPendingBreadcrumb() async throws {
    let suiteName = "test.notifActionError.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = MobileStore(core: try await makeSeededInMemoryCore(), defaults: defaults)
    await store.consumePendingNotificationActionError()

    #expect(store.errorMessage == nil)
  }
}

import Foundation
import LorvexCloudSync
import LorvexCore
import LorvexWorkflow
import Testing

@testable import LorvexMobile

/// C-9: a failed notification action (Complete / Defer / Snooze from a
/// reminder's buttons) must reach the user. The iOS app delegate classifies the
/// failure and posts `.lorvexNotificationActionError` with the classification;
/// `MobileStore` observes it and shows the classification's message in
/// `errorMessage`, which drives the shell's alert.
///
/// Serialized because both tests drive the process-wide `NotificationCenter.default`
/// (the observer subscribes there): running them concurrently would let one
/// test's post land in the other's observer.
@Suite(.serialized)
@MainActor
struct MobileStoreNotificationActionErrorTests {
  @Test("shows a posted failure's own sentence, never the core's English", arguments: [
    TaskLifecycleError.finishedTaskTransition(
      taskId: "0192f3a1-7c4b-7def-9abc-1234567890ab", from: .cancelled, to: .completed) as any Error,
    LorvexCoreError.taskNotFound as any Error,
  ])
  func surfacesNotificationActionError(failure: any Error) async throws {
    let store = MobileStore(core: try await makeSeededInMemoryCore())
    let observer = Task { await store.observeNotificationActionErrors() }
    defer { observer.cancel() }

    let classification = UserFacingError.classify(failure)
    let expected = UserFacingError.message(for: classification, copy: store.userFacingErrorCopy)
    // The async notification stream subscribes only once iteration begins, so a
    // post can race ahead of the subscription; repost until it lands.
    for _ in 0..<200 where store.errorMessage == nil {
      NotificationCenter.default.post(
        name: .lorvexNotificationActionError,
        object: nil,
        userInfo: [LorvexNotificationActionFailure.classificationKey: classification]
      )
      try? await Task.sleep(for: .milliseconds(5))
    }

    #expect(store.errorMessage == expected)
    let coreSentence = (failure as? LocalizedError)?.errorDescription
    #expect(store.errorMessage != coreSentence)
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

    let classification = UserFacingError.classify(
      TaskLifecycleError.startRequiresOpenTask(status: .completed))
    MobileNotificationActionErrorHandoff(defaults: defaults).record(classification)
    let store = MobileStore(core: try await makeSeededInMemoryCore(), defaults: defaults)

    await store.consumePendingNotificationActionError()

    #expect(store.errorMessage == UserFacingError.Reason.startingDoneTask.localizedMessage)
    #expect(MobileNotificationActionErrorHandoff(defaults: defaults).hasPendingError == false)
  }

  @Test("drains a message-less breadcrumb to the generic fallback")
  func consumesMessagelessBreadcrumbWithFallback() async throws {
    let suiteName = "test.notifActionError.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    MobileNotificationActionErrorHandoff(defaults: defaults).record(nil)
    let store = MobileStore(core: try await makeSeededInMemoryCore(), defaults: defaults)

    await store.consumePendingNotificationActionError()

    #expect(store.errorMessage?.isEmpty == false)
    #expect(MobileNotificationActionErrorHandoff(defaults: defaults).hasPendingError == false)
  }

  @Test("drains a breadcrumb that is not a classification to the generic fallback")
  func consumesUndecodableBreadcrumbWithFallback() async throws {
    let suiteName = "test.notifActionError.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    defaults.set("Complete failed", forKey: MobileNotificationActionErrorHandoff.pendingErrorKey)
    let handoff = MobileNotificationActionErrorHandoff(defaults: defaults)
    #expect(handoff.hasPendingError)
    #expect(handoff.pendingClassification == nil)
    let store = MobileStore(core: try await makeSeededInMemoryCore(), defaults: defaults)

    await store.consumePendingNotificationActionError()

    #expect(store.errorMessage?.isEmpty == false)
    #expect(store.errorMessage != "Complete failed")
    #expect(handoff.hasPendingError == false)
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

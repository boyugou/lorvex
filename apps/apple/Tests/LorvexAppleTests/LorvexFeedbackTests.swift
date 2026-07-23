import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

// MARK: - Recording provider

/// A `LorvexFeedbackProviding` implementation that records every `playFeedback`
/// call in order. Used by feedback integration tests to assert that store
/// actions emit the expected feedback events.
///
/// Recording is synchronous under a lock: the store calls `playFeedback`
/// synchronously inside its awaited `@MainActor` actions, so a `feedback.recorded`
/// read after `await store.someAction()` deterministically sees every emission —
/// no `Task.yield()` drain needed.
final class RecordingFeedbackProvider: LorvexFeedbackProviding {
  private let lock = NSLock()
  nonisolated(unsafe) private var _recorded: [LorvexFeedbackKind] = []

  var recorded: [LorvexFeedbackKind] {
    lock.lock()
    defer { lock.unlock() }
    return _recorded
  }

  nonisolated func playFeedback(_ kind: LorvexFeedbackKind) {
    lock.lock()
    defer { lock.unlock() }
    _recorded.append(kind)
  }
}

// MARK: - Helpers

/// A uniquely-named, freshly-cleared `UserDefaults` suite for one test.
///
/// `AppStore` persists and restores its navigation state (`selection`,
/// `selectedTaskID`) through the injected `UserDefaults`. Backing a test store
/// with `UserDefaults.standard` lets that state leak between parallel tests: a
/// store whose `init` runs `restorePersistedLaunchState()` while a concurrent
/// test has persisted `selection = .lists` restores that foreign selection, and
/// the mutation tail (`loadSelectedListDetail` → `pruneSelectedListTaskSelection`)
/// then clears `selectedTaskID` for any task not in the auto-selected list —
/// silently breaking a follow-up action that re-resolves the selected task.
/// An isolated suite keeps each store's navigation state its own.
private func makeIsolatedDefaults(_ label: String) -> (defaults: UserDefaults, suiteName: String) {
  let suiteName = "lorvexFeedbackTests.\(label).\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suiteName)!
  defaults.removePersistentDomain(forName: suiteName)
  return (defaults, suiteName)
}

@MainActor
private func makeStore(feedback: RecordingFeedbackProvider, defaults: UserDefaults) async throws -> AppStore {
  AppStore(
    core: try await makeSeededInMemoryCore(),
    feedbackProvider: feedback,
    defaults: defaults
  )
}

// MARK: - Tests

@MainActor
@Test
func noOpFeedbackProviderDoesNotCrash() {
  let provider = NoOpFeedbackProvider()
  provider.playFeedback(.taskCompleted)
  provider.playFeedback(.taskDeferred)
  provider.playFeedback(.habitCompleted)
  provider.playFeedback(.habitReset)
  provider.playFeedback(.captureSubmitted)
  // Expectation: no crash, nothing to assert.
}

@MainActor
@Test
func completeSelectedTaskEmitsTaskCompletedFeedback() async throws {
  let feedback = RecordingFeedbackProvider()
  let (defaults, suiteName) = makeIsolatedDefaults("completeFeedback")
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let store = try await makeStore(feedback: feedback, defaults: defaults)
  await store.refresh()

  guard let firstTask = store.today.tasks.first(where: { $0.status == .open }) else {
    Issue.record("No open tasks in preview data")
    return
  }
  store.selectedTaskID = firstTask.id
  await store.completeSelectedTask()

  #expect(feedback.recorded.contains(.taskCompleted))
}

@MainActor
@Test
func reopenSelectedTaskEmitsTaskReopenedFeedback() async throws {
  // Reopen mirrors complete: it plays a haptic and animates the row back into
  // the queue, so completing then reopening from the detail ⋯-menu feels
  // symmetric rather than silent.
  let feedback = RecordingFeedbackProvider()
  let (defaults, suiteName) = makeIsolatedDefaults("reopenFeedback")
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let store = try await makeStore(feedback: feedback, defaults: defaults)
  await store.refresh()

  guard let firstTask = store.today.tasks.first(where: { $0.status == .open }) else {
    Issue.record("No open tasks in preview data")
    return
  }
  store.selectedTaskID = firstTask.id
  await store.completeSelectedTask()
  // The completed task leaves the Today pool; reopen happens where it is
  // still listed — the task workspace.
  await store.loadTaskWorkspace()
  store.selectTaskFromList(firstTask.id)
  await store.reopenSelectedTask()

  #expect(feedback.recorded.contains(.taskReopened))
}

@MainActor
@Test
func createTaskEmitsCaptureSubmittedFeedback() async throws {
  let feedback = RecordingFeedbackProvider()
  let (defaults, suiteName) = makeIsolatedDefaults("createFeedback")
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let store = try await makeStore(feedback: feedback, defaults: defaults)

  await store.createTask(title: "Test capture", notes: "")

  #expect(feedback.recorded.contains(.captureSubmitted))
}

@MainActor
@Test
func feedbackKindIsDistinct() {
  let kinds: [LorvexFeedbackKind] = [
    .taskCompleted, .taskDeferred, .habitCompleted, .habitReset,
    .captureSubmitted,
  ]
  // All four cases are distinct (not equal to each other).
  for (i, a) in kinds.enumerated() {
    for (j, b) in kinds.enumerated() {
      if i == j {
        // Same case should produce the same string description.
        #expect(String(describing: a) == String(describing: b))
      } else {
        #expect(String(describing: a) != String(describing: b))
      }
    }
  }
}

@MainActor
@Test
func createDraftTaskEmitsCaptureSubmittedFeedback() async throws {
  let feedback = RecordingFeedbackProvider()
  let (defaults, suiteName) = makeIsolatedDefaults("createDraftFeedback")
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let store = try await makeStore(feedback: feedback, defaults: defaults)

  store.draftTitle = "Draft task feedback test"
  store.draftNotes = ""
  await store.createDraftTask()

  #expect(feedback.recorded.contains(.captureSubmitted))
}

@MainActor
@Test
func multipleActionsAccumulateFeedback() async throws {
  let feedback = RecordingFeedbackProvider()
  let (defaults, suiteName) = makeIsolatedDefaults("multipleActionsFeedback")
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let store = try await makeStore(feedback: feedback, defaults: defaults)
  await store.refresh()

  await store.createTask(title: "First capture", notes: "")

  guard let firstTask = store.today.tasks.first(where: { $0.status == .open }) else {
    Issue.record("No open tasks in preview data")
    return
  }
  store.selectedTaskID = firstTask.id
  await store.completeSelectedTask()

  #expect(feedback.recorded.contains(.captureSubmitted))
  #expect(feedback.recorded.contains(.taskCompleted))
}

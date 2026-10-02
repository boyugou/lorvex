import Foundation
import LorvexCore
import Testing

@testable import LorvexSystemIntents

// Siri and Shortcuts show a failed action's own error text, so every intent
// runner action throws a `LorvexIntentFailure`: worded like the app's alerts
// in the interface language, carrying the original classification, and logged
// when the person sees only generic copy.

@Test("a missing task reads as the shared not-found copy and is logged")
func intentRunnerRewordsAMissingTask() async throws {
  let core = try await makeSeededInMemoryCore()
  let missingID = "0192f3a1-7c4b-7def-9abc-1234567890ab"

  let failure = try await #require(throws: LorvexIntentFailure.self) {
    _ = try await LorvexTaskIntentRunner.completeTask(id: missingID, core: core)
  }

  #expect(failure.userFacingClassification.category == .notFound)
  #expect(failure.message == UserFacingError.Copy.standard.itemNoLongerExists)
  #expect(failure.errorDescription == failure.message)
  #expect(!failure.message.contains(missingID))
  #expect(UserFacingError.classify(failure) == failure.userFacingClassification)

  let logs = try await core.loadRecentLogs(
    limit: 50, offset: 0, since: nil, levels: nil, sources: nil, redact: false)
  let entry = try #require(logs.entries.first { $0.origin == "intent.action_failed" })
  #expect(entry.level == .error)
  #expect(entry.details == failure.userFacingClassification.technicalDetail)
}

@Test("a refused status change reads as its reason and is not logged")
func intentRunnerWordsARefusalAsItsReason() async throws {
  let core = try await makeSeededInMemoryCore()
  let task = try await core.createTask(title: "Already finished", notes: "")
  _ = try await core.completeTask(id: task.id)

  let failure = try await #require(throws: LorvexIntentFailure.self) {
    _ = try await LorvexTaskIntentRunner.startTask(id: task.id, core: core)
  }

  #expect(failure.userFacingClassification.reason == .startingDoneTask)
  #expect(failure.message == UserFacingError.Reason.startingDoneTask.localizedMessage)
  let logs = try await core.loadRecentLogs(
    limit: 50, offset: 0, since: nil, levels: nil, sources: nil, redact: false)
  #expect(!logs.entries.contains { $0.origin == "intent.action_failed" })
}

@Test("an entity query rewords its failure too")
func entityQueryRewordsItsFailure() async throws {
  let core = try await makeSeededInMemoryCore()
  let failure = try await #require(throws: LorvexIntentFailure.self) {
    try await LorvexIntentFailure.rewording(core: core) {
      try await LorvexTaskEntityQuery.entity(id: "0192f3a1-7c4b-7def-9abc-1234567890ab", core: core)
    }
  }
  #expect(failure.message == UserFacingError.Copy.standard.itemNoLongerExists)
}

@Test("cancellation and an already reworded failure pass through unchanged")
func rewordingPassesCancellationAndRewordedFailuresThrough() async throws {
  let core = try makeInMemoryCore()
  await #expect(throws: CancellationError.self) {
    try await LorvexIntentFailure.rewording(core: core) { () async throws -> Int in
      throw CancellationError()
    }
  }

  let original = LorvexIntentFailure(LorvexCoreError.taskNotFound)
  let rethrown = try await #require(throws: LorvexIntentFailure.self) {
    try await LorvexIntentFailure.rewording(core: core) { () async throws -> Int in
      throw original
    }
  }
  #expect(rethrown.userFacingClassification == original.userFacingClassification)
  #expect(LorvexIntentFailure(original).userFacingClassification == original.userFacingClassification)

  // Neither path reached the generic-failure log a second time.
  let logs = try await core.loadRecentLogs(
    limit: 50, offset: 0, since: nil, levels: nil, sources: nil, redact: false)
  #expect(!logs.entries.contains { $0.origin == "intent.action_failed" })
}

import Foundation
import Synchronization
import Testing

@testable import LorvexCore
@testable import LorvexSystemIntents

// A connection that was open when the app last left the foreground stays
// suspended until someone resumes it, and the system runs App Intents and
// notification actions in a backgrounded process. Work that writes in such a
// process takes the store back through `DatabaseSuspension.withBackgroundAccess`
// and gives it up when it is done. These tests watch the bracket through its
// own calls and never post the process-wide suspend notification, which would
// suspend the connections of every test running beside them.

private struct BracketTestError: Error {}

/// The calls a bracket makes, in order.
private final class BracketLog: Sendable {
  private let storage = Mutex<[String]>([])

  var events: [String] { storage.withLock { $0 } }

  func record(_ event: String) {
    storage.withLock { $0.append(event) }
  }

  /// An access whose two calls log themselves.
  var access: DatabaseSuspension.BackgroundAccess {
    DatabaseSuspension.BackgroundAccess(
      begin: { self.record("begin") },
      end: { self.record("end") })
  }
}

/// Lets the installed access, which every test in the process shares, log only
/// for the one test that binds a log.
private enum InstalledAccessProbe {
  @TaskLocal static var log: BracketLog?
}

@Test("the bracket resumes before the work, suspends after it, and returns its value")
func bracketOrdersBeginWorkEnd() async {
  let log = BracketLog()
  let value = await DatabaseSuspension.withBackgroundAccess(log.access) { () async -> Int in
    log.record("work")
    return 42
  }
  #expect(value == 42)
  #expect(log.events == ["begin", "work", "end"])
}

@Test("the bracket ends when the work throws and rethrows the same error")
func bracketEndsWhenTheWorkThrows() async {
  let log = BracketLog()
  await #expect(throws: BracketTestError.self) {
    try await DatabaseSuspension.withBackgroundAccess(log.access) { () async throws -> Int in
      log.record("work")
      throw BracketTestError()
    }
  }
  #expect(log.events == ["begin", "work", "end"])
}

@Test("nested brackets each begin and end, the outer one around the inner")
func nestedBracketsBalance() async {
  let log = BracketLog()
  await DatabaseSuspension.withBackgroundAccess(log.access) {
    await DatabaseSuspension.withBackgroundAccess(log.access) {
      log.record("work")
    }
  }
  #expect(log.events == ["begin", "begin", "work", "end", "end"])
}

@Test("without an access the work runs unchanged")
func bracketWithoutAnAccessRunsTheWork() async throws {
  let value = await DatabaseSuspension.withBackgroundAccess(nil) { () async -> String in "ran" }
  #expect(value == "ran")
  await #expect(throws: BracketTestError.self) {
    try await DatabaseSuspension.withBackgroundAccess(nil) { () async throws -> Int in
      throw BracketTestError()
    }
  }
}

@Test("the installed access brackets work that binds no other")
func installedAccessBracketsTheWork() async {
  let log = BracketLog()
  DatabaseSuspension.installBackgroundAccess(
    DatabaseSuspension.BackgroundAccess(
      begin: { InstalledAccessProbe.log?.record("begin") },
      end: { InstalledAccessProbe.log?.record("end") }))
  defer { DatabaseSuspension.installBackgroundAccess(nil) }
  await InstalledAccessProbe.$log.withValue(log) {
    await DatabaseSuspension.withBackgroundAccess { log.record("work") }
  }
  #expect(log.events == ["begin", "work", "end"])
}

@Test("an App Intent's failure is logged before the store is given up")
func intentFailureIsLoggedInsideTheBracket() async throws {
  let core = try makeInMemoryCore()
  let log = BracketLog()
  let access = DatabaseSuspension.BackgroundAccess(
    begin: { log.record("begin") },
    end: {
      // The diagnostics write is a database write, so it has to land while the
      // store is still taken back.
      let logs = try? await core.loadRecentLogs(
        limit: 50, offset: 0, since: nil, levels: nil, sources: nil, redact: false)
      let logged = logs?.entries.contains { $0.origin == "intent.action_failed" } ?? false
      log.record(logged ? "end after the failure was logged" : "end before the failure was logged")
    })

  await DatabaseSuspension.$backgroundAccessOverride.withValue(access) {
    await #expect(throws: LorvexIntentFailure.self) {
      try await LorvexIntentFailure.rewording(core: core) { () async throws -> Int in
        log.record("work")
        throw LorvexCoreError.taskNotFound
      }
    }
  }
  #expect(log.events == ["begin", "work", "end after the failure was logged"])
}

@Test("an App Intent's success and cancellation run inside the bracket too")
func intentSuccessAndCancellationRunInsideTheBracket() async throws {
  let core = try makeInMemoryCore()

  let succeeded = BracketLog()
  let value = await DatabaseSuspension.$backgroundAccessOverride.withValue(succeeded.access) {
    try? await LorvexIntentFailure.rewording(core: core) { () async throws -> Int in
      succeeded.record("work")
      return 7
    }
  }
  #expect(value == 7)
  #expect(succeeded.events == ["begin", "work", "end"])

  let cancelled = BracketLog()
  await DatabaseSuspension.$backgroundAccessOverride.withValue(cancelled.access) {
    await #expect(throws: CancellationError.self) {
      try await LorvexIntentFailure.rewording(core: core) { () async throws -> Int in
        cancelled.record("work")
        throw CancellationError()
      }
    }
  }
  #expect(cancelled.events == ["begin", "work", "end"])
}

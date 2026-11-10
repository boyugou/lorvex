import Foundation
import Synchronization
import Testing

@testable import LorvexCore
@testable import LorvexSystemIntents

// A Shortcuts automation stores the tasks it was given as identifiers, and the
// system resolves them through `entities(for:)` when it runs, possibly in a
// backgrounded process whose store connection is still suspended. Like every
// other entity query, the lookup has to take the store back for its length;
// an identifier whose task no longer exists is left out of the result.

/// The calls a background-access bracket makes, in order.
private final class AccessLog: Sendable {
  private let storage = Mutex<[String]>([])

  var events: [String] { storage.withLock { $0 } }

  var access: DatabaseSuspension.BackgroundAccess {
    DatabaseSuspension.BackgroundAccess(
      begin: { self.storage.withLock { $0.append("begin") } },
      end: { self.storage.withLock { $0.append("end") } })
  }
}

private let deletedTaskID = "0192f3a1-7c4b-7def-9abc-1234567890ab"

@Suite("Task entity queries resolve saved identifiers")
struct TaskEntityQueryResolutionTests {
  @Test("a saved task resolves inside the background-access bracket and a missing one is left out")
  func taskEntitiesForIdentifiersTakeBackgroundAccess() async throws {
    try await withIsolatedAppIntentDatabase {
      let core = LorvexCoreRuntimeFactory.makeForAppIntent()
      let kept = try await core.createTask(title: "Saved in a shortcut", notes: "")
      let other = try await core.createTask(title: "Saved beside it", notes: "")
      let log = AccessLog()

      let entities = try await DatabaseSuspension.$backgroundAccessOverride.withValue(log.access) {
        try await LorvexTaskEntityQuery().entities(for: [other.id, deletedTaskID, kept.id])
      }

      #expect(entities.map(\.id) == [other.id, kept.id])
      #expect(entities.map(\.title) == ["Saved beside it", "Saved in a shortcut"])
      #expect(log.events == ["begin", "end"])
    }
  }

  @Test("a closed task resolves for Reopen inside the bracket and a missing one is left out")
  func reopenableTaskEntitiesForIdentifiersTakeBackgroundAccess() async throws {
    try await withIsolatedAppIntentDatabase {
      let core = LorvexCoreRuntimeFactory.makeForAppIntent()
      let task = try await core.createTask(title: "Finished in a shortcut", notes: "")
      _ = try await core.completeTask(id: task.id)
      let log = AccessLog()

      let entities = try await DatabaseSuspension.$backgroundAccessOverride.withValue(log.access) {
        try await LorvexReopenableTaskEntityQuery().entities(for: [deletedTaskID, task.id])
      }

      #expect(entities.map(\.id) == [task.id])
      #expect(entities.map(\.status) == ["completed"])
      #expect(log.events == ["begin", "end"])
    }
  }

  @Test("a missing identifier is not a failure and writes no diagnostics entry")
  func aMissingIdentifierFailsNothing() async throws {
    try await withIsolatedAppIntentDatabase {
      let core = LorvexCoreRuntimeFactory.makeForAppIntent()

      let entities = try await LorvexTaskEntityQuery().entities(for: [deletedTaskID])
      let reopenable = try await LorvexReopenableTaskEntityQuery().entities(for: [deletedTaskID])

      #expect(entities.isEmpty)
      #expect(reopenable.isEmpty)
      let logs = try await core.loadRecentLogs(
        limit: 50, offset: 0, since: nil, levels: nil, sources: nil, redact: false)
      #expect(!logs.entries.contains { $0.origin == "intent.action_failed" })
    }
  }
}

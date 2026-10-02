import Foundation
import LorvexDomain
import LorvexStore
import LorvexWorkflow
import Testing

@testable import LorvexCore

/// Service-level contract for the `in_progress` lifecycle: `startTask` /
/// `pauseTask` happy paths, idempotency, the dependency-blocked start, the
/// list-filter, and that completing a started recurring task still spawns an
/// `open` successor. Runs on `SwiftLorvexCoreService` over an in-memory GRDB
/// store seeded with the canonical `schema/schema.sql`.
@Suite("Core service in_progress")
struct SwiftLorvexCoreServiceInProgressTests {
  private func makeService() throws -> any LorvexCoreServicing {
    let schemaURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent("schema/schema.sql")
    let schema = try String(contentsOf: schemaURL, encoding: .utf8)
    return SwiftLorvexCoreService(store: try LorvexStore.openInMemory(
      schemaSQL: schema, migrations: try SwiftLorvexCoreService.resolveSchemaMigrations()))
  }

  @Test("startTask marks an open task in_progress")
  func startHappyPath() async throws {
    let service = try makeService()
    let task = try await service.createTask(title: "Write report", notes: "")
    _ = try await service.startTask(id: task.id)
    #expect(try await service.loadTask(id: task.id).status == .inProgress)
  }

  @Test("startTask is idempotent on an already-started task")
  func startIdempotent() async throws {
    let service = try makeService()
    let task = try await service.createTask(title: "Write report", notes: "")
    _ = try await service.startTask(id: task.id)
    _ = try await service.startTask(id: task.id)
    #expect(try await service.loadTask(id: task.id).status == .inProgress)
  }

  @Test("startTask rejects a resolved or parked task (reopen first)")
  func startRejectsCompleted() async throws {
    let service = try makeService()
    let done = try await service.createTask(title: "Done thing", notes: "")
    _ = try await service.completeTask(id: done.id)
    await #expect(throws: TaskLifecycleError.startRequiresOpenTask(status: .completed)) {
      _ = try await service.startTask(id: done.id)
    }

    let parked = try await service.createTask(title: "Parked thing", notes: "")
    _ = try await service.markTaskSomeday(id: parked.id)
    await #expect(throws: TaskLifecycleError.startRequiresOpenTask(status: .someday)) {
      _ = try await service.startTask(id: parked.id)
    }
  }

  @Test("pauseTask rejects a task that is not in progress")
  func pauseRejectsResolved() async throws {
    let service = try makeService()
    let task = try await service.createTask(title: "Done thing", notes: "")
    _ = try await service.completeTask(id: task.id)
    await #expect(throws: TaskLifecycleError.pauseRequiresStartedTask(status: .completed)) {
      _ = try await service.pauseTask(id: task.id)
    }
  }

  @Test("completing a canceled task and canceling a completed one ask for a reopen")
  func finishedTaskTransitionsAreTyped() async throws {
    let service = try makeService()
    let canceled = try await service.createTask(title: "Dropped", notes: "")
    _ = try await service.cancelTask(id: canceled.id)
    await #expect(
      throws: TaskLifecycleError.finishedTaskTransition(
        taskId: canceled.id, from: .cancelled, to: .completed)
    ) {
      _ = try await service.completeTask(id: canceled.id)
    }

    let done = try await service.createTask(title: "Finished", notes: "")
    _ = try await service.completeTask(id: done.id)
    await #expect(
      throws: TaskLifecycleError.finishedTaskTransition(
        taskId: done.id, from: .completed, to: .cancelled)
    ) {
      _ = try await service.cancelTask(id: done.id)
    }
  }

  @Test("pauseTask returns a started task to open")
  func pauseHappyPath() async throws {
    let service = try makeService()
    let task = try await service.createTask(title: "Write report", notes: "")
    _ = try await service.startTask(id: task.id)
    _ = try await service.pauseTask(id: task.id)
    #expect(try await service.loadTask(id: task.id).status == .open)
  }

  @Test("pauseTask is a no-op on an already-open task")
  func pauseIdempotentFromOpen() async throws {
    let service = try makeService()
    let task = try await service.createTask(title: "Not started", notes: "")
    _ = try await service.pauseTask(id: task.id)
    #expect(try await service.loadTask(id: task.id).status == .open)
  }

  @Test("startTask is rejected when a dependency is unfinished, allowed once it is done")
  func dependencyBlockedStart() async throws {
    let service = try makeService()
    let blocker = try await service.createTask(title: "Blocker", notes: "")
    let dependent = try await service.createTask(
      TaskCreateDraft(title: "Dependent", dependsOn: [blocker.id]))

    await #expect(throws: (any Error).self) {
      _ = try await service.startTask(id: dependent.id)
    }
    #expect(try await service.loadTask(id: dependent.id).status == .open)

    _ = try await service.completeTask(id: blocker.id)
    _ = try await service.startTask(id: dependent.id)
    #expect(try await service.loadTask(id: dependent.id).status == .inProgress)
  }

  @Test("in_progress is included by the list filter and distinct from open")
  func listFilterInProgress() async throws {
    let service = try makeService()
    let marker = "wip-\(UUID().uuidString.prefix(8))"
    let started = try await service.createTask(title: "Started \(marker)", notes: "")
    let open = try await service.createTask(title: "Open \(marker)", notes: "")
    _ = try await service.startTask(id: started.id)

    let inProgress = try await service.listTasks(
      status: "in_progress", listID: nil, priority: nil, text: marker, limit: 50, offset: 0)
    #expect(inProgress.tasks.map(\.id).contains(started.id))
    #expect(!inProgress.tasks.map(\.id).contains(open.id))

    let openLane = try await service.listTasks(
      status: "open", listID: nil, priority: nil, text: marker, limit: 50, offset: 0)
    #expect(!openLane.tasks.map(\.id).contains(started.id))
    #expect(openLane.tasks.map(\.id).contains(open.id))
  }

  @Test("completing a started recurring task spawns an open successor")
  func recurringSuccessorIsOpen() async throws {
    let service = try makeService()
    let marker = "rec-\(UUID().uuidString.prefix(8))"
    let task = try await service.createTask(title: "Water plants \(marker)", notes: "")
    _ = try await service.setTaskRecurrence(
      taskID: task.id, rule: TaskRecurrenceRule(freq: .daily, interval: 1))
    _ = try await service.startTask(id: task.id)
    _ = try await service.completeTaskReturningTask(id: task.id)

    let successors = try await service.listTasks(
      status: "open", listID: nil, priority: nil, text: marker, limit: 50, offset: 0)
    let successor = try #require(successors.tasks.first { $0.id != task.id })
    #expect(successor.status == .open)
  }
}

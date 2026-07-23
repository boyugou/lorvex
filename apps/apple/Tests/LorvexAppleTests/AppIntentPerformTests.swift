import AppIntents
import Foundation
import LorvexCore
import LorvexSystemIntents
import Testing
import UniformTypeIdentifiers

@testable import LorvexApple
@testable import LorvexSystemIntents

// MARK: - CaptureLorvexTaskIntent

@Test
func captureIntentRunnerCreatesTaskForValidTitle() async throws {
  // Focused unit check of the runner with a directly injected in-memory core
  // (matching `completeIntentRunnerSetsTaskStatusToCompleted`). The real
  // `intent.perform()` success path is exercised separately and hermetically in
  // `captureIntentPerformCreatesTaskInHermeticDatabase`.
  let core = try await makeSeededInMemoryCore()
  let title = try await LorvexTaskIntentRunner.captureTask(
    title: "Intent test task",
    notes: "From perform path.",
    core: core
  )
  #expect(title == "Intent test task")

  let today = try await core.loadToday()
  #expect(today.tasks.contains { $0.title == "Intent test task" })
}

@Test
func captureIntentPerformThrowsOnBlankTitle() async throws {
  let intent = CaptureLorvexTaskIntent(title: "   ")
  await #expect(throws: LorvexCoreError.self) {
    _ = try await intent.perform()
  }
}

@Test
func captureIntentPerformCreatesTaskInHermeticDatabase() async throws {
  // Exercise the real `intent.perform()` path — which resolves its core through
  // `LorvexCoreRuntimeFactory.makeForAppIntent()` and has no dependency-injection
  // seam — hermetically. Binding the `@TaskLocal databaseOverride` to a
  // per-test temp path (mirroring `LorvexCoreRuntimeFactoryTests`) gives perform()
  // its own on-disk database, so it never races the process-global default
  // location against other perform tests.
  let tmp = NSTemporaryDirectory() + "lorvex-appintent-perform-\(UUID().uuidString).db"
  defer { try? FileManager.default.removeItem(atPath: tmp) }

  let intent = CaptureLorvexTaskIntent(title: "Perform-path task", notes: "Real perform.")
  try await LorvexCoreRuntimeFactory.$databaseOverride.withValue(tmp) {
    _ = try await intent.perform()
  }

  // A fresh reader on the same on-disk database sees the created task, proving
  // perform() ran against the bound temp DB rather than the default location.
  let reader = SwiftLorvexCoreService(databasePath: tmp)
  let today = try await reader.loadToday()
  #expect(today.tasks.contains { $0.title == "Perform-path task" })
}

// MARK: - Returning-value task intents (read / list / capture)

// The read/list/capture system intents return a `LorvexTaskEntity` value
// alongside their dialog so a Shortcut can chain on the result (matching the
// export intents' rich-return posture). These checks cover the intent-runner
// seam that feeds those returns and the entity mapping the intents apply, plus
// a source-level assertion that each intent declares the `ReturnsValue`
// contract.

@Test
func captureIntentReturnsCreatedTaskEntity() async throws {
  // The capture intent builds its `LorvexTaskEntity` return from
  // `captureTaskReturningTask`'s real task; the title-only `captureTask` echoes
  // the same task's title, so both stay in agreement.
  let core = try await makeSeededInMemoryCore()
  let task = try await LorvexTaskIntentRunner.captureTaskReturningTask(
    title: "  Chainable capture  ",
    notes: "From returning intent.",
    core: core
  )
  #expect(task.title == "Chainable capture")

  let entity = LorvexTaskEntity(task: task)
  #expect(entity.id == task.id)
  #expect(entity.title == "Chainable capture")
  #expect(entity.status == task.status.rawValue)

  let titleOnly = try await LorvexTaskIntentRunner.captureTask(
    title: "  Chainable capture  ", notes: nil, core: core)
  #expect(titleOnly == "Chainable capture")
}

@Test
func readIntentReturnsLoadedTaskEntity() async throws {
  let core = try await makeSeededInMemoryCore()
  let created = try await core.createTask(title: "Readable task", notes: "")
  let loaded = try await LorvexTaskIntentRunner.readTask(id: " \(created.id) ", core: core)

  let entity = LorvexTaskEntity(task: loaded)
  #expect(entity.id == created.id)
  #expect(entity.title == "Readable task")
  #expect(entity.status == loaded.status.rawValue)
}

@Test
func listIntentReturnsMatchingTaskEntities() async throws {
  let core = try await makeSeededInMemoryCore()
  let created = try await core.createTask(title: "Listable task", notes: "")
  let result = try await LorvexTaskIntentRunner.listTasks(
    status: "open", listID: nil, priority: nil, text: "Listable", limit: 10, core: core)

  let entities = result.tasks.map(LorvexTaskEntity.init(task:))
  #expect(entities.map(\.id).contains(created.id))
  #expect(entities.first { $0.id == created.id }?.title == "Listable task")
}

@Test
func readListCaptureIntentsDeclareEntityReturnValue() throws {
  let intents = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // LorvexAppleTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // apple
    .appending(path: "Sources/LorvexSystemIntents")
  let capture = try String(
    contentsOf: intents.appending(path: "CaptureLorvexTaskIntent.swift"), encoding: .utf8)
  let read = try String(
    contentsOf: intents.appending(path: "ReadLorvexTaskIntent.swift"), encoding: .utf8)
  let list = try String(
    contentsOf: intents.appending(path: "ListLorvexTasksIntent.swift"), encoding: .utf8)

  #expect(capture.contains("ReturnsValue<LorvexTaskEntity>"))
  #expect(capture.contains("value: LorvexTaskEntity(task: task)"))
  #expect(read.contains("ReturnsValue<LorvexTaskEntity>"))
  #expect(read.contains("value: LorvexTaskEntity(task: loaded)"))
  #expect(list.contains("ReturnsValue<[LorvexTaskEntity]>"))
  #expect(list.contains("value: result.tasks.map(LorvexTaskEntity.init(task:))"))
}

@Test
func searchAndReadTaskListIntentsDeclareEntityReturnValue() throws {
  // The search / upcoming / deferred / by-tag read intents return their matching
  // tasks as `[LorvexTaskEntity]` alongside the dialog, so a Shortcut can chain on
  // the results (e.g. complete each). Assert each declares the `ReturnsValue`
  // contract and maps the runner's tasks to entities.
  let intents = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // LorvexAppleTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // apple
    .appending(path: "Sources/LorvexSystemIntents")
  func source(_ name: String) throws -> String {
    try String(contentsOf: intents.appending(path: name), encoding: .utf8)
  }
  let search = try source("SearchLorvexTasksIntent.swift")
  let upcoming = try source("ReadLorvexUpcomingTasksIntent.swift")
  let deferred = try source("ReadLorvexDeferredTasksIntent.swift")
  let byTag = try source("FindLorvexTasksByTagIntent.swift")

  for src in [search, upcoming, deferred, byTag] {
    #expect(src.contains("ReturnsValue<[LorvexTaskEntity]>"))
  }
  #expect(search.contains("value: result.tasks.map(LorvexTaskEntity.init(task:))"))
  #expect(upcoming.contains("value: tasks.map(LorvexTaskEntity.init(task:))"))
  #expect(deferred.contains("value: result.tasks.map(LorvexTaskEntity.init(task:))"))
  #expect(byTag.contains("value: tasks.map(LorvexTaskEntity.init(task:))"))
}

@Test
func taskStatusLabelIsLocalizedNotRawWireEnum() {
  // The task entity picker subtitles render the status through the shared
  // status-filter labels, so a Shortcut shows "Open", not the raw wire enum
  // "open". Each known status resolves to its localized label; an unrecognized
  // value falls back to the raw string.
  #expect(String(localized: LorvexTaskStatusOption.localizedLabel(forRawStatus: "open")) == "Open")
  #expect(
    String(localized: LorvexTaskStatusOption.localizedLabel(forRawStatus: "completed")) == "Completed")
  #expect(
    String(localized: LorvexTaskStatusOption.localizedLabel(forRawStatus: "cancelled")) == "Cancelled")
  #expect(
    String(localized: LorvexTaskStatusOption.localizedLabel(forRawStatus: "someday")) == "Someday")
  #expect(String(localized: LorvexTaskStatusOption.localizedLabel(forRawStatus: "weird")) == "weird")
}

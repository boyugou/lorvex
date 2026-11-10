import Foundation
import LorvexCore
import Testing

@testable import LorvexApple
@testable import LorvexMobile

/// Pins the person's half of handing a task to the assistant on both stores:
/// Hand to Assistant and Take Back write through the core and every copy of
/// the task the store holds takes the result, while a refused write shows its
/// error and leaves every copy as it was.
@Suite("Task hand-off store actions")
@MainActor
struct TaskDelegationStoreActionTests {
  private static let refusal = LorvexCoreError.validation(
    field: "id", message: "Only a task that is still open can be handed to the assistant.")

  // MARK: Mac

  /// A seeded Mac store with Today and the Tasks workspace loaded and an open
  /// task present in both selected in the inspector.
  private func macStore() async throws -> (StubCoreService, AppStore, LorvexTask.ID) {
    let core = StubCoreService(preview: try await makeSeededInMemoryCore())
    let store = AppStore(core: core)
    await store.refresh()
    await store.loadTaskWorkspace()
    let workspaceIDs = Set(store.taskWorkspaceOpenTasks.map(\.id))
    let task = try #require(
      store.today.tasks.first { $0.status == .open && workspaceIDs.contains($0.id) })
    store.selectTaskFromList(task.id)
    return (core, store, task.id)
  }

  /// The task's hand-off state in each copy the Mac store holds: Today's row,
  /// the Tasks workspace row, and the inspector's task.
  private func macCopies(_ store: AppStore, _ id: LorvexTask.ID) -> [LorvexTaskDelegation.State?] {
    [
      store.today.tasks.first { $0.id == id }?.delegation?.state,
      store.taskWorkspaceOpenTasks.first { $0.id == id }?.delegation?.state,
      store.selectedTask?.delegation?.state,
    ]
  }

  @Test("Mac: Hand to Assistant, then Take Back, reach every loaded copy of the task")
  func macHandsOverAndTakesBack() async throws {
    let (core, store, id) = try await macStore()
    #expect(macCopies(store, id) == [nil, nil, nil])

    await store.performDelegationAction(.handToAssistant, taskID: id)
    #expect(store.errorMessage == nil)
    #expect(macCopies(store, id) == [.assistant, .assistant, .assistant])
    #expect(try await core.loadTask(id: id).delegation?.state == .assistant)
    #expect(store.selectedTaskID == id)

    await store.performDelegationAction(.takeBack, taskID: id)
    #expect(store.errorMessage == nil)
    #expect(macCopies(store, id) == [nil, nil, nil])
    #expect(try await core.loadTask(id: id).delegation == nil)
  }

  @Test("Mac: Take Back clears a task the assistant handed back")
  func macTakesBackAReturnedTask() async throws {
    let (core, store, id) = try await macStore()
    _ = try await core.delegateTask(id: id, request: nil)
    _ = try await core.returnDelegatedTask(id: id, result: "Drafted the reply.")
    await store.refresh()
    #expect(store.today.tasks.first { $0.id == id }?.delegation?.state == .returned)

    await store.performDelegationAction(.takeBack, taskID: id)
    #expect(store.today.tasks.first { $0.id == id }?.delegation == nil)
    // The reply stays in the task's notes from the assistant.
    #expect(try await core.loadTask(id: id).aiNotes == "Drafted the reply.")
  }

  @Test("Mac: a refused hand-over shows the error and leaves the task as it was")
  func macRefusedHandOverChangesNothing() async throws {
    let (core, store, id) = try await macStore()
    core.taskDelegationError = Self.refusal

    await store.performDelegationAction(.handToAssistant, taskID: id)
    #expect(store.errorMessage != nil)
    #expect(macCopies(store, id) == [nil, nil, nil])
    #expect(try await core.loadTask(id: id).delegation == nil)
  }

  @Test("Mac: a refused take-back shows the error and keeps the task with the assistant")
  func macRefusedTakeBackChangesNothing() async throws {
    let (core, store, id) = try await macStore()
    await store.performDelegationAction(.handToAssistant, taskID: id)
    core.taskDelegationError = Self.refusal

    await store.performDelegationAction(.takeBack, taskID: id)
    #expect(store.errorMessage != nil)
    #expect(macCopies(store, id) == [.assistant, .assistant, .assistant])
    #expect(try await core.loadTask(id: id).delegation?.state == .assistant)
  }

  // MARK: iPhone and iPad

  /// A seeded mobile store with Today loaded, and an open task on it.
  private func mobileStore() async throws -> (StubCoreService, MobileStore, LorvexTask.ID) {
    let core = StubCoreService(preview: try await makeSeededInMemoryCore())
    let store = MobileStore(core: core, todayString: { "2026-05-23" })
    await store.refresh()
    let task = try #require(store.snapshot.today.tasks.first { $0.status == .open })
    return (core, store, task.id)
  }

  /// The task's hand-off state in each copy the mobile store holds: Today's
  /// row, the task cache a detail page and the list pages read, and the task
  /// a route resolves.
  private func mobileCopies(_ store: MobileStore, _ id: LorvexTask.ID) -> [LorvexTaskDelegation.State?] {
    [
      store.snapshot.today.tasks.first { $0.id == id }?.delegation?.state,
      store.taskCache[id]?.delegation?.state,
      store.resolveTask(id)?.delegation?.state,
    ]
  }

  @Test("iPhone: the row actions hand the task over and take it back, in every copy")
  func mobileHandsOverAndTakesBack() async throws {
    let (core, store, id) = try await mobileStore()
    let actions = store.rowActions(for: id)

    await actions.delegate(.handToAssistant)
    #expect(store.errorMessage == nil)
    #expect(mobileCopies(store, id) == [.assistant, .assistant, .assistant])
    #expect(try await core.loadTask(id: id).delegation?.state == .assistant)

    await actions.delegate(.takeBack)
    #expect(store.errorMessage == nil)
    #expect(mobileCopies(store, id) == [nil, nil, nil])
    #expect(try await core.loadTask(id: id).delegation == nil)
  }

  @Test("iPhone: a refused hand-over shows the error and leaves the task as it was")
  func mobileRefusedHandOverChangesNothing() async throws {
    let (core, store, id) = try await mobileStore()
    core.taskDelegationError = Self.refusal

    let handed = await store.performDelegationAction(.handToAssistant, taskID: id)
    #expect(!handed)
    #expect(store.errorMessage != nil)
    #expect(store.snapshot.today.tasks.first { $0.id == id }?.delegation == nil)
    #expect(store.resolveTask(id)?.delegation == nil)
    #expect(try await core.loadTask(id: id).delegation == nil)
  }

  @Test("iPhone: a refused take-back shows the error and keeps the task with the assistant")
  func mobileRefusedTakeBackChangesNothing() async throws {
    let (core, store, id) = try await mobileStore()
    #expect(await store.performDelegationAction(.handToAssistant, taskID: id))
    core.taskDelegationError = Self.refusal

    let tookBack = await store.performDelegationAction(.takeBack, taskID: id)
    #expect(!tookBack)
    #expect(store.errorMessage != nil)
    #expect(mobileCopies(store, id) == [.assistant, .assistant, .assistant])
    #expect(try await core.loadTask(id: id).delegation?.state == .assistant)
  }
}

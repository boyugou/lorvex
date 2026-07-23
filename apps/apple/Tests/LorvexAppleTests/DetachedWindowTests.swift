import Foundation
import SwiftUI
import Testing

@testable import LorvexApple
@testable import LorvexCloudSync
@testable import LorvexCore

@MainActor
@Test
func detachedTaskWindowStateDoesNotRetargetMainSelection() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.refresh()
  let original = store.selectedTaskID
  let target: LorvexTask.ID = LorvexPreviewSeedID.agendaTask

  let detachedStore = store.makeDetachedWindowStore()
  await detachedStore.loadDetachedTaskWindow(taskID: target)

  #expect(detachedStore.selectedTaskID == target)
  #expect(store.selectedTaskID == original)
}

@MainActor
@Test
func detachedWindowStorePreservesInjectedClock() async throws {
  let referenceNow = Date(timeIntervalSince1970: 1_779_649_200)
  let store = AppStore(core: try await makeSeededInMemoryCore(), now: { referenceNow })

  let detachedStore = store.makeDetachedWindowStore()

  #expect(detachedStore.now() == referenceNow)
}

@MainActor
@Test
func detachedWindowKeepsCloudKitOffButSharesTheParentsMaintenanceGate() async throws {
  let coordinator = CloudSyncEngineCoordinator(
    accountChecker: StubAccountStatusChecker(),
    pusher: RecordingRecordPusher(),
    fetcher: StubRemoteChangeFetcher(records: []),
    accountIdentifier: StubAccountIdentifier(identifier: "account-A"),
    accountIdentityStore: RecordingAccountIdentityStore(initial: "account-A"),
    accountPauseStore: RecordingCloudSyncPauseStore())
  let parent = AppStore(
    core: try await makeSeededInMemoryCore(),
    cloudSyncMode: .live,
    cloudSyncCoordinator: coordinator,
    cloudDataMaintenanceCoordinator: coordinator)

  let detached = parent.makeDetachedWindowStore()

  #expect(detached.cloudSyncMode == .off)
  #expect(detached.cloudSyncCoordinator == nil)
  #expect(
    detached.shouldIncludeActiveOutboxCap == false,
    "a coordinator-less window must inherit the live app's no-shedding policy")
  let detachedMaintenance = try #require(detached.cloudDataMaintenanceCoordinator)
  #expect(detachedMaintenance.operationGate === coordinator.operationGate)

  parent.cloudSyncMode = .off
  #expect(
    detached.shouldIncludeActiveOutboxCap,
    "the inherited retention policy must follow runtime sync-mode changes")
}

@MainActor
@Test
func detachedListWindowStateDoesNotRetargetMainSelection() async throws {
  let suiteName = "detachedListWindowStateDoesNotRetargetMainSelection.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suiteName)!
  defaults.removePersistentDomain(forName: suiteName)
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let store = AppStore(core: try await makeSeededInMemoryCore(), defaults: defaults)
  await store.refresh()

  let target: LorvexList.ID = LorvexPreviewSeedID.appleNativeList
  let original = store.selectedListID
  let detachedStore = store.makeDetachedWindowStore()
  await detachedStore.loadDetachedListWindow(listID: target)

  #expect(detachedStore.selectedListID == target)
  #expect(store.selectedListID == original)
}

@MainActor
@Test
func detachedWindowPlaceholderRenders() {
  let placeholder = DetachedWindowPlaceholder(systemImage: "tray", title: "Empty")
  #expect(placeholder.systemImage == "tray")
  #expect(placeholder.title == "Empty")
}

private actor DetachedTaskReadGate {
  private var entered = false
  private var released = false
  private var enteredContinuation: CheckedContinuation<Void, Never>?
  private var releaseContinuation: CheckedContinuation<Void, Never>?

  func wait() async {
    entered = true
    enteredContinuation?.resume()
    enteredContinuation = nil
    guard !released else { return }
    await withCheckedContinuation { releaseContinuation = $0 }
  }

  func waitUntilEntered() async {
    if entered { return }
    await withCheckedContinuation { enteredContinuation = $0 }
  }

  func release() {
    released = true
    releaseContinuation?.resume()
    releaseContinuation = nil
  }
}

/// A detached window's store carries no CloudKit stack (`cloudSyncMode == .off`,
/// no coordinator), so its only live convergence on an MCP-host or main-window
/// write is the process-wide DB-change relay. These tests drive
/// `NotificationCenter.default` (which the observers subscribe to) and share the
/// single detached-window preferences suite, so they are serialized to keep one
/// test's post and store state out of another's.
@Suite(.serialized)
@MainActor
struct DetachedWindowConvergenceTests {
  @Test("a committed same-process write reloads the task a detached window shows")
  func detachedTaskWindowReloadsShownTaskOnCommittedWrite() async throws {
    let core = try await makeSeededInMemoryCore()
    let store = AppStore(core: core)
    let target: LorvexTask.ID = LorvexPreviewSeedID.agendaTask

    let detached = store.makeDetachedWindowStore()
    await detached.loadDetachedTaskWindow(taskID: target)
    let originalTitle = try #require(detached.selectedTask?.title)

    let previousLocalDelivery = DatabaseChangeSignal.postsInProcessOnWrite
    DatabaseChangeSignal.postsInProcessOnWrite = true
    defer { DatabaseChangeSignal.postsInProcessOnWrite = previousLocalDelivery }
    detached.startDetachedWindowObserversIfNeeded()
    defer { detached.stopDetachedWindowObservers() }
    // Let the observer task reach its async sequence before committing the write.
    try? await Task.sleep(for: .milliseconds(10))

    // This is the exact main-window / peer-detached path: the shared core commits
    // an edit, its write funnel schedules the in-process signal, and this store
    // must re-read without a hand-posted test notification.
    _ = try await core.updateTask(TaskUpdateDraft(id: target, title: "Edited out of band"))
    #expect(detached.selectedTask?.title == originalTitle)

    for _ in 0..<200 where detached.selectedTask?.title != "Edited out of band" {
      try? await Task.sleep(for: .milliseconds(5))
    }

    // The reload fired: the out-of-band edit is now shown, which only a re-read
    // from the store could surface.
    #expect(detached.selectedTask?.title == "Edited out of band")
  }

  @Test("detached observer startup is idempotent and stop prevents later reloads")
  func detachedObserverLifecycleIsBalanced() async throws {
    let core = try await makeSeededInMemoryCore()
    let store = AppStore(core: core)
    let target: LorvexTask.ID = LorvexPreviewSeedID.agendaTask
    let detached = store.makeDetachedWindowStore()
    await detached.loadDetachedTaskWindow(taskID: target)
    let originalTitle = try #require(detached.selectedTask?.title)

    detached.startDetachedWindowObserversIfNeeded()
    detached.startDetachedWindowObserversIfNeeded()
    #expect(detached.detachedWindowObserverTasks.count == 1)
    try? await Task.sleep(for: .milliseconds(10))

    detached.stopDetachedWindowObservers()
    #expect(detached.detachedWindowObserverTasks.isEmpty)

    _ = try await core.updateTask(TaskUpdateDraft(id: target, title: "Edit after close"))
    NotificationCenter.default.post(
      name: DatabaseChangeSignal.didChangeNotification, object: nil)
    try? await Task.sleep(for: .milliseconds(100))

    #expect(detached.selectedTask?.title == originalTitle)
  }

  @Test("closing a detached window rejects a DB read that already started")
  func detachedObserverStopRejectsSuspendedReadResult() async throws {
    let preview = try await makeSeededInMemoryCore()
    let core = StubFocusCoreService(preview: preview)
    let target: LorvexTask.ID = LorvexPreviewSeedID.agendaTask
    let original = try await preview.loadTask(id: target)
    core.loadTaskOverride = original

    let parent = AppStore(core: core)
    let detached = parent.makeDetachedWindowStore()
    await detached.loadDetachedTaskWindow(taskID: target)
    #expect(detached.selectedTask?.title == original.title)

    let lateResult = try await preview.updateTask(
      TaskUpdateDraft(id: target, title: "Read completed after close"))
    let gate = DetachedTaskReadGate()
    core.loadTaskOverride = lateResult
    core.loadTaskGate = { await gate.wait() }

    detached.startDetachedWindowObserversIfNeeded()
    try await Task.sleep(for: .milliseconds(10))
    NotificationCenter.default.post(
      name: DatabaseChangeSignal.didChangeNotification, object: nil)
    await gate.waitUntilEntered()

    detached.stopDetachedWindowObservers()
    await gate.release()
    for _ in 0..<200 where detached.isReloadingDetachedWindowEntity {
      try await Task.sleep(for: .milliseconds(5))
    }

    #expect(
      detached.selectedTask?.title == original.title,
      "a read owned by the closed observer epoch must never adopt its late result")
  }

  @Test("core replacement rejects a suspended read from the previous database")
  func detachedCoreReplacementRejectsPreviousCoreRead() async throws {
    let oldPreview = try await makeSeededInMemoryCore()
    let oldCore = StubFocusCoreService(preview: oldPreview)
    let target: LorvexTask.ID = LorvexPreviewSeedID.agendaTask
    oldCore.loadTaskOverride = try await oldPreview.loadTask(id: target)

    let parent = AppStore(core: oldCore)
    let detached = parent.makeDetachedWindowStore()
    await detached.loadDetachedTaskWindow(taskID: target)

    let staleOldResult = try await oldPreview.updateTask(
      TaskUpdateDraft(id: target, title: "Late result from replaced core"))
    let oldReadGate = DetachedTaskReadGate()
    oldCore.loadTaskOverride = staleOldResult
    oldCore.loadTaskGate = { await oldReadGate.wait() }

    detached.startDetachedWindowObserversIfNeeded()
    defer { detached.stopDetachedWindowObservers() }
    try await Task.sleep(for: .milliseconds(10))
    NotificationCenter.default.post(
      name: DatabaseChangeSignal.didChangeNotification, object: nil)
    await oldReadGate.waitUntilEntered()

    let newPreview = try await makeSeededInMemoryCore()
    let newTask = try await newPreview.updateTask(
      TaskUpdateDraft(id: target, title: "Canonical replacement core"))
    let newCore = StubFocusCoreService(preview: newPreview)
    newCore.loadTaskOverride = newTask
    await detached.adoptReplacedCore(newCore)
    #expect(detached.selectedTask?.title == "Canonical replacement core")

    await oldReadGate.release()
    for _ in 0..<200 where detached.isReloadingDetachedWindowEntity {
      try await Task.sleep(for: .milliseconds(5))
    }

    #expect(
      detached.selectedTask?.title == "Canonical replacement core",
      "the old core's late read must not overwrite the replacement state")
  }

  @Test("a dirty task draft blocks the reload, then convergence resumes when clean")
  func detachedTaskWindowReloadPreservesUnsavedDraft() async throws {
    let core = try await makeSeededInMemoryCore()
    let store = AppStore(core: core)
    let target: LorvexTask.ID = LorvexPreviewSeedID.agendaTask

    let detached = store.makeDetachedWindowStore()
    await detached.loadDetachedTaskWindow(taskID: target)
    let originalTitle = try #require(detached.selectedTask?.title)

    // The user is mid-edit in the detached window: an unsaved draft title.
    detached.taskDetailTitle = "half-typed title"
    #expect(detached.selectedTaskDraftHasChanges)

    // An out-of-band writer edits the same task; the change signal then fires.
    _ = try await core.updateTask(TaskUpdateDraft(id: target, title: "Edited out of band"))
    await detached.reloadDetachedWindowEntity()

    // The draft guard blocked the reload: the in-progress edit is intact and the
    // stored title a force-sync would have adopted was not applied.
    #expect(detached.taskDetailTitle == "half-typed title")
    #expect(detached.selectedTaskDraftHasChanges)
    #expect(detached.selectedTask?.title == originalTitle)
    #expect(detached.detachedWindowReloadDeferredForDraft)

    // Once the draft is clean again, the sticky-window onChange resumes the
    // deferred invalidation; no second peer write or focus change is required.
    detached.taskDetailTitle = originalTitle
    #expect(!detached.selectedTaskDraftHasChanges)
    await detached.resumeDeferredDetachedWindowReloadIfPossible()
    #expect(detached.selectedTask?.title == "Edited out of band")
    #expect(!detached.detachedWindowReloadDeferredForDraft)
  }

  @Test("a half-typed checklist item also defers detached-window convergence")
  func detachedTaskWindowPreservesChecklistComposer() async throws {
    let core = try await makeSeededInMemoryCore()
    let store = AppStore(core: core)
    let target: LorvexTask.ID = LorvexPreviewSeedID.agendaTask
    let detached = store.makeDetachedWindowStore()
    await detached.loadDetachedTaskWindow(taskID: target)
    let originalTitle = try #require(detached.selectedTask?.title)

    detached.taskDetailNewChecklistText = "half-typed checklist item"
    #expect(detached.selectedTaskHasUnsavedEditorState)
    _ = try await core.updateTask(TaskUpdateDraft(id: target, title: "Peer title"))
    await detached.reloadDetachedWindowEntity()

    #expect(detached.selectedTask?.title == originalTitle)
    #expect(detached.taskDetailNewChecklistText == "half-typed checklist item")
    #expect(detached.detachedWindowReloadDeferredForDraft)

    detached.taskDetailNewChecklistText = ""
    await detached.resumeDeferredDetachedWindowReloadIfPossible()
    #expect(detached.selectedTask?.title == "Peer title")
  }

  @Test("a main-store refresh preserves a dirty draft when a peer moves its task off-surface")
  func mainStoreRefreshPreservesDirtyTaskDraft() async throws {
    let core = try await makeSeededInMemoryCore()
    let store = AppStore(core: core)
    await store.refresh()
    let target: LorvexTask.ID = LorvexPreviewSeedID.agendaTask
    store.selectedTaskID = target
    store.syncSelectedTaskDraft()
    store.taskDetailTitle = "half-typed main-window title"
    #expect(store.selectedTaskDraftHasChanges)

    // A peer defers the task far enough that it leaves Today's visible pool.
    // The following full refresh used to clear selectedTaskID and, through its
    // didSet, silently clear the user's draft.
    _ = try await core.deferTask(
      id: target, until: Date(timeIntervalSince1970: 4_000_000_000))
    await store.refresh()

    #expect(store.selectedTaskID == target)
    #expect(store.taskDetailTitle == "half-typed main-window title")
    #expect(store.taskDetailDraftTaskID == target)
  }

  @Test("a database-change signal reloads the list a detached window shows")
  func detachedListWindowReloadsShownListOnSignal() async throws {
    let core = try await makeSeededInMemoryCore()
    let store = AppStore(core: core)
    let target: LorvexList.ID = LorvexPreviewSeedID.appleNativeList
    let taskInList: LorvexTask.ID = LorvexPreviewSeedID.agendaTask

    let detached = store.makeDetachedWindowStore()
    await detached.loadDetachedListWindow(listID: target)
    let shown = try #require(detached.selectedListDetail?.tasks.first { $0.id == taskInList })
    #expect(shown.title != "Renamed out of band")

    _ = try await core.updateTask(TaskUpdateDraft(id: taskInList, title: "Renamed out of band"))
    await detached.reloadDetachedWindowEntity()

    // The reload re-read the list detail: the out-of-band rename is now visible.
    let reloaded = detached.selectedListDetail?.tasks.first { $0.id == taskInList }
    #expect(reloaded?.title == "Renamed out of band")
  }
}

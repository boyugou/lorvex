import Foundation
import LorvexCloudSync
import LorvexCore

/// Weak holder so the parent store can track spawned detached-window stores
/// without retaining a closed window's store.
final class WeakAppStoreBox {
  weak var store: AppStore?
  init(_ store: AppStore) { self.store = store }
}

extension AppStore {
  func makeDetachedWindowStore() -> AppStore {
    // Detached windows always load a specific task/list on open, so their
    // navigation-state persistence is moot — use one shared, ephemeral suite
    // rather than a fresh UUID suite per window. The old per-window-UUID suite
    // leaked a preferences plist for every detached window that was ever opened.
    let suiteName = "com.lorvex.detached-window"
    let defaults = UserDefaults(suiteName: suiteName) ?? .standard
    // Prune closed-window boxes, then only reset the shared suite when no other
    // detached window is still live — wiping it unconditionally would clobber a
    // sibling window's state every time a second window opens.
    detachedWindowStores.removeAll { $0.store == nil }
    if detachedWindowStores.isEmpty {
      defaults.removePersistentDomain(forName: suiteName)
    }
    // A detached window never owns the App-Group snapshot: its `today`/`habits`/
    // `currentFocus` are not the full live state, so letting it publish would blank
    // the widgets. Use a no-op publisher; the main window's snapshot is authoritative.
    let store = AppStore(
      core: core,
      feedbackProvider: feedbackProvider,
      taskSearchIndexer: taskSearchIndexer,
      contentSearchIndexer: contentSearchIndexer,
      taskReminderScheduler: taskReminderScheduler,
      // A detached window's mutations reschedule reminders from the full core
      // task set (appleSurfaceTasks reads the DB, not this store's partial
      // surfaces), so the task + habit reschedule share one notification budget.
      // Carry the real habit scheduler too — a Noop here would let the budget
      // plan habit slots that never arm while task reminders take the cap.
      habitReminderScheduler: habitReminderScheduler,
      widgetSnapshotPublisher: NoopWidgetSnapshotPublisher(),
      cloudSyncMode: .off,
      // No coordinator belongs to this window, but retention must follow the
      // app's real product configuration. In live mode, shedding active outbox
      // rows would turn harmless sync debt into a forced full reseed.
      includeActiveOutboxCapProvider: { [weak self] in
        // If the parent authority ever disappears while this window is still
        // alive, fail safe toward retaining sync debt rather than interpreting
        // an absent mode as permission to shed it.
        self.map { $0.cloudSyncMode != .live } ?? false
      },
      cloudSyncSubscriber: NoOpCloudSyncSubscriber(),
      cloudSyncCoordinator: nil,
      // A detached window must never run CloudKit itself, but its foreground
      // refresh still performs local retention. Route that maintenance through
      // the parent app's retained operation gate so it cannot cap the outbox or
      // mutate sync debt while the main window is importing, rebuilding, or
      // deleting the CloudKit namespace.
      cloudDataMaintenanceCoordinator:
        cloudDataMaintenanceCoordinator ?? cloudSyncCoordinator,
      eventKitCoordinator: eventKitCoordinator,
      badgeEnabled: badgeEnabled,
      setBadge: setBadge,
      now: now,
      defaults: defaults
    )
    detachedWindowStores.append(WeakAppStoreBox(store))
    return store
  }

  /// Adopt a database swap from the parent store: repoint at the new core and
  /// reload this detached window's task or list from the new database (surfacing
  /// an error if it no longer exists there) instead of continuing to commit to
  /// the old file.
  func adoptReplacedCore(_ core: any LorvexCoreServicing) async {
    // A convergence read may already be suspended against the previous core.
    // Stop first to advance the observer epoch, so that read cannot adopt its
    // old-database result after the replacement load below. Restore observation
    // only after the new core has established the window's canonical state.
    let wasObserving = !detachedWindowObserverTasks.isEmpty
    if wasObserving {
      stopDetachedWindowObservers()
    } else {
      detachedWindowObserverEpoch &+= 1
    }
    self.core = core
    if let taskID = selectedTaskID {
      await loadDetachedTaskWindow(taskID: taskID)
    } else if let listID = selectedListID {
      await loadDetachedListWindow(listID: listID)
    }
    if wasObserving { startDetachedWindowObserversIfNeeded() }
  }

  /// Start the detached window's convergence observer exactly once. The
  /// window's store can't see an MCP-host or main-window write on its own
  /// (`cloudSyncMode == .off`, no coordinator), so this observer relays the
  /// unified DB-change signal (coalesced in-process commits plus the
  /// cross-process Darwin relay) into a reload of the single entity this window
  /// shows. Idempotent (guards on the already-started array). Pair with
  /// ``stopDetachedWindowObservers()`` on window close so the loop ends and the
  /// per-window store is released.
  func startDetachedWindowObserversIfNeeded() {
    guard detachedWindowObserverTasks.isEmpty else { return }
    detachedWindowObserverEpoch &+= 1
    let observerEpoch = detachedWindowObserverEpoch
    detachedWindowObserverTasks = [
      Task { [weak self] in
        await self?.observeDetachedWindowDatabaseChangeSignal(observerEpoch: observerEpoch)
      }
    ]
  }

  /// Cancel the detached window's convergence observer, ending the notification
  /// loop. Called when the window closes; without it the loop would sit suspended
  /// awaiting notifications for the process's lifetime (one leaked task per
  /// window ever opened), since a `[weak self]` that has gone nil is
  /// only observed on the next signal, which may never arrive.
  func stopDetachedWindowObservers() {
    // Invalidate already-queued reload children before cancelling the sequence
    // task; a buffered notification can otherwise mutate a closed window after
    // this method returns.
    detachedWindowObserverEpoch &+= 1
    for task in detachedWindowObserverTasks { task.cancel() }
    detachedWindowObserverTasks = []
    detachedWindowReloadPending = false
    detachedWindowReloadDeferredForDraft = false
  }

  private func observeDetachedWindowDatabaseChangeSignal(observerEpoch: UInt64) async {
    let stream = NotificationCenter.default.notifications(
      named: DatabaseChangeSignal.didChangeNotification)
    for await _ in stream {
      guard !Task.isCancelled, detachedWindowObserverEpoch == observerEpoch else { return }
      // Drain bursts into concurrent calls so the reload's own single-flight
      // guard can collapse them. Awaiting inline would replay every buffered
      // notification sequentially after each reload finished.
      Task { @MainActor [weak self] in
        guard let self, self.detachedWindowObserverEpoch == observerEpoch else { return }
        await self.reloadDetachedWindowEntity(observerEpoch: observerEpoch)
      }
    }
  }

  /// Reload the single task or list this detached window shows, coalescing a
  /// burst of change signals into one rerun. The DB-change relay carries no
  /// entity-level dirty set, so any signal reloads the shown entity — cheap: one
  /// task load or one list-detail read. A list window is reloaded first when it
  /// has one (a list window may also hold a task selection in its inspector);
  /// otherwise the task window's task is reloaded, but only when its detail draft
  /// is clean, so convergence never clobbers an in-progress edit. A reload
  /// skipped for a dirty draft resumes as soon as the editor becomes clean; a
  /// later signal or the regain-key path remains a backstop.
  func reloadDetachedWindowEntity() async {
    await reloadDetachedWindowEntity(observerEpoch: detachedWindowObserverEpoch)
  }

  private func reloadDetachedWindowEntity(observerEpoch: UInt64) async {
    guard detachedReloadIsCurrent(observerEpoch) else { return }
    guard !isReloadingDetachedWindowEntity else {
      detachedWindowReloadPending = true
      return
    }
    isReloadingDetachedWindowEntity = true
    defer {
      isReloadingDetachedWindowEntity = false
      // A new observer epoch may have requested a reload while the old epoch's
      // DB read was suspended. Hand the pending work to the current observer;
      // otherwise the stale flight would return safely but strand the new
      // invalidation until another unrelated signal arrived.
      if detachedWindowReloadPending, !detachedWindowObserverTasks.isEmpty {
        detachedWindowReloadPending = false
        let currentEpoch = detachedWindowObserverEpoch
        Task { @MainActor [weak self] in
          await self?.reloadDetachedWindowEntity(observerEpoch: currentEpoch)
        }
      }
    }
    repeat {
      detachedWindowReloadPending = false
      await reloadDetachedWindowEntityOnce(observerEpoch: observerEpoch)
      guard detachedReloadIsCurrent(observerEpoch) else { return }
    } while detachedWindowReloadPending
  }

  private func reloadDetachedWindowEntityOnce(observerEpoch: UInt64) async {
    if let listID = selectedListID {
      detachedWindowReloadDeferredForDraft = false
      await reloadDetachedListWindow(listID: listID, observerEpoch: observerEpoch)
    } else if let taskID = selectedTaskID {
      guard !selectedTaskHasUnsavedEditorState else {
        detachedWindowReloadDeferredForDraft = true
        return
      }
      detachedWindowReloadDeferredForDraft = false
      await reloadDetachedTaskWindow(taskID: taskID, observerEpoch: observerEpoch)
    }
  }

  private func detachedReloadIsCurrent(_ observerEpoch: UInt64) -> Bool {
    return !Task.isCancelled && detachedWindowObserverEpoch == observerEpoch
  }

  private func reloadDetachedTaskWindow(
    taskID: LorvexTask.ID, observerEpoch: UInt64
  ) async {
    let snapshotCore = core
    do {
      let task = try await snapshotCore.loadTask(id: taskID)
      guard detachedReloadIsCurrent(observerEpoch) else { return }
      replaceTask(task)
      syncSelectedTaskDraft(force: true)
      errorMessage = nil
    } catch {
      guard detachedReloadIsCurrent(observerEpoch) else { return }
      await presentUserFacingError(error)
    }
  }

  private func reloadDetachedListWindow(
    listID: LorvexList.ID, observerEpoch: UInt64
  ) async {
    let snapshotCore = core
    do {
      let reloadedLists = try await snapshotCore.loadLists()
      guard detachedReloadIsCurrent(observerEpoch) else { return }
      let reloadedDetail = try await snapshotCore.loadListDetail(
        id: listID, limit: 100, offset: 0)
      guard detachedReloadIsCurrent(observerEpoch) else { return }
      lists = reloadedLists
      selectedListDetail = reloadedDetail
      errorMessage = nil
    } catch {
      guard detachedReloadIsCurrent(observerEpoch) else { return }
      await presentUserFacingError(error)
    }
  }

  /// Resume an invalidation that was held while the user typed. Called when the
  /// sticky task draft transitions from dirty to clean; no-op for ordinary saves
  /// or when no peer invalidation was deferred.
  func resumeDeferredDetachedWindowReloadIfPossible() async {
    guard detachedWindowReloadDeferredForDraft, !selectedTaskHasUnsavedEditorState else { return }
    await reloadDetachedWindowEntity()
  }

  func loadDetachedTaskWindow(taskID: LorvexTask.ID) async {
    selectedTaskID = taskID
    await perform {
      let task = try await core.loadTask(id: taskID)
      replaceTask(task)
      syncSelectedTaskDraft(force: true)
    }
  }

  func loadDetachedListWindow(listID: LorvexList.ID) async {
    selectedListID = listID
    await perform {
      lists = try await core.loadLists()
      selectedListDetail = try await core.loadListDetail(id: listID, limit: 100, offset: 0)
    }
  }
}

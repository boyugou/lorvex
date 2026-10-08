import AppKit
@preconcurrency import CloudKit
import Foundation
import LorvexCloudSync
import LorvexCore
import LorvexWidgetKitSupport

extension AppStore {
  /// Starts the app-lifetime change observers exactly once and retains
  /// them on the store. Because the store outlives every window, the CloudKit
  /// push refresh, EventKit ingestion, and notification-action error toasts keep
  /// running after the main window is closed (the menu-bar extra keeps the app
  /// alive) — a per-window `.task` would cancel them and leave open workspace
  /// windows stale and notification-action failures silently dropped.
  func startLifetimeObserversIfNeeded() {
    guard lifetimeObserverTasks.isEmpty else { return }
    lifetimeObserverTasks = [
      Task { [weak self] in await self?.observeRemoteChanges() },
      Task { [weak self] in await self?.observeEventKitChanges() },
      Task { [weak self] in await self?.observeNotificationActionErrors() },
      Task { [weak self] in await self?.observeAppActivation() },
      Task { [weak self] in await self?.observeDatabaseChangeSignal() },
      Task { [weak self] in await self?.observeCloudKitAccountChanges() },
      Task { [weak self] in await self?.observeCalendarDayChange() },
      Task { [weak self] in await self?.connectCloudSyncReports() },
    ]
    rescheduleLogicalDayBoundaryWake()
    Task.detached(priority: .utility) { LorvexCaptureParser.warmUp() }
  }

  /// Republishes when the local calendar day rolls over. The widget/complication
  /// snapshot bakes day-relative stats (due-today / overdue / completed-today) at
  /// publish time, so without a day-boundary republish a Mac left running across
  /// midnight would keep serving yesterday's counts to its glance surfaces until
  /// the next unrelated refresh. `refresh()` reloads today and republishes the
  /// snapshot (which reloads all widget timelines). Foundation posts
  /// `NSCalendarDayChanged` at midnight and on any shift of the current day (time
  /// zone / clock changes), so this also covers travel across zones. Runs for the
  /// app's lifetime via `startLifetimeObserversIfNeeded`.
  func observeCalendarDayChange() async {
    let stream = NotificationCenter.default.notifications(named: .NSCalendarDayChanged)
    for await _ in stream {
      await refresh()
    }
  }

  /// Re-evaluates CloudKit when the signed-in iCloud account changes. CloudKit
  /// posts `CKAccountChanged` on sign-in, sign-out, and account switch. The
  /// controller compares the account with the one the local data last synced
  /// with: the same account resumes, a different one pauses until the user
  /// chooses to sync with it. Runs for the app's lifetime via
  /// `startLifetimeObserversIfNeeded`.
  func observeCloudKitAccountChanges() async {
    let stream = NotificationCenter.default.notifications(named: .CKAccountChanged)
    for await _ in stream {
      await handleCloudKitAccountChange()
    }
  }

  /// Re-evaluates the controller and publishes its state; a running
  /// controller then syncs through the ordinary refresh.
  func handleCloudKitAccountChange() async {
    guard cloudSyncMode == .live, let cloudSyncController else { return }
    let state = await cloudSyncController.handleAccountChange()
    await applyCloudSyncControllerState(state)
    if state == .running { await refresh() }
  }

  /// Hands the reports of syncs the engine starts on its own (a push, the
  /// system scheduler, a retry) to the same completion path as an explicit
  /// cycle. Runs once via `startLifetimeObserversIfNeeded`.
  func connectCloudSyncReports() async {
    await cloudSyncController?.setReportHandler { [weak self] report in
      await self?.handleCompletedCloudSyncReport(report)
    }
  }

  /// Refreshes whenever a committed shared-database write invalidates this
  /// store. `DatabaseChangeSignal` unifies coalesced same-process writes (another
  /// window, an App Intent / notification action, or a CloudKit apply) with the
  /// Darwin relay from the MCP host and widget extension. This is the live,
  /// frontmost counterpart to `observeAppActivation`: new state appears without
  /// the user switching away and back. Runs for the app's lifetime via
  /// `startLifetimeObserversIfNeeded`.
  func observeDatabaseChangeSignal() async {
    let stream = NotificationCenter.default.notifications(
      named: DatabaseChangeSignal.didChangeNotification)
    for await notification in stream {
      // A CloudKit cycle posts an origin-tagged invalidation after it has already
      // reconciled this store selectively. Independent detached stores still
      // need that signal, but refreshing the origin again would perform a second
      // sync cycle for the same commit.
      if let origin = notification.object as? AppStore, origin === self { continue }
      // Do not suspend this observer loop on the refresh itself: draining the
      // notification sequence lets a burst enter `refresh()` concurrently,
      // where RefreshSingleFlight collapses it to one trailing rerun. Awaiting
      // inline would serialize the buffered notifications and run one full
      // refresh for every signal after the previous refresh completed.
      Task { @MainActor [weak self] in await self?.refresh() }
    }
  }

  /// Refreshes when the app becomes active. Live invalidation should normally
  /// have converged the windows already; activation remains the
  /// platform-conventional backstop for a Darwin notification the process missed
  /// while suspended or before its observers started. Runs for the app's
  /// lifetime via `startLifetimeObserversIfNeeded`.
  func observeAppActivation() async {
    let stream = NotificationCenter.default.notifications(
      named: NSApplication.didBecomeActiveNotification)
    for await _ in stream {
      // iCloud may have become usable while the app was in the background
      // (signed in, network back); re-evaluate an unavailable controller.
      if case .unavailable = await cloudSyncController?.state {
        await handleCloudKitAccountChange()
      }
      await refresh()
    }
  }

  /// Starts an async loop that listens for `EKEventStoreChanged` notifications
  /// and triggers a calendar timeline refresh on each one. Runs for the app's
  /// lifetime via `startLifetimeObserversIfNeeded`.
  func observeEventKitChanges() async {
    let observer = EventKitChangeObserver { [self] in
      // AppStore is @MainActor-isolated. The EventKitChangeObserver callback is
      // @Sendable, so all mutations must be dispatched back to MainActor.
      await Task { @MainActor [self] in
        do {
          // EventKit posts this for the app's own write-backs too, so reload the
          // window the user is actually viewing — the no-arg overload would snap
          // it back to today and empty whatever week they navigated to.
          try await self.refreshCurrentCalendarTimeline()
        } catch {
          self.lastCalendarImportReport = .failed(
            operation: "eventkit-change-observer",
            error: error
          )
        }
      }.value
    }
    await observer.observe()
  }

  /// Listens for `.lorvexNotificationActionError` posted by AppDelegate when a
  /// notification action handler fails, and shows the failure's classification
  /// (``LorvexNotificationActionFailure``) in `toastMessage`.
  ///
  /// Call once at app startup alongside `observeRemoteChanges()`.
  func observeNotificationActionErrors() async {
    let stream = NotificationCenter.default.notifications(named: .lorvexNotificationActionError)
    for await note in stream {
      if let classification = note.userInfo?[LorvexNotificationActionFailure.classificationKey]
        as? UserFacingError.Classification
      {
        toastMessage = await userFacingBannerMessage(
          for: classification, source: "macos.notification.action_failed")
      } else {
        toastMessage = String(
          localized:
            "notification.action.failed", defaultValue: "Couldn’t perform that action.",
          table: "Localizable",
          bundle: LorvexL10n.bundle)
      }
    }
  }

  /// Starts an async loop that listens for `.lorvexCloudKitRemoteChange`
  /// notifications posted by AppDelegate and triggers a refresh on each one.
  /// Runs for the app's lifetime via `startLifetimeObserversIfNeeded`.
  func observeRemoteChanges() async {
    let stream = NotificationCenter.default.notifications(named: .lorvexCloudKitRemoteChange)
    for await _ in stream {
      // `refresh()` ends with a sync cycle, so a push notification just
      // triggers a refresh — no separate cycle call.
      await refresh()
    }
  }

  /// Runs one CloudKit pass: fetch, then send. Best-effort and silent: the
  /// outcome lands in the status fields and is never thrown. Starts the
  /// controller first when it has not started yet; a no-op while sync is off.
  /// Retries, throttling, and push-triggered syncs belong to `CKSyncEngine`,
  /// so this only runs on local triggers (a refresh after a local write, app
  /// activation, an account change).
  func runCloudSyncCycle() async {
    await cloudSyncCycleFlight.run {
      await runCloudSyncCycleBody()
    }
  }

  private func runCloudSyncCycleBody() async {
    guard cloudSyncMode == .live, let cloudSyncController else { return }
    // Stopped, failed, or waiting for iCloud: evaluate again, so a transient
    // failure or a returning account recovers on the next pass. A pause waits
    // for the user.
    switch await cloudSyncController.state {
    case .running, .paused: break
    case .stopped, .unavailable, .failed:
      await applyCloudSyncControllerState(await cloudSyncController.start())
    }
    do {
      let report = try await Task.detached(priority: .utility) {
        let signpost = LorvexSignpost.begin(.cloudSync)
        defer { LorvexSignpost.end(signpost) }
        return try await cloudSyncController.syncNow()
      }.value
      guard let report else {
        await applyCloudSyncControllerState(await cloudSyncController.state)
        return
      }
      await handleCompletedCloudSyncReport(report)
    } catch {
      lastCloudSyncRemoteChangeErrorMessage = await cloudSyncUserFacingErrorMessage(
        for: error, source: "macos.cloud_sync.cycle")
      await applyCloudSyncControllerState(await cloudSyncController.state)
    }
  }

  /// Records a completed pass and reloads what it changed.
  func handleCompletedCloudSyncReport(_ report: CloudSyncCycleReport) async {
    lastCloudSyncCycleReport = report
    lastCloudSyncRemoteChangeSucceededAt = now()
    lastCloudSyncRemoteChangeErrorMessage =
      report.iCloudStorageFull
      ? String(
        localized: "settings.cloud_sync.storage_full",
        defaultValue: "Your iCloud storage is full. Lorvex will finish syncing when there’s space.",
        table: "Localizable", bundle: LorvexL10n.bundle)
      : nil
    await reconcileSurfacesAfterCompletedCloudSyncCycle(report)
  }

  /// Publishes the controller's state to the status surfaces. A failure's
  /// technical detail goes to the diagnostics log; the status row gets the
  /// user-facing message.
  func applyCloudSyncControllerState(_ state: CloudSyncControllerState) async {
    switch state {
    case .stopped:
      break
    case .running:
      cloudKitAccountAvailability = .available
      cloudSyncPauseReason = nil
    case .unavailable(let availability):
      cloudKitAccountAvailability = availability
    case .paused(let reason):
      cloudKitAccountAvailability = .available
      cloudSyncPauseReason = reason
    case .failed(let detail):
      lastCloudSyncRemoteChangeErrorMessage = await cloudSyncUserFacingErrorMessage(
        forMessage: detail, source: "macos.cloud_sync.controller")
    }
  }

  /// Publish and adopt the canonical mutations described by one successfully
  /// completed sync report. Kept as one testable seam so notification gating and
  /// primary-surface reconciliation cannot drift apart.
  func reconcileSurfacesAfterCompletedCloudSyncCycle(_ report: CloudSyncCycleReport) async {
    // Inbound work changed local rows after the calling surface last read
    // them. A server winner can arrive through the outbound conflict path, so
    // adoption follows what the apply changed, not whether CloudKit fetched a
    // page. Outbound-only reports, and fetched batches whose records were all
    // held already (typically this device's own pushes coming back), changed
    // nothing: they neither notify nor reload.
    guard report.inbound.canonicalStateChanged else { return }

    // Inbound apply commits through its dedicated transactional path rather than
    // the ordinary local-write funnel, so notify independent same-process
    // stores here; the origin ignores its own already-reconciled signal.
    DatabaseChangeSignal.broadcastCommittedChangeInProcess(origin: self)

    if isRefreshing {
      // A local pass is running beside this cycle and may already have read
      // some surfaces from the pre-apply state. Reloading next to it could let
      // its older reads land after newer ones, so arm one trailing pass of the
      // same single-flight instead; that pass re-reads every surface.
      refreshFlight.requestRerun()
    } else if let domains = InboundReloadScope.domains(for: report.inbound.appliedEntityTypes) {
      // A bounded set of domains reloads selectively: a habits-only push
      // re-reads habits, not the task workspace, lists, calendar, or reviews.
      // The selective executor republishes every affected derived surface.
      await performSelectiveInboundReload(domains)
    } else {
      // A change no domain bounds (a diffuse `preference` change, or one with
      // no attributed kind, such as retention pruning of the assistant
      // changelog): re-read every local surface. This runs
      // inside the cycle, so it must be the local-only reload. `refresh()` ends
      // by waiting on the sync cycle, and waiting on the cycle that is running
      // this code would leave both single-flights waiting on each other.
      await refreshLocalSurfaces()
    }
  }

  func replaceCore(
    _ core: any LorvexCoreServicing,
    refreshAfterReplacement: Bool = true
  ) async {
    self.core = core
    await eventKitCoordinator?.updateProvider(from: core)
    resetRuntimeState()
    if refreshAfterReplacement {
      await refresh()
    }
    // Repoint any open detached task/list windows at the new database too, so
    // they stop committing edits to the old file.
    detachedWindowStores.removeAll { $0.store == nil }
    for box in detachedWindowStores {
      if let detached = box.store { await detached.adoptReplacedCore(core) }
    }
  }

  /// Reloads every local surface, then converges with iCloud.
  ///
  /// A refresh has two halves. The local pass (``performLocalRefresh()``) reads
  /// every surface from the on-disk store and republishes the derived surfaces;
  /// it runs under the shared `refreshFlight`. The sync tail
  /// (``runRefreshSyncTail()``) runs retention and one coalesced CloudKit
  /// cycle; it runs only after the local pass
  /// has released the flight. A slow, offline, or stalled CloudKit exchange
  /// therefore never delays the next local reload: a helper-process write
  /// (the MCP host, a widget) reaches the UI as soon as its change signal lands.
  ///
  /// A trigger arriving while a local pass is in flight (a database-change
  /// signal, `didBecomeActive`, or a CloudKit push, each from its own stream)
  /// arms one trailing local pass and returns at once; any number of such
  /// triggers collapse into that one pass, so a write that committed after the
  /// in-flight pass started its reads is still picked up. The leader runs the
  /// sync tail after the trailing pass, which pushes whatever those writes
  /// queued. A pass started inside a sync cycle has no tail of its own, so the
  /// coalesced trigger also arms one trailing cycle pass while a cycle runs.
  /// The coalesced caller does not await the in-flight run, so a
  /// notification-observer loop stays free to receive its next trigger.
  /// Re-entrancy-safe on `@MainActor`: the running/pending flags are read and
  /// written without an intervening suspension before the guard.
  func refresh() async {
    guard !isLocalFactoryResetRunning else { return }
    guard !isRefreshing else {
      refreshFlight.requestRerun()
      if isCloudSyncCycleRunning { cloudSyncCycleFlight.requestRerun() }
      return
    }
    await refreshFlight.run(body: { await performLocalRefresh() })
    await runRefreshSyncTail()
  }

  /// Awaitable refresh seam for a caller that must not report completion until
  /// a local pass that observed its preceding write has settled, followed by
  /// the sync tail. Ordinary observer triggers intentionally return immediately
  /// when coalesced; destructive or multi-record workflows use this variant so
  /// their shared busy fence covers the trailing pass as well.
  func refreshAndWaitForLatest() async {
    await refreshFlight.run(body: { await performLocalRefresh() })
    await runRefreshSyncTail()
  }

  /// Re-reads every local surface under the refresh single-flight, with no
  /// sync tail. A sync cycle uses this to adopt a fetched page it cannot
  /// attribute to specific domains: the cycle is already running, and a full
  /// ``refresh()`` would end by waiting on it.
  func refreshLocalSurfaces() async {
    guard !isLocalFactoryResetRunning else { return }
    await refreshFlight.run(body: { await performLocalRefresh() })
  }

  /// The network half of a refresh, run after the local pass has released
  /// `refreshFlight`: local retention, then one sync cycle that pulls peer
  /// changes and sends the outbox. Errors land in the cycle's status fields;
  /// sync is invisible and best-effort.
  private func runRefreshSyncTail() async {
    await runLocalRetentionMaintenance()
    await runCloudSyncCycle()
  }

  /// Reads and publishes every local surface. Performs no network work, so an
  /// offline or slow-network launch shows on-disk data immediately, and it
  /// never waits on the CloudSync operation gate.
  private func performLocalRefresh() async {
    let signpost = LorvexSignpost.begin(.refreshTotal)
    defer {
      LorvexSignpost.end(signpost)
      taskDataGeneration &+= 1
    }
    do {
      // Snapshot the detail draft before any awaited read. A peer can move,
      // complete, defer, or delete the selected task while the user is typing;
      // once the fresh collections no longer contain that row we can no longer
      // infer dirtiness by comparing against `selectedTask`, so preserve both an
      // already-dirty draft and edits made while this refresh is suspended.
      let taskDetailReload = taskDetailReloadSnapshot()
      // Today is the atomic source of the product logical day/timezone. Load it
      // first, then fan out every other day-scoped read using that exact key;
      // deriving `date` from the Mac clock could pair a Jul-21 Today snapshot
      // with Jul-20 habits when the configured zone crosses midnight first.
      today = try await core.loadToday()
      rescheduleLogicalDayBoundaryWake()
      let date = logicalTodayDateString
      surfaceDatabaseRecoveryNoticeIfNeeded()
      // The Reviews surface's Day scope may be showing a past day (editable or
      // read-only); refresh reloads the selected day, not today's.
      async let loadedDailyReview = core.loadDailyReview(date: dailyReviewEditorDate)
      // Objective evidence for the selected day, backing the right-hand panel.
      async let loadedDayEvidence = try? core.loadDaySummary(date: selectedReviewDate)
      // Preserve the viewed week across a full refresh; `nil` anchor is the
      // live trailing week.
      async let loadedWeeklyReview = core.getWeeklyReviewSnapshot(weekOf: weeklyReviewAnchor)
      async let loadedLists = core.loadLists()
      // Archived lists back the sidebar's Archived section; a failed read falls
      // back to the current value rather than aborting the whole refresh.
      async let loadedArchivedLists = try? core.loadArchivedLists()
      async let loadedHabits = core.loadHabits(date: date)
      async let loadedRuntimeDiagnostics = try? core.loadRuntimeDiagnostics()

      // Keep an in-progress daily review the user is typing — only adopt the
      // freshly-loaded values when the draft has no unsaved edits.
      let dailyReviewWasClean = dailyReviewDraftMatchesLoaded
      dailyReview = try await loadedDailyReview
      if dailyReviewWasClean { syncDailyReviewDraft() }
      weeklyReview = try await loadedWeeklyReview
      dayReviewEvidence = await loadedDayEvidence
      lists = try await loadedLists
      archivedLists = await loadedArchivedLists
      // Preserve the viewed week across a full refresh (⌘R, window open, CloudKit
      // push); the no-arg overload would reset it to today.
      try await refreshCurrentCalendarTimeline()
      // An archived list stays a valid selection (its detail is still viewable),
      // so reconcile against active + archived before falling back to the first
      // active list.
      let knownListIDs =
        (lists?.lists ?? []).map(\.id) + orderedArchivedLists.map(\.id)
      if selectedListID == nil || !knownListIDs.contains(where: { $0 == selectedListID }) {
        selectedListID = lists?.lists.first?.id
      }
      // Do not let this intermediate list-detail reload clear the selected task
      // before the final draft-aware reconciliation can decide whether it is
      // safe. The selection is protected only while it is still the one captured
      // above; a user navigation during the await remains authoritative.
      try await loadSelectedListDetail(
        preservingTaskSelection: taskDetailReload.selectedTaskID)
      habits = try await loadedHabits
      // Keep the habit cards' streak/rhythm/progress in sync after a full
      // refresh (CloudKit push, ⌘R, core swap) — otherwise stats reload only on
      // a habit mutation or the Habits surface's own .task.
      await loadAllHabitStats()
      await reloadArchivedHabitsIfLoaded()
      await reloadSelectedHabitDetailIfLoaded()
      runtimeDiagnostics = await loadedRuntimeDiagnostics
      // Memory is loaded lazily when its workspace first opens. Once loaded it
      // is part of the store's live surface and must participate in a database-
      // change refresh too; otherwise an MCP/App-Intent edit leaves an already-
      // open Memory workspace stale. Preserve any composer draft while adopting
      // the refreshed snapshot.
      if memoryStorage.memory != nil, let loadedMemory = try? await core.loadMemory() {
        adoptReloadedMemoryPreservingDraft(loadedMemory)
      }
      // The Tasks workspace is not part of the today/lists/habits fan-out
      // above, so a remote change or core swap would otherwise leave that pane
      // showing stale rows. Reload it before reconciling selection so the
      // reconcile sees the fresh pools.
      await reloadTaskWorkspaceIfLoaded()
      // A selected task that is in none of the loaded lists (finished or moved
      // away by a peer, say) would otherwise keep its older record.
      await refreshSelectedTaskRecord()
      let dirtyTaskDraftIDToPreserve = dirtyTaskIDToPreserve(after: taskDetailReload)
      reconcileSelectedTaskAfterRefresh(preservingDirtyTaskID: dirtyTaskDraftIDToPreserve)
      // The Apple system surfaces run in parallel, each from its own read, so a
      // failed read leaves only that surface as it was: the content index
      // (lists, habits, review, calendar), the task index (every searchable
      // task), the badge (every actionable task the day surfaces show), and the
      // reminder re-plan (the delivery-aware reminder query). Task and habit
      // reminders share that one budgeted re-plan so they compete for the OS
      // notification cap by earliest-due instead of racing two passes.
      async let contentIndex: Void = reindexContentForSpotlight()
      async let taskIndex: Void = reindexTasksForSpotlight()
      async let reminderSchedule: Void = rescheduleReminders()
      async let badge: Void = updateBadge()
      _ = await (contentIndex, taskIndex, reminderSchedule, badge)
      // The widget snapshot is a derived, best-effort surface: a missing or
      // corrupt App-Group sidecar or a transient file-lock failure must never
      // wipe the freshly loaded primary UI or raise a modal on launch.
      try? await publishWidgetSnapshot()
      // Re-evaluate after the indexing/scheduling awaits: the user may have
      // started typing after the earlier reconciliation. A clean inspector must
      // force-adopt peer changes even when its draft is already bound to the same
      // task id; the ordinary non-force sync deliberately no-ops in that case.
      if dirtyTaskIDToPreserve(after: taskDetailReload) != selectedTaskID {
        syncSelectedTaskDraft(force: true)
      }
      clearRefreshFailure()
    } catch {
      // A recovering open may have set aside a database before this failure (or
      // an unrelated later load failed after a clean recovery); surface the
      // recovery notice so it isn't lost, then present the failure — which, for a
      // fatal open, is the `unrecoverable` fatal copy rather than "try again".
      surfaceDatabaseRecoveryNoticeIfNeeded()
      clearLoadedStateAfterRefreshFailure()
      await presentRefreshFailure(error)
    }
  }

}

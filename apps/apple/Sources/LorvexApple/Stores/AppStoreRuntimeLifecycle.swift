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
      // One immediate launch attempt pays off a `.deleted` barrier whose prior
      // physical cleanup was interrupted even when ordinary sync remains off.
      Task { [weak self] in await self?.retryPendingCloudDataDeletionCleanup() },
    ]
    rescheduleLogicalDayBoundaryWake()
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

  /// Resets sync identity when the signed-in iCloud account changes. CloudKit
  /// posts `CKAccountChanged` on sign-in/sign-out/account switch; on it the
  /// registered-subscription flag is process/account scoped, so it is reset and
  /// the next `refresh` re-subscribes. Checkpoints are already account+generation
  /// qualified: a switch pauses, and explicit adoption clears the old lineage
  /// rather than destroying a valid checkpoint on a same-account notification.
  /// Runs for the app's lifetime via
  /// `startLifetimeObserversIfNeeded`.
  func observeCloudKitAccountChanges() async {
    let stream = NotificationCenter.default.notifications(named: .CKAccountChanged)
    for await _ in stream {
      await handleCloudKitAccountChange()
    }
  }

  /// Performs the account-change identity gate and invalidates process-local
  /// subscription state. An unchanged/first account immediately re-enters the
  /// ordinary refresh path to re-register and drain; a real switch stays paused.
  /// Best-effort — a gate-state failure is recorded, never thrown, matching the
  /// silent-sync contract.
  func handleCloudKitAccountChange() async {
    hasRegisteredSubscription = false
    // A new identity starts fresh: clear breaker/backoff for the new account.
    cloudSyncPacing.reset()
    guard cloudSyncMode == .live else { return }
    guard let cloudSyncCoordinator else { return }
    var shouldResumeSameAccountSync = false
    do {
      // A switch never copies this device's data into the newly observed Apple
      // ID. It closes the account gate until explicit adoption; a same-account
      // notification leaves the qualified checkpoint intact.
      let decision = try await cloudSyncCoordinator.handleAccountChange()
      shouldResumeSameAccountSync = decision == .backfilled
      if decision == .backfillFailed {
        lastCloudSyncRemoteChangeErrorMessage = await cloudSyncUserFacingErrorMessage(
          forMessage: "CloudKit full-resync backfill failed; sync is paused until retry.",
          source: "macos.cloud_sync.account_change")
      } else {
        lastCloudSyncRemoteChangeErrorMessage = nil
      }
    } catch {
      lastCloudSyncRemoteChangeErrorMessage = await cloudSyncUserFacingErrorMessage(
        for: error, source: "macos.cloud_sync.account_change")
    }
    // Surface a durable pause the account change may have set (a switch to a
    // different Apple ID) so Settings can offer the adopt action.
    await refreshCloudSyncPauseReason()
    // CKAccountChanged is also the only deterministic recovery signal after a
    // retry wake discovers that iCloud is temporarily unavailable and cancels
    // itself. For the unchanged/first account, immediately re-enter the normal
    // refresh single-flight: it re-registers the subscription and starts one
    // ordinary coordinator drain with freshly reset pacing. A real account
    // switch or user-deleted zone remains paused and deliberately does not run.
    if shouldResumeSameAccountSync {
      // The coordinator gate may have waited behind an in-flight cycle that
      // recorded a failure after the notification's eager reset above. Reset at
      // the actual recovery edge as well so this refresh is not paced off.
      cloudSyncPacing.reset()
      await refresh()
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
      // A deliberate return to the app is an explicit reset point for the sync
      // circuit breaker: clear any open breaker / backoff so the refresh's
      // cycle attempts immediately rather than staying wedged behind a stale
      // failure window (e.g. failures accumulated offline, now back online).
      cloudSyncPacing.reset()
      await retryPendingCloudDataDeletionCleanup()
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
  /// notification action handler fails, and routes the message into `toastMessage`.
  ///
  /// Call once at app startup alongside `observeRemoteChanges()`.
  func observeNotificationActionErrors() async {
    let stream = NotificationCenter.default.notifications(named: .lorvexNotificationActionError)
    for await note in stream {
      if let raw = note.userInfo?["errorMessage"] as? String {
        toastMessage = await userFacingBannerMessage(
          forMessage: raw, source: "macos.notification.action_failed")
      } else {
        toastMessage = String(
          localized:
            "notification.action.failed", defaultValue: "Couldn't perform that action.",
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
      // `refresh()` runs the sync cycle via `publishAppleSyncSurfaces`, so a
      // push notification just triggers a refresh — no separate cycle call.
      await refresh()
    }
  }

  /// Run the invisible sync, draining the inbound backlog and pacing failures,
  /// off the main actor. Best-effort: account-gating and errors are recorded in
  /// the status fields and never thrown — sync is silent. No-ops when sync is
  /// off / iCloud is unavailable.
  ///
  /// Pacing gates *when* a cycle runs without changing the silent contract:
  ///
  /// - Before running, `cloudSyncPacing.shouldRun` skips the trigger while the
  ///   previous attempts are in their backoff window or the circuit breaker is
  ///   open (after 20 consecutive failures). A single app-owned task wakes at
  ///   the next retry/deferred-work deadline; the breaker itself is reset
  ///   explicitly on account change and app activation.
  /// - `runDrainingCycle` loops until `moreInboundComing` is false, so a large
  ///   remote backlog drains in one trigger instead of one page per trigger.
  /// - A nil report is classified after refreshing the durable pause and live
  ///   account status. An account/generation boundary is retried after ordinary
  ///   backoff; an explicit unavailable account or durable pause cancels the
  ///   wake; a transient account-status failure advances ordinary retry backoff.
  /// - Failure (advances the backoff) means a thrown cycle error OR a report
  ///   that made no progress while a push failed:
  ///   `failedPushCount > 0 && pushedRecordCount == 0 && fetchedRecordCount == 0`.
  ///   Any progress (a push confirmed or a record fetched) counts as success
  ///   and resets the failure count.
  func runCloudSyncCycle() async {
    await cloudSyncCycleFlight.run {
      await runCloudSyncCycleBody()
    }
  }

  /// One gated CloudKit pass. ``runCloudSyncCycle()`` owns coalescing around
  /// this body so a trigger arriving at any suspension point requests a
  /// serialized trailing pass rather than starting a competing coordinator
  /// operation or disappearing.
  private func runCloudSyncCycleBody() async {
    guard cloudSyncMode == .live else {
      cancelCloudSyncRetryWake()
      return
    }
    guard let cloudSyncCoordinator else {
      cancelCloudSyncRetryWake()
      return
    }
    let snapshotCore = core
    guard snapshotCore is any EnvelopeSyncServicing else {
      cancelCloudSyncRetryWake()
      return
    }
    let now = self.now()
    // ±10% jitter to desynchronize backoff across devices.
    guard cloudSyncPacing.shouldRun(now: now, jitterFraction: Double.random(in: -1...1)) else {
      updateCloudSyncRetryWake(after: nil, retryCurrentWork: true)
      return
    }
    cloudSyncPacing.recordAttempt(now: now)

    do {
      // CloudKit I/O + apply transactions run off @MainActor in a detached task.
      let report = try await Task.detached(priority: .utility) {
        let signpost = LorvexSignpost.begin(.cloudSync)
        defer { LorvexSignpost.end(signpost) }
        return try await cloudSyncCoordinator.runDrainingCycle(core: snapshotCore)
      }.value
      // Surface any durable pause the cycle just set (a closed-app account
      // switch or an external zone deletion is detected inside the cycle) or
      // cleared, so the Settings notice stays current.
      await refreshCloudSyncPauseReason()
      // A nil report is deliberately ambiguous at the coordinator API: it can
      // mean a durable pause/account loss, or a safe account/generation boundary
      // abort whose local outbox rows remain pending. Re-prove the live account
      // here before deciding whether the app-owned wake can be discarded.
      guard let report else {
        await reconcileCloudSyncRetryWakeAfterNilReport(using: cloudSyncCoordinator)
        return
      }
      lastCloudSyncCycleReport = report
      if Self.cloudSyncCycleMadeNoProgress(report) {
        cloudSyncPacing.recordFailure()
        lastCloudSyncRemoteChangeErrorMessage = await cloudSyncUserFacingErrorMessage(
          forMessage: "CloudKit push failed without making progress",
          source: "macos.cloud_sync.cycle")
      } else {
        cloudSyncPacing.recordSuccess()
        lastCloudSyncRemoteChangeSucceededAt = now
        lastCloudSyncRemoteChangeErrorMessage = nil
      }
      await reconcileSurfacesAfterCompletedCloudSyncCycle(report)
      updateCloudSyncRetryWake(after: report, retryCurrentWork: false)
    } catch {
      if let partial = error as? CloudSyncPartialCycleFailure {
        lastCloudSyncCycleReport = partial.partialReport
        await reconcileSurfacesAfterCompletedCloudSyncCycle(partial.partialReport)
      }
      await refreshCloudSyncPauseReason()
      // A CloudKit `.requestRateLimited` / `.serviceUnavailable` names the
      // earliest instant the server will accept a retry; honor it as a throttle
      // that survives the next push/activation reset, so a user trigger cannot
      // stampede past an active server rate limit.
      if let retryAfter = CloudSyncTransientClassifier.serverRetryAfter(error) {
        cloudSyncPacing.recordServerThrottle(retryAfter: retryAfter, now: now)
      }
      cloudSyncPacing.recordFailure()
      lastCloudSyncRemoteChangeErrorMessage = await cloudSyncUserFacingErrorMessage(
        for: error, source: "macos.cloud_sync.cycle")
      updateCloudSyncRetryWake(
        after: (error as? CloudSyncPartialCycleFailure)?.partialReport,
        retryCurrentWork: true)
    }
  }

  private func reconcileCloudSyncRetryWakeAfterNilReport(
    using coordinator: CloudSyncEngineCoordinator
  ) async {
    guard cloudSyncPauseReason == nil else {
      cancelCloudSyncRetryWake()
      return
    }
    let availability =
      (try? await coordinator.accountChecker.checkAccountStatus()) ?? .couldNotDetermine
    cloudKitAccountAvailability = availability
    switch availability {
    case .available:
      // The cycle crossed a peer account/generation transition without
      // consuming its local results. Back off before re-reading authority, but
      // preserve an app-owned wake even if the notification is lost.
      cloudSyncPacing.recordFailure()
      updateCloudSyncRetryWake(after: nil, retryCurrentWork: true)
    case .couldNotDetermine, .temporarilyUnavailable:
      cloudSyncPacing.recordFailure()
      updateCloudSyncRetryWake(after: nil, retryCurrentWork: true)
    case .noAccount, .restricted:
      cancelCloudSyncRetryWake()
    }
  }

  /// Publish and adopt the canonical mutations described by one successfully
  /// completed sync report. Kept as one testable seam so notification gating and
  /// primary-surface reconciliation cannot drift apart.
  func reconcileSurfacesAfterCompletedCloudSyncCycle(_ report: CloudSyncCycleReport) async {
    // Inbound apply commits through its dedicated transactional path rather than
    // the ordinary local-write funnel. Notify independent same-process stores
    // only when canonical rows actually changed. Outbound-only and LWW-skipped
    // reports emit nothing; the origin ignores its own already-reconciled signal.
    if !report.inbound.appliedEntityTypes.isEmpty {
      DatabaseChangeSignal.broadcastCommittedChangeInProcess(origin: self)
    }

    // Inbound records were applied after the calling surface last read local
    // state. A server winner can arrive through the outbound conflict path, so
    // canonical changes must trigger adoption even when CloudKit fetched no
    // page. Fetched-but-unattributable pages conservatively request a full read.
    if report.fetchedRecordCount > 0 || !report.inbound.appliedEntityTypes.isEmpty {
      if isRefreshing {
        // A refresh fan-out is in flight (this cycle runs at its tail) and
        // already read every UI surface from the PRE-apply state. Bring the
        // just-applied records onto the surfaces that read them:
        //
        // - When the apply attributes its changes to a bounded set of domains,
        //   reload ONLY those inline (`performSelectiveInboundReload`) — a
        //   habits-only push re-reads habits, not the task workspace / lists /
        //   calendar / reviews. The inline reload runs before this cycle returns,
        //   so the records reach the UI in the same refresh without a full rerun.
        // - Otherwise (records fetched but not cleanly attributable — all
        //   foreign / skipped, or a diffuse `preference` change) request a full
        //   trailing rerun through the single-flight `refresh()` loop, which
        //   re-reads every surface, republishes the widget, and re-plans
        //   reminders/badge. Any number of such records collapse into this one
        //   pending rerun (`runDrainingCycle` already drained the backlog, so the
        //   rerun's own cycle fetches nothing), so the loop converges after a
        //   single extra fan-out instead of stampeding.
        if let domains = InboundReloadScope.domains(for: report.inbound.appliedEntityTypes) {
          await performSelectiveInboundReload(domains)
        } else {
          refreshFlight.requestRerun()
        }
      } else {
        // No refresh is in flight (typically the post-local-mutation outbox
        // drain), so the primary UI needs the same domain-selective adoption —
        // not merely a reminder/badge recompute. Otherwise a concurrent remote
        // habit/list/memory edit commits locally yet remains absent from the
        // open workspace. The selective executor already republishes every
        // affected derived surface. An unattributable batch falls back to one
        // full refresh; its tail sync call observes this cycle's running-id
        // guard and returns, so it cannot recurse.
        if let domains = InboundReloadScope.domains(for: report.inbound.appliedEntityTypes) {
          await performSelectiveInboundReload(domains)
        } else {
          await refresh()
        }
      }
    }
  }

  /// A cycle "made no progress" — the backoff predicate for a non-nil report —
  /// when a push failed and neither direction advanced: nothing pushed and
  /// nothing fetched. A push throw is folded into `failedPushCount` by the
  /// coordinator (it is not re-thrown), so this is the report-shaped half of
  /// the failure predicate; the thrown-error half is handled in the `catch`.
  static func cloudSyncCycleMadeNoProgress(_ report: CloudSyncCycleReport) -> Bool {
    report.failedPushCount > 0 && report.pushedRecordCount == 0 && report.fetchedRecordCount == 0
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

  /// Registers the private-database push subscription the first time only.
  /// Registration is an idempotent CloudKit upsert; the flag avoids re-issuing it
  /// on every refresh, and a failure is recorded (never thrown) with the flag left
  /// false so the next refresh retries. `refresh` calls this after the local
  /// fan-out — so a slow or offline network never blocks the first paint — and the
  /// account-change handler resets the flag so the next refresh re-subscribes under
  /// the new identity. No-op (succeeds silently) when sync is off (the injected
  /// subscriber is the `NoOp` one).
  func registerCloudSyncSubscriptionIfNeeded() async {
    guard !hasRegisteredSubscription else { return }
    do {
      try await cloudSyncSubscriber.registerSubscription()
      hasRegisteredSubscription = true
      lastCloudSyncSubscriptionErrorMessage = nil
    } catch {
      lastCloudSyncSubscriptionErrorMessage = await cloudSyncUserFacingErrorMessage(
        for: error, source: "macos.cloud_sync.subscription")
    }
  }

  /// Runs the full refresh fan-out under the shared `refreshFlight`, coalescing
  /// concurrent triggers.
  ///
  /// A trigger arriving while a refresh is in flight (a database-change signal,
  /// `didBecomeActive`, or a CloudKit push, each from its own stream) arms one
  /// trailing rerun and returns at once instead of starting a
  /// parallel fan-out; the in-flight refresh reruns exactly once after it
  /// completes. Any number of pending triggers collapse into a single rerun, so a
  /// write that committed after the in-flight refresh started its reads is picked
  /// up rather than staying stale until the next unrelated trigger. The coalesced
  /// caller does not await the in-flight run (`refresh()` returns no result), so a
  /// notification-observer loop stays free to receive its next trigger.
  /// Re-entrancy-safe on `@MainActor`: the running/pending flags are read and
  /// written without an intervening suspension before the guard.
  func refresh() async {
    guard !isLocalFactoryResetRunning else { return }
    guard !isRefreshing else {
      refreshFlight.requestRerun()
      return
    }
    await refreshFlight.run(body: { await performRefresh() })
  }

  /// Awaitable refresh seam for a caller that must not report completion until
  /// a fan-out that observed its preceding write has settled. Ordinary observer
  /// triggers intentionally return immediately when coalesced; destructive or
  /// multi-record workflows use this variant so their shared busy fence covers
  /// the trailing rerun as well.
  func refreshAndWaitForLatest() async {
    await refreshFlight.run(body: { await performRefresh() })
  }

  private func performRefresh() async {
    let signpost = LorvexSignpost.begin(.refreshTotal)
    defer { LorvexSignpost.end(signpost) }
    // Retention must not depend on successful UI reads or a live CloudKit apply.
    // Run its always-safe subset at the start of every foreground refresh;
    // only a non-live configured mode may shed an oversized active outbox.
    await runLocalRetentionMaintenance()
    // Load and render the local surfaces FIRST — before ANY network work,
    // including CloudKit push-subscription registration, which makes a real
    // network request on the first cold-start refresh (`hasRegisteredSubscription`
    // is process-local). So an offline or slow-network launch shows on-disk data
    // immediately instead of freezing the first paint until the network returns,
    // matching the iPhone refresh. The subscription is registered after this
    // fan-out, just before the push+pull cycle in `publishAppleSyncSurfaces`.
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
      // with Jul-20 focus/habits when the configured zone crosses midnight first.
      today = try await core.loadToday()
      rescheduleLogicalDayBoundaryWake()
      let date = logicalTodayDateString
      surfaceDatabaseRecoveryNoticeIfNeeded()
      async let loadedCurrentFocus = core.loadCurrentFocus(date: date)
      async let loadedFocusSchedule = core.loadFocusSchedule(date: date)
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

      currentFocus = try await loadedCurrentFocus
      focusSchedule = try await loadedFocusSchedule
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
      let dirtyTaskDraftIDToPreserve = dirtyTaskIDToPreserve(after: taskDetailReload)
      reconcileSelectedTaskAfterRefresh(preservingDirtyTaskID: dirtyTaskDraftIDToPreserve)
      // The content surfaces (lists/habits/review/calendar) don't depend on the
      // bulk task read, so index them regardless. When that read fails the task
      // index, reminders, and badge are left intact rather than shrunk to
      // today's tasks only. Task + habit reminders share one budgeted re-plan
      // (`rescheduleReminders`) so they compete for the OS notification cap by
      // earliest-due instead of racing two independent passes — so it rides the
      // task read alongside the index and badge.
      async let contentIndex: Void = reindexContentForSpotlight()
      if let surfaceTasks = await appleSurfaceTasks() {
        async let taskIndex: Void = reindexTasksForSpotlight(tasks: surfaceTasks)
        async let reminderSchedule: Void = rescheduleReminders(tasks: surfaceTasks)
        async let badge: Void = updateBadge(tasks: surfaceTasks)
        _ = await (taskIndex, reminderSchedule, badge)
      }
      await contentIndex
      // The local surfaces are loaded and rendered; NOW touch the network.
      // Register the push subscription (first cold-start refresh only) before the
      // push+pull cycle that `publishAppleSyncSurfaces` runs, so a slow or offline
      // network delays sync convergence but never the first paint.
      await registerCloudSyncSubscriptionIfNeeded()
      // Publishing the widget snapshot and draining the sync outbox is a
      // secondary, best-effort surface: a malformed sync entry (e.g. one that
      // fails title validation) must never wipe the freshly-loaded primary UI or
      // raise a modal on launch. Its own status fields record any failure.
      await publishAppleSyncSurfaces()
      // Re-evaluate after indexing/scheduling/network awaits: the user may have
      // started typing after the earlier reconciliation. A clean inspector must
      // force-adopt peer changes even when its draft is already bound to the same
      // task id; the ordinary non-force sync deliberately no-ops in that case.
      if dirtyTaskIDToPreserve(after: taskDetailReload) != selectedTaskID {
        syncSelectedTaskDraft(force: true)
      }
      errorMessage = nil
    } catch {
      // A recovering open may have set aside a database before this failure (or
      // an unrelated later load failed after a clean recovery); surface the
      // recovery notice so it isn't lost, then present the failure — which, for a
      // fatal open, is the `unrecoverable` fatal copy rather than "try again".
      surfaceDatabaseRecoveryNoticeIfNeeded()
      clearLoadedStateAfterRefreshFailure()
      await presentUserFacingError(error)
    }
  }

}

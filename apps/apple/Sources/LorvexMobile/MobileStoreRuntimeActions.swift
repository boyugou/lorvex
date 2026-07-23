import LorvexCore
import LorvexWidgetKitSupport

extension MobileStore {
  /// Runs the full refresh fan-out under the shared `refreshFlight`, coalescing
  /// concurrent triggers.
  ///
  /// A trigger arriving while a refresh is in flight (scene-active, a CloudKit
  /// push, a DB-change signal, a notification action — each from its own stream)
  /// arms one trailing rerun and awaits the loop instead of running a parallel
  /// body; the in-flight refresh then reruns exactly once after it completes.
  /// Serializing the bodies prevents an older read that completes last from
  /// clobbering the snapshot a newer refresh committed, and any number of pending
  /// triggers collapse into a single rerun. Coalesced callers are resumed with
  /// the final rerun's result, so a caller's `await` still means "a body that saw
  /// my trigger has finished" — the app delegate's background-fetch completion
  /// stays honest. Once the loop drains, `applyPendingCloudSyncModeIfNeeded()`
  /// runs (as the flight's `afterDrain`) so a sync-mode change queued while this
  /// refresh or its embedded cycle was in flight applies now that the refresh is
  /// no longer active. Re-entrancy-safe on `@MainActor`.
  @discardableResult
  public func refresh() async -> MobileCloudSyncLifecycleResult {
    await refreshFlight.run(
      body: { await performRefresh() },
      afterDrain: { await applyPendingCloudSyncModeIfNeeded() })
  }

  private func performRefresh() async -> MobileCloudSyncLifecycleResult {
    let signpost = LorvexSignpost.begin(.refreshTotal)
    defer { LorvexSignpost.end(signpost) }

    // Run retention before any fallible local read or network gate. The
    // always-safe subset must continue while live sync is unavailable/paused;
    // only a non-live mode may shed an oversized active outbox backlog.
    await runLocalRetentionMaintenance()

    // Publish the local snapshot FIRST — before ANY network work, including
    // CloudKit subscription registration, which makes a real network request on
    // the first cold-start refresh (`hasRegisteredSubscription` is process-local).
    // So the UI shows on-disk data without waiting on the network at all (macOS's
    // refresh already loads local-first). The loading indicator only appears while
    // the snapshot is still empty (the root view gates on `isLoading && today ==
    // .empty`), so a cold launch shows the spinner until this fast local load lands
    // and a later reload over populated data is silent.
    guard await loadLocalSurfaces(clearOnFailure: true) else { return .failed }

    // Now the network: register the push subscription, then run the push+pull cycle.
    // A confirmed import owns the coordinator gate while it writes, and queued
    // mode changes must linearize before imported rows can leave the device.
    // Its final refresh is therefore local-only; the import finisher clears the
    // fence, applies the latest requested mode, then starts one explicit cycle
    // only if the resulting mode is still Live.
    guard !isDataImportRunning else { return .noData }
    await registerCloudSyncSubscriptionIfNeeded()
    let syncResult = await runCloudSyncCycle()
    await reloadInboundSurfacesIfNeeded(after: syncResult)
    return syncResult
  }

  /// Adopt canonical rows a completed sync cycle may have committed into the
  /// primary UI without starting another sync cycle.
  ///
  /// This is shared by the full-refresh path and the normal post-mutation drain:
  /// both can pull peer writes after their visible surfaces were last read. A
  /// bounded applied-kind set gets the selective executor; a fetched but
  /// empty/diffuse set falls back to a best-effort full local reload. A push
  /// conflict reports the exact kinds its server winner changed, while an
  /// ordinary confirmed push performs no local reload. Neither branch calls
  /// CloudKit, so adoption cannot form a sync loop.
  func reloadInboundSurfacesIfNeeded(after syncResult: MobileCloudSyncLifecycleResult) async {
    guard syncResult == .newData else { return }
    guard let report = lastCloudSyncCycleReport else { return }
    let appliedKinds = report.inbound.appliedEntityTypes
    guard report.fetchedRecordCount > 0 || !appliedKinds.isEmpty else { return }
    if let domains = InboundReloadScope.domains(for: appliedKinds) {
      await reloadInboundDomains(domains)
    } else {
      // Best-effort — preserve the already-published UI if any local read fails.
      _ = await loadLocalSurfaces(clearOnFailure: false)
    }
    // Inbound apply bypasses the ordinary local-write funnel. Notify CarPlay and
    // any independent same-process store only when canonical rows changed; the
    // origin guard in the database-change observer prevents this
    // already-reconciled store from reloading itself.
    if !appliedKinds.isEmpty {
      DatabaseChangeSignal.broadcastCommittedChangeInProcess(origin: self)
    }
  }

  /// Load and publish every local surface from the on-disk store, managing
  /// `isLoading` across the load. Returns `false` — after surfacing the error, and
  /// (only when `clearOnFailure` is true) clearing the loaded snapshots — when a
  /// load throws. A post-sync reload passes `clearOnFailure: false` so a failed
  /// reload does not blank an already-populated UI.
  private func loadLocalSurfaces(clearOnFailure: Bool) async -> Bool {
    isLoading = true
    defer { isLoading = false }
    do {
      let hadLogicalDay = snapshot.today.logicalDay != nil
      let loadedToday = try await core.loadToday()
      let date = loadedToday.logicalDay ?? todayString()
      if !hadLogicalDay || selectedReviewDate > date {
        selectedReviewDate = date
      }
      let weekDigestToDay = weeklyReviewAnchor ?? date
      let weekDigestFromDay =
        LorvexDateFormatters.ymdUTCAddingDays(weekDigestToDay, days: -6) ?? weekDigestToDay
      let dailyReviewDraftAtStart = dailyReviewDraft
      let dailyReviewWasCleanAtStart =
        dailyReviewDraftAtStart == MobileDailyReviewDraft(review: dailyReview)
      async let loadedDailyReview = core.loadDailyReview(date: selectedReviewDate)
      async let loadedDayEvidence = try? core.loadDaySummary(date: selectedReviewDate)
      async let loadedWeeklyReview = core.getWeeklyReviewSnapshot(weekOf: weeklyReviewAnchor)
      async let loadedWeekDigest = (try? await core.getReviewHistory(
        from: weekDigestFromDay, to: weekDigestToDay, limit: 7)) ?? []
      snapshot = MobileHomeSnapshot(
        today: loadedToday,
        currentFocus: try await core.loadCurrentFocus(date: date),
        weeklyReview: try await loadedWeeklyReview
      )
      rescheduleLogicalDayBoundaryWake()
      // The load above opened the on-disk store, so surface any quarantine
      // recovery now — before the rest of the fan-out — rather than letting a
      // set-aside database be silent if a later load fails. A fatal open instead
      // throws into `catch` and is presented via the `unrecoverable` category.
      surfaceDatabaseRecoveryNoticeIfNeeded()
      dailyReview = try await loadedDailyReview
      // The read above suspends the main actor. Adopt into the editor only when
      // it was clean at the start AND the user did not type while the fan-out was
      // in flight; the previous one-bit snapshot could clobber such mid-refresh
      // edits.
      if dailyReviewWasCleanAtStart, dailyReviewDraft == dailyReviewDraftAtStart {
        dailyReviewDraft = MobileDailyReviewDraft(review: dailyReview)
      }
      dayReviewEvidence = await loadedDayEvidence
      weekReviewDigest = await loadedWeekDigest
      focusSchedule = try await core.loadFocusSchedule(date: date)
      let planningError = await loadPlanningSnapshotsPreservingLoadedState(date: date)
      if selectedTaskID == nil {
        selectedTaskID = snapshot.nextTask?.id
      }
      _ = try? await publishWidgetSnapshot()
      await rescheduleReminders()
      await updateBadge()
      if let planningError {
        await presentUserFacingError(planningError)
      } else {
        errorMessage = nil
      }
      invalidateAllViewOwnedData()
      return true
    } catch {
      // A recovering open may have set aside a database before this failure;
      // surface the recovery notice so it isn't lost, then present the failure —
      // which, for a fatal open, is the `unrecoverable` fatal copy.
      surfaceDatabaseRecoveryNoticeIfNeeded()
      if clearOnFailure { clearLoadedSnapshots() }
      await presentUserFacingError(error)
      return false
    }
  }

  @discardableResult
  public func refreshResettingCloudSyncPacing() async -> MobileCloudSyncLifecycleResult {
    // A foreground/manual full refresh runs the sync cycle, paying off any
    // persisted push handoff (a push that arrived before the store attached)
    // so it does not trigger a redundant drain later. Keep the exact token until
    // a real successful cycle returns; a transport/account gate is not an ACK.
    let handoffToken = MobileCloudSyncPushHandoff(defaults: defaults).pendingToken
    let startingSuccessfulGeneration = cloudSyncSuccessfulCycleGeneration
    cloudSyncPacing.reset()
    await retryPendingCloudDataDeletionCleanup()
    let result = await refresh()
    acknowledgePendingCloudSyncPush(
      token: handoffToken,
      startingSuccessfulGeneration: startingSuccessfulGeneration,
      result: result)
    return result
  }

  @discardableResult
  func publishWidgetSnapshot() async throws -> WidgetSnapshot {
    guard let sourceCore = core as? any LorvexWidgetSnapshotSourceServicing else {
      throw WidgetSnapshotPublisherError.atomicSourceUnavailable
    }
    let source = try await sourceCore.loadWidgetSnapshotSource(date: nil)
    return try await widgetSnapshotPublisher.publish(source: source)
  }

  func clearLoadedSnapshots() {
    snapshot = MobileHomeSnapshot(
      today: .empty,
      currentFocus: nil,
      weeklyReview: nil
    )
    lists = nil
    selectedListDetail = nil
    habits = nil
    habitDetailsByID = [:]
    calendarTimeline = nil
    calendarScheduledTasks = []
    dailyReview = nil
    dayReviewEvidence = nil
    weekReviewDigest = []
    focusSchedule = nil
    proposedFocusSchedule = nil
    selectedTaskID = nil
    invalidateAllViewOwnedData()
  }

  public func submitCaptureDraft() async {
    guard canSubmitCapture else { return }
    isCapturing = true
    defer { isCapturing = false }
    do {
      let created = try await submitCaptureDraftTasks()
      selectedTaskID = created.first?.id
      captureDraft = MobileCaptureDraft()
      await refresh()
      // Quick capture is a sheet over whatever surface raised it; close it and
      // let the new task land in the active list on refresh, rather than yanking
      // the user to a different tab.
      isPresentingCapture = false
      feedbackProvider.playFeedback(.captureSubmitted)
      errorMessage = nil
    } catch {
      await presentUserFacingError(error)
    }
  }

  private func submitCaptureDraftTasks() async throws -> [LorvexTask] {
    let titles = captureDraft.parsedTitles
    guard titles.count > 1 else {
      let task = try await core.createTask(
        title: captureDraft.trimmedTitle,
        notes: captureDraft.notes
      )
      return [task]
    }
    return try await core.batchCreateTasks(titles.map {
      TaskCreateDraft(title: $0, notes: captureDraft.notes)
    })
  }

  public func taskIsMutating(_ id: LorvexTask.ID) -> Bool {
    mutatingTaskIDs.contains(id)
  }

  /// Whether a task mutation for `taskID` (nil = an unscoped/batch mutation)
  /// could begin right now without the re-entrancy guard rejecting it: no
  /// unscoped mutation is in flight, and — for a scoped mutation — that task is
  /// not already mutating; an unscoped one additionally requires no scoped
  /// mutation in flight.
  func canBeginTaskMutation(id taskID: LorvexTask.ID?) -> Bool {
    guard unscopedTaskMutationCount == 0 else { return false }
    guard let taskID else { return mutatingTaskIDs.isEmpty }
    return !mutatingTaskIDs.contains(taskID)
  }

  private func beginTaskMutation(id taskID: LorvexTask.ID?) -> Bool {
    guard canBeginTaskMutation(id: taskID) else { return false }
    if let taskID {
      mutatingTaskIDs.insert(taskID)
    } else {
      unscopedTaskMutationCount += 1
    }
    return true
  }

  private func endTaskMutation(id taskID: LorvexTask.ID?) {
    if let taskID {
      mutatingTaskIDs.remove(taskID)
    } else {
      unscopedTaskMutationCount = max(0, unscopedTaskMutationCount - 1)
    }
  }

  @discardableResult
  func mutateTask(id taskID: LorvexTask.ID? = nil, _ operation: () async throws -> Void) async -> Bool {
    guard beginTaskMutation(id: taskID) else { return false }
    defer { endTaskMutation(id: taskID) }
    do {
      try await operation()
      await refresh()
      errorMessage = nil
      return true
    } catch {
      await presentUserFacingError(error)
      return false
    }
  }

  @discardableResult
  func mutateTaskReturningToday(
    id taskID: LorvexTask.ID? = nil,
    _ operation: () async throws -> TodaySnapshot
  ) async -> Bool {
    guard beginTaskMutation(id: taskID) else { return false }
    defer { endTaskMutation(id: taskID) }
    do {
      snapshot.today = try await operation()
      let date = logicalTodayString
      snapshot.currentFocus = try await core.loadCurrentFocus(date: date)
      if let taskID, let mutatedTask = try? await core.loadTask(id: taskID) {
        replaceKnownTask(mutatedTask)
      }
      if let selectedTaskID, selectedTaskID != taskID,
        let selectedTask = try? await core.loadTask(id: selectedTaskID)
      {
        replaceKnownTask(selectedTask)
      }
      invalidateTaskViews()
      await publishMobileSyncSurfaces()
      await rescheduleReminders()
      await updateBadge()
      errorMessage = nil
      return true
    } catch {
      await presentUserFacingError(error)
      return false
    }
  }

  @discardableResult
  func mutateTaskReturningTask(
    id taskID: LorvexTask.ID? = nil,
    _ operation: () async throws -> LorvexTask
  ) async -> Bool {
    guard beginTaskMutation(id: taskID) else { return false }
    defer { endTaskMutation(id: taskID) }
    do {
      let updated = try await operation()
      snapshot.today = try await core.loadToday()
      let date = logicalTodayString
      snapshot.currentFocus = try await core.loadCurrentFocus(date: date)
      replaceKnownTask(updated)
      invalidateTaskViews()
      await publishMobileSyncSurfaces()
      await rescheduleReminders()
      await updateBadge()
      errorMessage = nil
      return true
    } catch {
      await presentUserFacingError(error)
      return false
    }
  }
}

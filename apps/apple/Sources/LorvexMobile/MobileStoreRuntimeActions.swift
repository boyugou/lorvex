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
  /// stays honest. Re-entrancy-safe on `@MainActor`.
  @discardableResult
  public func refresh() async -> MobileCloudSyncLifecycleResult {
    await refreshFlight.run(body: { await performRefresh() })
  }

  private func performRefresh() async -> MobileCloudSyncLifecycleResult {
    let signpost = LorvexSignpost.begin(.refreshTotal)
    defer { LorvexSignpost.end(signpost) }

    // Run retention before any fallible local read or network gate. The
    // always-safe subset must continue while live sync is unavailable/paused;
    // only a non-live mode may shed an oversized active outbox backlog.
    await runLocalRetentionMaintenance()

    // Publish the local snapshot FIRST — before any network work — so the UI
    // shows on-disk data without waiting on the network at all. The loading indicator only appears while
    // the snapshot is still empty (the root view gates on `isLoading && today ==
    // .empty`), so a cold launch shows the spinner until this fast local load lands
    // and a later reload over populated data is silent.
    guard await loadLocalSurfaces(clearOnFailure: true) else { return .failed }

    // Local writes since the last pass (this app's own mutations, an MCP or App
    // Intent write that raised the change signal) have already changed the
    // outbox depth. Read it before the network so Settings reflects the queue as
    // it stands, rather than only after a cycle gets to run.
    await refreshSyncStatus()

    // Now the network. A confirmed import's own refresh stays local; the
    // import finishes with one explicit pass.
    guard !isDataImportRunning else { return .noData }
    let syncResult = await runCloudSyncCycle()
    await reloadInboundSurfacesIfNeeded(after: syncResult)
    return syncResult
  }

  /// Adopt what a completed sync cycle changed: the outbox depth it moved, and
  /// any canonical rows it committed — without starting another sync cycle.
  ///
  /// This is the shared tail of every pass (the full refresh, the
  /// post-mutation drain, a pass the engine ran on its own), so it is where a
  /// pass's effects reach the UI. The queue-status re-read is skipped for
  /// `.noData`, which is a pass that moved nothing or a gate (sync off, no
  /// account, paused) that ran no work.
  ///
  /// Surface adoption itself needs `.newData` and a pass that changed
  /// canonical rows: both the refresh path and the drain can pull peer writes
  /// after their visible surfaces were last read. A bounded applied-kind set
  /// gets the selective executor; a change no domain bounds (a diffuse
  /// preference, or one with no attributed kind) falls back to a best-effort
  /// full local reload. A push conflict reports the exact kinds its server
  /// winner changed, while an ordinary confirmed push, or a fetched batch of
  /// records already held (this device's own pushes coming back), performs no
  /// local reload. Neither branch calls CloudKit, so adoption cannot form a
  /// sync loop.
  func reloadInboundSurfacesIfNeeded(after syncResult: MobileCloudSyncLifecycleResult) async {
    if syncResult != .noData { await refreshSyncStatus() }
    guard syncResult == .newData else { return }
    guard let report = lastCloudSyncCycleReport, report.inbound.canonicalStateChanged else {
      return
    }
    if let domains = InboundReloadScope.domains(for: report.inbound.appliedEntityTypes) {
      await reloadInboundDomains(domains)
    } else {
      // Best-effort — preserve the already-published UI if any local read fails.
      _ = await loadLocalSurfaces(clearOnFailure: false)
    }
    // Inbound apply bypasses the ordinary local-write funnel, so notify any
    // independent same-process store here; the origin guard in the
    // database-change observer keeps this already-reconciled store from
    // reloading itself.
    DatabaseChangeSignal.broadcastCommittedChangeInProcess(origin: self)
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
      let planningError = await loadPlanningSnapshotsPreservingLoadedState(date: date)
      // Keep an already-open Memory workspace fresh after an out-of-band write
      // that reaches the full refresh rather than the selective `.memory` inbound
      // path — an in-process App Intent / Shortcut or an MCP edit. Only when
      // already loaded; mirror the inbound reconcile (adopt the snapshot, prune a
      // selection/edit whose entry is gone) while leaving the composer draft the
      // user may be typing.
      if memory != nil, let loadedMemory = try? await core.loadMemory() {
        memory = loadedMemory
        let liveKeys = Set(loadedMemory.entries.map(\.key))
        if let selectedMemoryKey, !liveKeys.contains(selectedMemoryKey) {
          self.selectedMemoryKey = nil
        }
        if let memoryEditingKey, !liveKeys.contains(memoryEditingKey) {
          self.memoryEditingKey = nil
        }
      }
      await reloadArchivedHabitsIfLoaded()
      if selectedTaskID == nil {
        selectedTaskID = snapshot.today.tasks.first?.id
      }
      _ = try? await publishWidgetSnapshot()
      await rescheduleReminders()
      await updateBadge()
      if let planningError {
        await presentRefreshFailure(planningError)
      } else {
        clearRefreshFailure()
      }
      invalidateAllViewOwnedData()
      return true
    } catch {
      // A recovering open may have set aside a database before this failure;
      // surface the recovery notice so it isn't lost, then present the failure —
      // which, for a fatal open, is the `unrecoverable` fatal copy.
      surfaceDatabaseRecoveryNoticeIfNeeded()
      if clearOnFailure { clearLoadedSnapshots() }
      await presentRefreshFailure(error)
      return false
    }
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
    snapshot = MobileHomeSnapshot(today: .empty, weeklyReview: nil)
    lists = nil
    habits = nil
    habitDetailsByID = [:]
    archivedHabits = []
    archivedHabitsAreLoaded = false
    calendarTimeline = nil
    calendarScheduledTasks = []
    dailyReview = nil
    dayReviewEvidence = nil
    weekReviewDigest = []
    proposedDayTimes = nil
    selectedTaskID = nil
    invalidateAllViewOwnedData()
  }

  public func submitCaptureDraft() async {
    guard canSubmitCapture else { return }
    isCapturing = true
    defer { isCapturing = false }
    do {
      _ = try await submitCaptureDraftTasks()
      captureDraft = MobileCaptureDraft()
      // The write is committed; repaint from the on-disk store and close the
      // sheet now. `refresh()` joins the shared single-flight, whose in-flight
      // pass can include the sync cycle's network tail (a first Live enable
      // pushes the entire baseline), so awaiting it here pins the sheet on
      // "Capturing" for the duration of someone else's sync. Local reload +
      // view invalidation is what actually surfaces the new task; the full
      // fan-out (outbox drain, widgets, sync) follows without gating dismissal.
      invalidateAllViewOwnedData()
      _ = await loadLocalSurfaces(clearOnFailure: false)
      // Quick capture is a sheet over whatever surface raised it; close it and
      // let the new task land in the active list, rather than yanking the user
      // to a different tab. Captured work is undated, so it belongs to the inbox
      // and not to today — the dismissal plus haptic is the confirmation, and
      // nothing is selected, since a task with no claim on today would not
      // resolve against the surfaces the user is left looking at.
      isPresentingCapture = false
      feedbackProvider.playFeedback(.captureSubmitted)
      errorMessage = nil
      Task { await self.refresh() }
    } catch {
      await presentUserFacingError(error)
    }
  }

  /// Each captured line becomes one task with the details its words name
  /// (see `captureTaskDraft(line:notes:)`); several lines go through one batch.
  private func submitCaptureDraftTasks() async throws -> [LorvexTask] {
    let lines = captureDraft.parsedTitles
    let drafts = try (lines.isEmpty ? [captureDraft.trimmedTitle] : lines).map {
      try captureTaskDraft(line: $0, notes: captureDraft.notes)
    }
    if drafts.count == 1 {
      return [try await core.createTask(drafts[0])]
    }
    return try await core.batchCreateTasks(drafts)
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
  func mutateTaskReturningToday(
    id taskID: LorvexTask.ID? = nil,
    affectedIDs: [LorvexTask.ID] = [],
    _ operation: () async throws -> TodaySnapshot
  ) async -> Bool {
    guard beginTaskMutation(id: taskID) else { return false }
    defer { endTaskMutation(id: taskID) }
    let namedIDs = stableUniqueTaskIDs(
      [taskID, selectedTaskID].compactMap { $0 } + affectedIDs)
    let placementsBefore = taskPlacements(of: namedIDs)
    do {
      snapshot.today = try await operation()
      if let taskID, let mutatedTask = try? await core.loadTask(id: taskID) {
        replaceKnownTask(mutatedTask)
      }
      // A batch mutation has no single `taskID`, so reconcile each affected task
      // into the store's cross-tab surfaces (`calendarScheduledTasks`, the task
      // cache) the same way the single-task path does — otherwise the Calendar
      // tab keeps the pre-mutation status until its own window reloads.
      for affectedID in affectedIDs where affectedID != taskID {
        if let mutated = try? await core.loadTask(id: affectedID) {
          replaceKnownTask(mutated)
        }
      }
      if let selectedTaskID, selectedTaskID != taskID,
        let selectedTask = try? await core.loadTask(id: selectedTaskID)
      {
        replaceKnownTask(selectedTask)
      }
      await reloadSurfacesAfterTaskMutation(
        ifPlacementsChangedFrom: placementsBefore, of: namedIDs)
      invalidateTaskViews()
      await reloadReviewEvidenceAfterTaskMutation()
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
    let namedIDs = stableUniqueTaskIDs([taskID, selectedTaskID].compactMap { $0 })
    let placementsBefore = taskPlacements(of: namedIDs)
    do {
      let updated = try await operation()
      snapshot.today = try await core.loadToday()
      replaceKnownTask(updated)
      await reloadSurfacesAfterTaskMutation(
        ifPlacementsChangedFrom: placementsBefore, of: namedIDs)
      invalidateTaskViews()
      await reloadReviewEvidenceAfterTaskMutation()
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

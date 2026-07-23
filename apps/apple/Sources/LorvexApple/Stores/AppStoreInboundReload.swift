import Foundation
import LorvexCore

extension AppStore {
  /// Reload only the surfaces an inbound sync's applied entity kinds can affect,
  /// after the refresh fan-out already loaded every surface from the PRE-apply
  /// state. `runCloudSyncCycle` calls this inline at the tail of the in-flight
  /// refresh (see `AppStoreRuntimeLifecycle`) instead of requesting a full
  /// trailing rerun, so a habits-only push re-reads habits without touching the
  /// task workspace / lists / calendar / reviews.
  ///
  /// Contracts it honors:
  /// - **Best-effort per surface.** A transient read failure keeps the value the
  ///   fan-out loaded moments ago rather than blanking it — unlike
  ///   `performRefresh`, whose full reload owns the clear-on-failure semantics.
  /// - **No re-entrant cycle.** It runs INSIDE `runCloudSyncCycle`, so it must
  ///   not itself run one (it republishes the widget via `publishWidgetSnapshot`,
  ///   never `publishAppleSyncSurfaces`).
  /// - **Single-flight task reload.** Task reloads route through
  ///   `reloadTaskWorkspaceIfLoaded()`, preserving the workspace's coalescing
  ///   guard so a concurrent local mutation's awaited reload still wins.
  ///
  /// Derived surfaces (reminders, badge, widget, task Spotlight) are recomputed
  /// from whichever primary domains reloaded. Content Spotlight (lists / habits /
  /// reviews / the wide calendar horizon) is deliberately left to the next full
  /// refresh: it is a background search index whose lag never shows stale UI, and
  /// reindexing it here would re-read the whole calendar horizon on every push.
  func performSelectiveInboundReload(_ domains: Set<InboundReloadDomain>) async {
    // Capture editor cleanliness before ANY awaited read can replace a
    // task-bearing surface. Otherwise a clean draft is compared against the
    // peer-updated task and falsely becomes "dirty", suppressing adoption of
    // the very remote change this reload is meant to surface.
    let taskDetailReload = taskDetailReloadSnapshot()

    // Refresh Today first when requested because it carries the authoritative
    // product logical day/timezone used by every later day-scoped read.
    if domains.contains(.today), let loaded = try? await core.loadToday() {
      today = loaded
    }
    let date = logicalTodayDateString
    let reloadsTaskBearingDomain =
      !domains.isDisjoint(with: [.today, .tasks, .lists, .calendar])
    // Exhaustive per-domain dispatch. The `switch` has no `default`, so a new
    // `InboundReloadDomain` case fails to compile until this executor handles it
    // (a real reload or a documented no-op). Iterating `allCases` keeps every case
    // present in the switch regardless of the requested set; `where` skips the
    // domains this reload didn't touch.
    for domain in InboundReloadDomain.allCases where domains.contains(domain) {
      switch domain {
      case .today:
        break  // Loaded above so dependent domains share its exact logical day.
      case .tasks:
        await reloadTaskWorkspaceIfLoaded()
      case .lists:
        if let loaded = try? await core.loadLists() { lists = loaded }
        if let loaded = try? await core.loadArchivedLists() { archivedLists = loaded }
        // An archived list stays a valid selection; reconcile against active +
        // archived before falling back to the first active list.
        let knownListIDs = (lists?.lists ?? []).map(\.id) + orderedArchivedLists.map(\.id)
        if selectedListID == nil || !knownListIDs.contains(where: { $0 == selectedListID }) {
          selectedListID = lists?.lists.first?.id
        }
        try? await loadSelectedListDetail(
          preservingTaskSelection: taskDetailReload.selectedTaskID)
      case .calendar:
        // Reload whatever window is on screen at its own span (day/week/month).
        try? await refreshCurrentCalendarTimeline()
      case .focus:
        // do/catch, not `try?`: these return an optional whose `nil` is a legitimate
        // remote CLEAR that must be reflected. `try?` would fold that nil into the
        // failure case and keep a stale plan. Only a thrown read error keeps the old
        // value.
        do { currentFocus = try await core.loadCurrentFocus(date: date) } catch {}
        do { focusSchedule = try await core.loadFocusSchedule(date: date) } catch {}
      case .reviews:
        // Preserve an in-progress daily-review draft: only adopt freshly-loaded
        // values when the editor has no unsaved edits, mirroring `performRefresh`.
        let dailyReviewWasClean = dailyReviewDraftMatchesLoaded
        // do/catch so a remote CLEAR (nil) is reflected; see the focus block.
        do {
          dailyReview = try await core.loadDailyReview(date: dailyReviewEditorDate)
          if dailyReviewWasClean { syncDailyReviewDraft() }
        } catch {}
        if let loaded = try? await core.getWeeklyReviewSnapshot(weekOf: weeklyReviewAnchor) {
          weeklyReview = loaded
        }
        if let loaded = try? await core.loadDaySummary(date: selectedReviewDate) {
          dayReviewEvidence = loaded
        }
      case .habits:
        if let loaded = try? await core.loadHabits(date: date) { habits = loaded }
        await loadAllHabitStats()
      case .memory:
        if let loaded = try? await core.loadMemory() {
          adoptReloadedMemoryPreservingDraft(loaded)
        }
      case .diagnostics:
        runtimeDiagnostics = (try? await core.loadRuntimeDiagnostics()) ?? runtimeDiagnostics
      }
    }
    // Drop an inspector selection a remote change made invalid, the same way the
    // full fan-out does — only when a task-bearing surface actually reloaded.
    if reloadsTaskBearingDomain {
      reconcileSelectedTaskAfterRefresh(
        preservingDirtyTaskID: dirtyTaskIDToPreserve(after: taskDetailReload))
    }

    // Derived surfaces. Read the task pool once (when needed) and feed both the
    // task Spotlight index and the shared reminder/badge re-plan, mirroring the
    // fan-out's single-read reuse.
    if domains.contains(.tasks) || InboundReloadScope.recomputesReminders(domains) {
      if let surfaceTasks = await appleSurfaceTasks() {
        if domains.contains(.tasks) {
          await reindexTasksForSpotlight(tasks: surfaceTasks)
        }
        if InboundReloadScope.recomputesReminders(domains) {
          await rescheduleReminders(tasks: surfaceTasks)
        }
        if InboundReloadScope.recomputesBadge(domains) {
          await updateBadge(tasks: surfaceTasks)
        }
      }
    }
    if InboundReloadScope.republishesWidget(domains) {
      try? await publishWidgetSnapshot()
    }
    // A clean inspector adopts changed peer fields. Re-evaluate dirtiness after
    // all derived-surface awaits so typing begun mid-reload is never clobbered.
    if reloadsTaskBearingDomain,
      dirtyTaskIDToPreserve(after: taskDetailReload) != selectedTaskID
    {
      syncSelectedTaskDraft(force: true)
    }
  }
}

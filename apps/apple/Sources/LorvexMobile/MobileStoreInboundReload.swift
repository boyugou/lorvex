import Foundation
import LorvexCore

extension MobileStore {
  /// Reload only the surfaces an inbound sync's applied entity kinds can affect,
  /// after `loadLocalSurfaces` (phase 1) already loaded everything from the
  /// PRE-apply on-disk state. `performRefresh` calls this instead of the full
  /// phase-2 `loadLocalSurfaces` when the cycle's applied kinds attribute cleanly
  /// to a bounded set of domains, so a habits-only push re-reads habits without
  /// re-reading the calendar / list / planning surfaces.
  ///
  /// Best-effort per surface: a transient read failure keeps the phase-1 value
  /// rather than blanking a working UI (the same intent as phase 2's
  /// `clearOnFailure: false`). Runs on `@MainActor` at the tail of the in-flight
  /// refresh; it does not run a sync cycle. Derived surfaces (widget, reminders,
  /// badge) are recomputed from whichever primary domains reloaded.
  func reloadInboundDomains(_ domains: Set<InboundReloadDomain>) async {
    if domains.contains(.today), let loaded = try? await core.loadToday() {
      snapshot.today = loaded
    }
    let date = logicalTodayString

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
        // Documented no-op: the mobile Tasks tab holds no store-published
        // task-workspace pool — it self-loads on appearance via `.task(id:)`. Every
        // store-published task surface (Today, lists, calendar/scheduled) reloads
        // under its own domain, which a `.task` inbound always includes alongside
        // `.tasks`; the task-derived reminders and badge still recompute below via
        // the derived fan-out. Nothing is left for `.tasks` to reload here.
        break
      case .lists:
        if let loaded = try? await core.loadLists() { lists = loaded }
      case .calendar:
        let endDate = Self.calendarEndDateString(from: date)
        if let loaded = try? await core.loadCalendarTimeline(from: date, to: endDate) {
          calendarTimeline = loaded
        }
        if let loaded = try? await core.getScheduledTasks(from: date, to: endDate, limit: 500) {
          calendarScheduledTasks = loaded
        }
      case .focus:
        // do/catch, not `try?`: these return an optional whose `nil` is a legitimate
        // remote CLEAR that must be reflected. `try?` would fold that nil into the
        // failure case and keep a stale plan. Only a thrown read error keeps the old
        // value.
        do { snapshot.currentFocus = try await core.loadCurrentFocus(date: date) } catch {}
        do { focusSchedule = try await core.loadFocusSchedule(date: date) } catch {}
      case .reviews:
        if let loaded = try? await core.getWeeklyReviewSnapshot(weekOf: weeklyReviewAnchor) {
          snapshot.weeklyReview = loaded
        }
        // Preserve an in-progress daily-review draft: adopt freshly-loaded values
        // only when the editor has no unsaved edits, mirroring `loadLocalSurfaces`.
        // do/catch so a remote CLEAR (nil) is reflected; see the focus block.
        let dailyReviewDraftAtStart = dailyReviewDraft
        let dailyReviewWasCleanAtStart =
          dailyReviewDraftAtStart == MobileDailyReviewDraft(review: dailyReview)
        do {
          dailyReview = try await core.loadDailyReview(date: selectedReviewDate)
          if dailyReviewWasCleanAtStart, dailyReviewDraft == dailyReviewDraftAtStart {
            dailyReviewDraft = MobileDailyReviewDraft(review: dailyReview)
          }
        } catch {}
        if let loaded = try? await core.loadDaySummary(date: selectedReviewDate) {
          dayReviewEvidence = loaded
        }
        let weekDigestToDay = weeklyReviewAnchor ?? date
        let weekDigestFromDay =
          LorvexDateFormatters.ymdUTCAddingDays(weekDigestToDay, days: -6) ?? weekDigestToDay
        if let loaded = try? await core.getReviewHistory(
          from: weekDigestFromDay, to: weekDigestToDay, limit: 7)
        {
          weekReviewDigest = loaded
        }
      case .habits:
        if let loaded = try? await core.loadHabits(date: date) { habits = loaded }
      case .memory:
        if let loaded = try? await core.loadMemory() {
          memory = loaded
          let liveKeys = Set(loaded.entries.map(\.key))
          if let selectedMemoryKey, !liveKeys.contains(selectedMemoryKey) {
            self.selectedMemoryKey = nil
          }
          // Keep the text the user was composing, but a remotely-deleted source
          // can no longer be renamed. Treat the preserved draft as a new entry.
          if let memoryEditingKey, !liveKeys.contains(memoryEditingKey) {
            self.memoryEditingKey = nil
          }
        }
      case .diagnostics:
        // Documented no-op: the mobile diagnostics surface (`runtimeDiagnostics` /
        // `recentDiagnosticLogs`) is loaded on demand when Settings appears, not by
        // the refresh fan-out (`loadLocalSurfaces` never reads it). A selective
        // inbound reload must stay a subset of that fan-out, so reloading it here
        // would over-read a surface the refresh itself leaves alone; Settings
        // re-reads it on next appearance. (macOS differs: its full refresh loads
        // diagnostics, so its executor reloads it selectively.)
        break
      }
    }
    // Several mobile workspaces own paginated/detail state in the View rather
    // than the store. Bump their observable keys after the canonical rows have
    // been reloaded so already-visible pages re-query instead of staying pinned
    // to their first `.task(id:)` result.
    if domains.contains(.tasks) { invalidateTaskViewsAfterCanonicalReload() }
    if domains.contains(.lists), !domains.contains(.tasks) { invalidateListDetailViews() }
    if domains.contains(.habits) { invalidateHabitDetailViews() }
    // Re-seat the Today selection when a task surface reloaded, matching phase 1.
    if !domains.isDisjoint(with: [.today, .tasks]), selectedTaskID == nil {
      selectedTaskID = snapshot.nextTask?.id
    }

    // Derived surfaces, from whichever primary domains reloaded.
    if InboundReloadScope.republishesWidget(domains) {
      _ = try? await publishWidgetSnapshot()
    }
    // Reminders derive from both task and habit rows; the badge counts due/overdue
    // TASKS only, so a habits-only change re-plans reminders without recomputing
    // the badge (which would also re-read the scheduled-task pool for nothing).
    if InboundReloadScope.recomputesReminders(domains) {
      await rescheduleReminders()
    }
    if InboundReloadScope.recomputesBadge(domains) {
      await updateBadge()
    }
  }
}

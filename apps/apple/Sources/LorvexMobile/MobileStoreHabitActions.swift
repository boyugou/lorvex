import Foundation
import LorvexCore

extension MobileStore {
  @discardableResult
  public func completeHabit(_ habit: LorvexHabit) async -> Bool {
    await mutateHabit {
      habits = try await core.completeHabit(id: habit.id, date: logicalTodayString)
    } afterWrite: {
      // A crossing plays the celebratory milestone feedback (and stages the
      // badge) in place of the ordinary completion note, so a single crisp haptic
      // marks the moment rather than two success taps in a row.
      if !stageMilestoneCelebrationIfReached(habitID: habit.id) {
        feedbackProvider.playFeedback(.habitCompleted)
      }
      await refreshHabitDetailIfLoaded(id: habit.id)
    }
  }

  @discardableResult
  public func uncompleteHabit(_ habit: LorvexHabit) async -> Bool {
    await mutateHabit {
      habits = try await core.uncompleteHabit(id: habit.id, date: logicalTodayString)
    } afterWrite: {
      feedbackProvider.playFeedback(.habitReset)
      await refreshHabitDetailIfLoaded(id: habit.id)
    }
  }

  /// Sets `habit` aside for today (a skip): an excused day, neither done nor
  /// missed. A day that already has a check-in cannot be skipped.
  @discardableResult
  public func skipHabit(_ habit: LorvexHabit) async -> Bool {
    await mutateHabit {
      habits = try await core.skipHabit(id: habit.id, date: logicalTodayString)
    } afterWrite: {
      feedbackProvider.playFeedback(.habitSkipped)
      await refreshHabitDetailIfLoaded(id: habit.id)
    }
  }

  /// Takes today's skip of `habit` back, returning the day to an ordinary open
  /// day.
  @discardableResult
  public func unskipHabit(_ habit: LorvexHabit) async -> Bool {
    await mutateHabit {
      habits = try await core.unskipHabit(id: habit.id, date: logicalTodayString)
    } afterWrite: {
      feedbackProvider.playFeedback(.habitReset)
      await refreshHabitDetailIfLoaded(id: habit.id)
    }
  }

  /// The skip command the habit's menus offer (``LorvexHabitSkip``): Skip Today
  /// or Undo Skip. False, and nothing written, when today holds a check-in.
  @discardableResult
  public func toggleHabitSkip(_ habit: LorvexHabit) async -> Bool {
    switch LorvexHabitSkip.action(for: habit) {
    case .skip: await skipHabit(habit)
    case .unskip: await unskipHabit(habit)
    case nil: false
    }
  }

  /// Check `habit` in on `date` (`YYYY-MM-DD`) by the shared rule
  /// (``LorvexHabitCheckIn``), the way the day review checks in on the day it
  /// reviews. Today's habits reload after it, since any day's check-in moves
  /// streaks, and so does an open review's evidence, whose sentence counts
  /// habits kept. A milestone crossed today celebrates as an ordinary
  /// check-in would.
  @discardableResult
  public func checkInHabit(_ habit: LorvexHabit, on date: String) async -> Bool {
    let action = LorvexHabitCheckIn.action(for: habit)
    guard action != .none else { return false }
    return await mutateHabit {
      switch action {
      case .complete: _ = try await core.completeHabit(id: habit.id, date: date)
      case .uncomplete: _ = try await core.uncompleteHabit(id: habit.id, date: date)
      case .addOne: _ = try await core.adjustHabitCompletion(id: habit.id, date: date, delta: 1)
      case .none: break
      }
      habits = try await core.loadHabits(date: logicalTodayString)
    } afterWrite: {
      if action == .uncomplete {
        feedbackProvider.playFeedback(.habitReset)
      } else if date != logicalTodayString
        || !stageMilestoneCelebrationIfReached(habitID: habit.id)
      {
        feedbackProvider.playFeedback(.habitCompleted)
      }
      await refreshHabitDetailIfLoaded(id: habit.id)
      await reloadReviewEvidenceAfterTaskMutation()
    }
  }

  @discardableResult
  public func completeHabits(_ ids: [LorvexHabit.ID]) async -> Bool {
    let uniqueIDs = stableUniqueHabitIDs(ids)
    guard !uniqueIDs.isEmpty else { return false }
    return await mutateHabit {
      habits = try await core.batchCompleteHabits(ids: uniqueIDs, date: logicalTodayString)
    } afterWrite: {
      // A batch can cross several milestones at once; celebrate the most
      // significant crossing (largest reached value) rather than dropping every
      // one, mirroring the single-complete paths. When nothing crossed, the
      // ordinary completion feedback stands in for the batch.
      if let mostSignificant = mostSignificantMilestoneCrossing(among: uniqueIDs) {
        _ = stageMilestoneCelebrationIfReached(habitID: mostSignificant)
      } else {
        feedbackProvider.playFeedback(.habitCompleted)
      }
      await refreshLoadedHabitDetails(ids: uniqueIDs)
    }
  }

  /// The id of the batch-completed habit with the largest just-reached milestone
  /// value, or `nil` when none of `ids` crossed a milestone. Reads the
  /// authoritative `milestone.justReached` stamped on the refreshed `habits`
  /// snapshot by `batchCompleteHabits`.
  private func mostSignificantMilestoneCrossing(among ids: [LorvexHabit.ID]) -> LorvexHabit.ID? {
    let idSet = Set(ids)
    return habits?.habits
      .filter { idSet.contains($0.id) }
      .compactMap { habit -> (id: LorvexHabit.ID, reached: Int)? in
        guard let reached = habit.milestone?.justReached else { return nil }
        return (habit.id, reached)
      }
      .max { $0.reached < $1.reached }?
      .id
  }

  @discardableResult
  public func uncompleteHabits(_ ids: [LorvexHabit.ID]) async -> Bool {
    let uniqueIDs = stableUniqueHabitIDs(ids)
    guard !uniqueIDs.isEmpty else { return false }
    let date = logicalTodayString
    return await mutateHabit {
      for id in uniqueIDs {
        habits = try await core.uncompleteHabit(id: id, date: date)
      }
    } afterWrite: {
      feedbackProvider.playFeedback(.habitReset)
      await refreshLoadedHabitDetails(ids: uniqueIDs)
    }
  }

  public var canCreateHabitDraft: Bool {
    habitDraft.canSubmit && !isCreatingHabit
  }

  @discardableResult
  public func createDraftHabit() async -> Bool {
    guard canCreateHabitDraft, let targetCount = habitDraft.resolvedTargetCount else {
      return false
    }
    isCreatingHabit = true
    defer { isCreatingHabit = false }
    guard
      await performCanonicalMutation({
        try await core.createHabit(
          name: habitDraft.trimmedName,
          cue: habitDraft.trimmedCue.isEmpty ? nil : habitDraft.trimmedCue,
          icon: habitDraft.icon,
          color: habitDraft.color,
          targetCount: targetCount,
          cadence: habitDraft.cadenceInput,
          milestoneTarget: habitDraft.milestoneTarget
        )
      }) != nil
    else { return false }

    habitDraft = MobileHabitDraft()
    await reconcileAfterCommittedMutation(source: "ios.habit.create.reconcile") {
      habits = try await core.loadHabits(date: logicalTodayString)
    }
    // Republish so the new habit appears in the iOS Habits widget now rather
    // than when the full refresh that the write's change signal starts reaches
    // its own publish.
    await publishMobileSyncSurfaces()
    return true
  }

  public var canUpdateHabitDraft: Bool {
    habitDraft.canSubmit && !isUpdatingHabit
  }

  public func prepareHabitDraft(for habit: LorvexHabit) {
    habitDraft = MobileHabitDraft(habit: habit)
  }

  /// Reset the shared habit draft to its defaults before presenting the create
  /// sheet. `habitDraft` is reused by the edit flow
  /// (``prepareHabitDraft(for:)``), so a create sheet opened after an edit
  /// would otherwise inherit the edited habit's fields.
  public func beginCreateHabitDraft() {
    habitDraft = MobileHabitDraft()
  }

  @discardableResult
  public func updateHabit(_ habit: LorvexHabit) async -> Bool {
    guard canUpdateHabitDraft, let targetCount = habitDraft.resolvedTargetCount else {
      return false
    }
    isUpdatingHabit = true
    defer { isUpdatingHabit = false }
    do {
      // Three-state cue and milestone patches: a non-empty field sets the value;
      // an empty field clears it (blanking a cue or goal in the editor is an
      // explicit "no value", never a silent leave-as-is). The cadence is replaced
      // atomically from the editor selections.
      _ = try await core.updateHabit(
        id: habit.id,
        name: habitDraft.trimmedName,
        cue: habitDraft.trimmedCue.isEmpty ? .clear : .set(habitDraft.trimmedCue),
        color: habitDraft.color,
        icon: habitDraft.icon,
        targetCount: targetCount,
        archived: nil,
        cadence: habitDraft.cadenceInput,
        milestoneTarget: habitDraft.milestoneTarget.map { .set($0) } ?? .clear
      )
      habits = try await core.loadHabits(date: logicalTodayString)
      await refreshHabitDetailIfLoaded(id: habit.id)
      habitDraft = MobileHabitDraft()
      errorMessage = nil
      // A cadence change re-arms a different set of days and a name/icon/color
      // change alters the widget; mirror `mutateHabit`'s tail so the reminder
      // plan and the App-Group snapshot reflect the edit immediately instead of
      // waiting for an unrelated reschedule/refresh.
      await publishMobileSyncSurfaces()
      await rescheduleReminders()
      return true
    } catch {
      await presentUserFacingError(error)
      return false
    }
  }

  @discardableResult
  public func deleteHabit(_ habit: LorvexHabit) async -> Bool {
    guard !isDeletingHabit else { return false }
    isDeletingHabit = true
    defer { isDeletingHabit = false }
    do {
      habits = try await core.deleteHabit(id: habit.id)
      habitDetailsByID[habit.id] = nil
      archivedHabits.removeAll { $0.id == habit.id }
      if selectedHabitID == habit.id {
        selectedHabitID = nil
      }
      errorMessage = nil
      // The deleted habit is gone from the widget snapshot and its armed
      // reminders must be reaped. Do both here, as every other habit mutation
      // does, instead of waiting for the full refresh that the write's change
      // signal starts.
      await publishMobileSyncSurfaces()
      await rescheduleReminders()
      return true
    } catch {
      await presentUserFacingError(error)
      return false
    }
  }

  @discardableResult
  public func deleteHabits(_ ids: [LorvexHabit.ID]) async -> Bool {
    let uniqueIDs = stableUniqueHabitIDs(ids)
    guard !uniqueIDs.isEmpty, !isDeletingHabit else { return false }
    isDeletingHabit = true
    defer { isDeletingHabit = false }

    // Each delete is its own transaction; a mid-batch failure leaves the earlier
    // deletions committed. Stop on the first failure but ALWAYS reconcile the
    // catalog + selection against the store, so a partial batch never leaves the
    // UI showing an already-deleted habit or a selection pointing at one.
    var caught: Error?
    for id in uniqueIDs {
      do {
        habits = try await core.deleteHabit(id: id)
      } catch {
        caught = error
        break
      }
    }

    habits = (try? await core.loadHabits(date: logicalTodayString)) ?? habits
    let liveIDs = Set(habits?.habits.map(\.id) ?? [])
    habitDetailsByID = habitDetailsByID.filter { liveIDs.contains($0.key) }
    if let selectedHabitID, !liveIDs.contains(selectedHabitID) {
      self.selectedHabitID = nil
    }

    // Committed deletions (even on a partial batch) removed habits from the
    // widget and left armed reminders behind; republish and reap here.
    await publishMobileSyncSurfaces()
    await rescheduleReminders()

    if let caught {
      await presentUserFacingError(caught)
      return false
    }
    errorMessage = nil
    return true
  }

  /// Loads the archived habits for the Habits screen's restore section. A
  /// failed read keeps the last list rather than raising an error: the section
  /// is secondary to the active catalog above it.
  public func loadArchivedHabits() async {
    guard let loaded = try? await core.loadArchivedHabits(date: logicalTodayString) else {
      return
    }
    archivedHabits = loaded.habits
    archivedHabitsAreLoaded = true
  }

  /// Re-reads the archived habits once the Habits screen has loaded them, so an
  /// archive, restore, rename, or deletion made elsewhere (the assistant, another
  /// device) shows in the restore section while the screen is open. The screen
  /// itself re-reads them only when the set of active habits changes, which a
  /// rename or a deletion of an archived habit does not do. Before the first load
  /// the list stays unread.
  func reloadArchivedHabitsIfLoaded() async {
    guard archivedHabitsAreLoaded else { return }
    await loadArchivedHabits()
  }

  /// Archives a habit, or restores an archived one. Archiving keeps the habit's
  /// completion history but takes it out of the active catalog, Today, the
  /// widget, and reminder planning; restoring brings all of that back.
  @discardableResult
  public func setHabitArchived(_ habit: LorvexHabit, archived: Bool) async -> Bool {
    await mutateHabit {
      _ = try await core.updateHabit(
        id: habit.id, name: nil, cue: .unset, color: nil, icon: nil, targetCount: nil,
        archived: archived)
      habits = try await core.loadHabits(date: logicalTodayString)
    } afterWrite: {
      if archived {
        habitDetailsByID[habit.id] = nil
        if selectedHabitID == habit.id {
          selectedHabitID = nil
        }
      }
      await loadArchivedHabits()
    }
  }

  /// Authoritatively re-read the habits list for a `.habit` route whose target
  /// isn't in the currently-loaded list — the list hasn't loaded yet (a deep link
  /// or Handoff before the Habits workspace appeared) or the habit was added
  /// out-of-band (an in-process intent / MCP write) since the last load. Returns
  /// whether the read succeeded; on a transient failure it keeps the last-good
  /// list so the route can stay on its skeleton and recover on the next refresh
  /// rather than showing a false "Habit Not Found". Later peer/MCP additions also
  /// arrive through the observed `habits` state, which the route reads directly.
  @discardableResult
  public func reloadHabitsForRoute() async -> Bool {
    guard let loaded = try? await core.loadHabits(date: logicalTodayString) else { return false }
    habits = loaded
    return true
  }

  @discardableResult
  public func loadHabitDetail(id: LorvexHabit.ID) async -> Bool {
    do {
      let to = logicalTodayString
      let from = habitDetailStartDateString(endingAt: to)
      async let completions = core.getHabitCompletions(id: id, from: from, to: to, limit: 400)
      async let stats = core.getHabitStats(id: id)
      async let policies = core.getHabitReminderPolicies(id: id)
      habitDetailsByID[id] = HabitDetail(
        completions: try await completions,
        stats: try await stats,
        reminderPolicies: try await policies
      )
      errorMessage = nil
      return true
    } catch {
      await presentUserFacingError(error)
      return false
    }
  }

  private func refreshHabitDetailIfLoaded(id: LorvexHabit.ID) async {
    guard habitDetailsByID[id] != nil else { return }
    _ = await loadHabitDetail(id: id)
  }

  private func refreshLoadedHabitDetails(ids: [LorvexHabit.ID]) async {
    for id in ids where habitDetailsByID[id] != nil {
      _ = await loadHabitDetail(id: id)
    }
  }

  private func habitDetailStartDateString(endingAt dayString: String) -> String {
    let heatmapDays = 16 * 7
    return LorvexDateFormatters.ymdUTCAddingDays(dayString, days: -heatmapDays) ?? dayString
  }

  /// Runs one habit write and returns whether it committed.
  ///
  /// ``isMutatingHabit`` is held for `operation`, the write and the snapshot read
  /// that shows it, and for `afterWrite`, the work that shows the result:
  /// feedback, the milestone check, and the detail reads. The two run back to
  /// back, so the milestone stamp on `habits` is still the write's own when
  /// `afterWrite` reads it.
  ///
  /// The flag is released before the best-effort surfaces. The App-Group
  /// snapshot is republished so the Habits widget shows the completion, and the
  /// reminder plan is rebuilt so a done habit stops nudging and a cadence change
  /// re-arms the right days. Both go through ``habitSurfacesFlight``, so a tap
  /// is never dropped behind them and overlapping writes share one trailing pass
  /// rather than re-planning the reminders in parallel. The call returns once a
  /// pass that saw its write has finished.
  @discardableResult
  private func mutateHabit(
    _ operation: () async throws -> Void,
    afterWrite: () async -> Void = {}
  ) async -> Bool {
    guard await commitHabitWrite(operation, afterWrite: afterWrite) else { return false }
    await habitSurfacesFlight.run {
      await publishMobileSyncSurfaces()
      await rescheduleReminders()
    }
    return true
  }

  /// The guarded part of ``mutateHabit(_:afterWrite:)``: false when another habit
  /// write holds the flag, or when `operation` throws, which presents the error.
  private func commitHabitWrite(
    _ operation: () async throws -> Void,
    afterWrite: () async -> Void
  ) async -> Bool {
    guard !isMutatingHabit else { return false }
    isMutatingHabit = true
    defer { isMutatingHabit = false }
    do {
      try await operation()
    } catch {
      await presentUserFacingError(error)
      return false
    }
    errorMessage = nil
    invalidateHabitDetailViews()
    await afterWrite()
    return true
  }

  private func stableUniqueHabitIDs(_ ids: [LorvexHabit.ID]) -> [LorvexHabit.ID] {
    var seen = Set<LorvexHabit.ID>()
    return ids.filter { seen.insert($0).inserted }
  }
}

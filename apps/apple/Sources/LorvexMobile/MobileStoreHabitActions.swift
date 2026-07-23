import Foundation
import LorvexCore

extension MobileStore {
  @discardableResult
  public func completeHabit(_ habit: LorvexHabit) async -> Bool {
    let succeeded = await mutateHabit {
      habits = try await core.completeHabit(id: habit.id, date: logicalTodayString)
    }
    if succeeded {
      await refreshHabitDetailIfLoaded(id: habit.id)
      // A crossing plays the celebratory milestone feedback (and stages the
      // badge) in place of the ordinary completion note, so a single crisp haptic
      // marks the moment rather than two success taps in a row.
      if !stageMilestoneCelebrationIfReached(habitID: habit.id) {
        feedbackProvider.playFeedback(.habitCompleted)
      }
    }
    return succeeded
  }

  @discardableResult
  public func uncompleteHabit(_ habit: LorvexHabit) async -> Bool {
    let succeeded = await mutateHabit {
      habits = try await core.uncompleteHabit(id: habit.id, date: logicalTodayString)
    }
    if succeeded {
      await refreshHabitDetailIfLoaded(id: habit.id)
    }
    if succeeded {
      feedbackProvider.playFeedback(.habitReset)
    }
    return succeeded
  }

  @discardableResult
  public func completeHabits(_ ids: [LorvexHabit.ID]) async -> Bool {
    let uniqueIDs = stableUniqueHabitIDs(ids)
    guard !uniqueIDs.isEmpty else { return false }
    let succeeded = await mutateHabit {
      habits = try await core.batchCompleteHabits(ids: uniqueIDs, date: logicalTodayString)
    }
    if succeeded {
      await refreshLoadedHabitDetails(ids: uniqueIDs)
      // A batch can cross several milestones at once; celebrate the most
      // significant crossing (largest reached value) rather than dropping every
      // one, mirroring the single-complete paths. When nothing crossed, the
      // ordinary completion feedback stands in for the batch.
      if let mostSignificant = mostSignificantMilestoneCrossing(among: uniqueIDs) {
        _ = stageMilestoneCelebrationIfReached(habitID: mostSignificant)
      } else {
        feedbackProvider.playFeedback(.habitCompleted)
      }
    }
    return succeeded
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
    let succeeded = await mutateHabit {
      for id in uniqueIDs {
        habits = try await core.uncompleteHabit(id: id, date: date)
      }
    }
    if succeeded {
      await refreshLoadedHabitDetails(ids: uniqueIDs)
    }
    if succeeded {
      feedbackProvider.playFeedback(.habitReset)
    }
    return succeeded
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
      // Three-state milestone patch: a positive field sets the goal; an empty or
      // invalid field clears any existing goal (an optional personal target, so
      // blanking it is an explicit "no goal", never a silent leave-as-is). The
      // cadence is replaced atomically from the editor selections.
      _ = try await core.updateHabit(
        id: habit.id,
        name: habitDraft.trimmedName,
        cue: habitDraft.trimmedCue.isEmpty ? nil : habitDraft.trimmedCue,
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
      if selectedHabitID == habit.id {
        selectedHabitID = nil
      }
      errorMessage = nil
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

    if let caught {
      await presentUserFacingError(caught)
      return false
    }
    errorMessage = nil
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

  @discardableResult
  private func mutateHabit(_ operation: () async throws -> Void) async -> Bool {
    guard !isMutatingHabit else { return false }
    isMutatingHabit = true
    defer { isMutatingHabit = false }
    do {
      try await operation()
      invalidateHabitDetailViews()
      // Republish the App-Group snapshot so the iOS Habits widget reflects the
      // completion immediately, mirroring the task mutation path. Without this
      // the widget stayed stale until the next full refresh.
      await publishMobileSyncSurfaces()
      errorMessage = nil
      return true
    } catch {
      await presentUserFacingError(error)
      return false
    }
  }

  private func stableUniqueHabitIDs(_ ids: [LorvexHabit.ID]) -> [LorvexHabit.ID] {
    var seen = Set<LorvexHabit.ID>()
    return ids.filter { seen.insert($0).inserted }
  }
}

import Foundation
import LorvexCore

extension AppStore {
  var draftHabitTargetCountIsValid: Bool {
    parsedDraftHabitTargetCount != nil
  }

  /// Whether an invalid per-day target count should block confirming the habit
  /// create/edit sheet. The target field is shown — and parsed into
  /// `target_count` — only for Daily and Weekly-specific-days cadences;
  /// `timesPerWeek` and `monthly` hide it and pin the count to 1, so a stale
  /// invalid value there must not silently disable Save/Create with no visible
  /// cause.
  var draftHabitTargetCountBlocksConfirm: Bool {
    guard draftHabitCadenceMode != .timesPerWeek, draftHabitCadenceMode != .monthly else {
      return false
    }
    return !draftHabitTargetCountIsValid
  }

  var parsedDraftHabitTargetCount: Int? {
    let text = draftHabitTargetCountText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let value = Int(text), value > 0 else { return nil }
    return value
  }

  func prepareHabitDraft(for habit: LorvexHabit) {
    draftHabitName = habit.name
    draftHabitCue = habit.cue ?? ""
    draftHabitTargetCountText = "\(habit.targetCount)"
    draftHabitMilestoneTargetText = habit.milestoneTarget.map { "\($0)" } ?? ""
    applyCadenceDraft(from: habit)
    draftHabitIcon = habit.icon
    draftHabitColor = habit.color
  }

  /// Reset the shared habit draft to its defaults before presenting the create
  /// sheet. The draft fields are reused by the edit flow
  /// (``prepareHabitDraft(for:)``), so a create sheet opened after an edit
  /// would otherwise inherit the edited habit's fields.
  func beginCreateHabitDraft() {
    resetHabitDraft()
  }

  func createDraftHabit() async {
    // Guard against a double Return/click during the create round-trip (write +
    // Spotlight reindex + sync), which would otherwise create duplicate habits.
    guard !draftHabitTargetCountBlocksConfirm, !isCreating else { return }
    isCreating = true
    defer { isCreating = false }
    let reminderTimes = draftHabitReminderTimes
    let draft = draftHabitCadenceInput()
    guard
      await performCanonicalMutation({
        try await core.createHabit(
          name: draftHabitName.trimmingCharacters(in: .whitespacesAndNewlines),
          cue: draftHabitCue.trimmedNilIfEmpty,
          icon: draftHabitIcon,
          color: draftHabitColor,
          targetCount: draft.targetCount,
          cadence: draft.cadence,
          milestoneTarget: parsedDraftHabitMilestoneTarget,
          reminderTimes: reminderTimes
        )
      }) != nil
    else { return }

    resetHabitDraft()
    selection = .habits
    await reconcileAfterCommittedMutation(source: "macos.habit.create.reconcile") {
      habits = try await core.loadHabits(date: logicalTodayDateString)
    }
    await loadAllHabitStats()
    if !reminderTimes.isEmpty { await rescheduleHabitReminders() }
  }

  func updateHabit(_ habit: LorvexHabit) async {
    guard !draftHabitTargetCountBlocksConfirm, !isCreating else { return }
    isCreating = true
    defer { isCreating = false }
    await perform {
      let name = draftHabitName.trimmingCharacters(in: .whitespacesAndNewlines)
      // The editor reflects the habit's full cadence (specific weekdays, a
      // per-week count, or a monthly day), pre-filled by `applyCadenceDraft`, so
      // writing it back verbatim is faithful — no clobbering of a cadence
      // authored elsewhere.
      let draft = draftHabitCadenceInput()
      // Three-state milestone patch: a positive field sets the goal; an empty or
      // invalid field clears any existing goal (an optional personal target, so
      // blanking it is an explicit "no goal", never a silent leave-as-is).
      _ = try await core.updateHabit(
        id: habit.id,
        name: name,
        cue: draftHabitCue.trimmedNilIfEmpty,
        color: draftHabitColor,
        icon: draftHabitIcon,
        targetCount: draft.targetCount,
        archived: nil,
        cadence: draft.cadence,
        milestoneTarget: parsedDraftHabitMilestoneTarget.map { .set($0) } ?? .clear
      )
      habits = try await core.loadHabits(date: logicalTodayDateString)
      await loadAllHabitStats()
      // Keep an open habit inspector's stats/streak in sync with the edit.
      await refreshHabitDetailIfLoaded(id: habit.id)
      resetHabitDraft()
      selection = .habits
    }
  }

  private func resetHabitDraft() {
    draftHabitName = ""
    draftHabitCue = ""
    draftHabitTargetCountText = "1"
    draftHabitMilestoneTargetText = ""
    draftHabitCadenceMode = .daily
    draftHabitWeekdays = [0, 2, 4]
    draftHabitTimesPerWeek = 3
    draftHabitDayOfMonth = 1
    draftHabitIcon = nil
    draftHabitColor = nil
    draftHabitReminderTimes = []
  }

  /// Archived habits (hidden from the active catalog), surfaced by the Habits
  /// workspace's restore section.
  var archivedHabits: [LorvexHabit] {
    habitsStorage.archivedHabits
  }

  /// Load the archived-habit list for the restore surface. Called when the
  /// Habits workspace appears and refreshed after any archive/restore/delete.
  func loadArchivedHabits() async {
    await perform {
      habitsStorage.archivedHabits =
        try await core.loadArchivedHabits(date: logicalTodayDateString).habits
    }
  }

  /// Real stats for a habit's card (nil until `loadAllHabitStats` runs).
  func habitStats(for id: LorvexHabit.ID) -> HabitStats? {
    habitsStorage.habitStatsByID[id]
  }

  /// Load real per-habit stats for every active habit so cards show real streaks
  /// and recent activity rather than estimates. Sequential (habits are few) and
  /// MainActor-safe; a per-habit failure just leaves that card without stats.
  func loadAllHabitStats() async {
    guard let habits = habits?.habits else { return }
    var stats: [LorvexHabit.ID: HabitStats] = [:]
    for habit in habits {
      if let entry = try? await core.getHabitStats(id: habit.id) {
        stats[habit.id] = entry
      }
    }
    habitsStorage.habitStatsByID = stats
  }

  func deleteHabit(_ habit: LorvexHabit) async {
    await perform {
      habits = try await core.deleteHabit(id: habit.id)
      await loadAllHabitStats()
      // A delete can target an archived habit (from the restore section), so keep
      // that list in sync too.
      await loadArchivedHabits()
      // Close the inspector if it was showing the deleted habit, so it doesn't
      // linger on a "Habit Not Found" placeholder.
      if selectedHabitID == habit.id {
        selectedHabitID = nil
      }
    }
  }

  /// Archive (hide, preserving history) or restore a habit. Archived habits drop
  /// out of the active catalog, so the inspector closes if it was showing one.
  func setHabitArchived(_ habit: LorvexHabit, archived: Bool) async {
    await perform {
      _ = try await core.updateHabit(
        id: habit.id, name: nil, cue: nil, color: nil, icon: nil, targetCount: nil,
        archived: archived)
      habits = try await core.loadHabits(date: logicalTodayDateString)
      await loadAllHabitStats()
      // The habit moved between the active and archived lists; refresh the latter
      // so the restore section reflects it.
      await loadArchivedHabits()
      if archived, selectedHabitID == habit.id {
        selectedHabitID = nil
      }
    }
  }

  func completeHabit(_ habit: LorvexHabit) async {
    do {
      let updatedHabits = try await core.completeHabit(id: habit.id, date: logicalTodayDateString)
      lorvexAnimated(.snappy(duration: 0.18)) {
        habits = updatedHabits
      }
      feedbackProvider.playFeedback(.habitCompleted)
      celebrateMilestoneIfReached(habit, updated: updatedHabits)
      errorMessage = nil
      await refreshHabitDetailIfLoaded(id: habit.id)
      await loadAllHabitStats()
      await republishSurfacesAfterLocalMutation()
    } catch {
      await presentUserFacingError(error)
    }
  }

  func uncompleteHabit(_ habit: LorvexHabit) async {
    do {
      let updatedHabits = try await core.uncompleteHabit(id: habit.id, date: logicalTodayDateString)
      lorvexAnimated(.snappy(duration: 0.18)) {
        habits = updatedHabits
      }
      feedbackProvider.playFeedback(.habitReset)
      errorMessage = nil
      await refreshHabitDetailIfLoaded(id: habit.id)
      await loadAllHabitStats()
      await republishSurfacesAfterLocalMutation()
    } catch {
      await presentUserFacingError(error)
    }
  }

  /// Bump today's completion count for a habit by `delta` (e.g. +1/−1 on the
  /// accumulative stepper), clamped to `[0, target_count]` by the core. `delta
  /// == 0` toggles the day. Backs the card's per-step controls so an
  /// accumulative habit can be corrected down without wiping the whole day.
  func adjustHabitCompletion(_ habit: LorvexHabit, delta: Int) async {
    do {
      let updatedHabits = try await core.adjustHabitCompletion(
        id: habit.id, date: logicalTodayDateString, delta: delta)
      lorvexAnimated(.snappy(duration: 0.18)) {
        habits = updatedHabits
      }
      // The card ring / stepper checks a habit in through the adjust path, which
      // the core does not stamp with `justReached`; the helper falls back to a
      // currentMilestone increase so crossing a milestone here still celebrates.
      celebrateMilestoneIfReached(habit, updated: updatedHabits)
      errorMessage = nil
      await refreshHabitDetailIfLoaded(id: habit.id)
      await loadAllHabitStats()
      await republishSurfacesAfterLocalMutation()
    } catch {
      await presentUserFacingError(error)
    }
  }

  /// Load completion history + stats for a habit and cache it for the heatmap.
  /// Composes the existing `getHabitCompletions` and `getHabitStats` servicing
  /// reads; a year of history is requested so the heatmap window is fully
  /// covered. No-ops the cache on error and surfaces the message.
  func loadHabitDetail(id: LorvexHabit.ID) async {
    await perform {
      let to = logicalTodayDateString
      let from = LorvexDateFormatters.ymdUTCAddingDays(to, days: -370) ?? to
      // A year-plus window has at most ~371 daily rows; the bound guards against
      // pathological data while covering the full heatmap window.
      async let completions = core.getHabitCompletions(
        id: id, from: from, to: to, limit: 400)
      async let stats = core.getHabitStats(id: id)
      async let policies = core.getHabitReminderPolicies(id: id)
      habitsStorage.detailsByHabitID[id] = HabitDetail(
        completions: try await completions,
        stats: try await stats,
        reminderPolicies: try await policies
      )
    }
  }

  private func refreshHabitDetailIfLoaded(id: LorvexHabit.ID) async {
    guard habitsStorage.detailsByHabitID[id] != nil else { return }
    await loadHabitDetail(id: id)
  }

  // MARK: - Reminder policies

  /// Add a reminder time ("HH:mm") to a habit. Creates a new enabled policy via
  /// the core's upsert (each `(habit, time)` pair is one policy), reloads the
  /// habit's detail so the editor reflects the new chip, and re-plans the
  /// notification schedule. A duplicate time is a no-op the core upsert dedupes.
  func addHabitReminder(habitID: LorvexHabit.ID, time: String) async {
    await perform {
      _ = try await core.upsertHabitReminderPolicy(
        id: habitID, policy: Self.newReminderPolicy(habitID: habitID, time: time))
      await loadHabitDetail(id: habitID)
      await rescheduleHabitReminders()
    }
  }

  /// Remove a single reminder policy, reload its habit's detail, and re-plan the
  /// schedule. `habitID` lets the reload target the right habit without a lookup.
  func removeHabitReminder(habitID: LorvexHabit.ID, policyID: String) async {
    await perform {
      _ = try await core.deleteHabitReminderPolicy(policyID: policyID)
      await loadHabitDetail(id: habitID)
      await rescheduleHabitReminders()
    }
  }

  /// Retime an existing reminder policy in place, keeping its enabled flag. Skips
  /// the write when `time` collides with another of the habit's reminders (the
  /// core would reject the duplicate slot), so retiming onto a taken time is a
  /// no-op rather than a surfaced error. Reloads detail + reschedules.
  func setHabitReminderTime(
    policy: HabitReminderPolicy, to time: String, in policies: [HabitReminderPolicy]
  ) async {
    guard time != policy.reminderTime else { return }
    guard !policies.contains(where: { $0.id != policy.id && $0.reminderTime == time }) else {
      return
    }
    await perform {
      var retimed = policy
      retimed.reminderTime = time
      _ = try await core.upsertHabitReminderPolicy(id: policy.habitID, policy: retimed)
      await loadHabitDetail(id: policy.habitID)
      await rescheduleHabitReminders()
    }
  }

  /// Flip a reminder policy's enabled flag (a disabled policy stays set but is
  /// skipped by the scheduler), keeping the same time. Reloads detail + reschedules.
  func toggleHabitReminderEnabled(policy: HabitReminderPolicy) async {
    await perform {
      var flipped = policy
      flipped.enabled.toggle()
      _ = try await core.upsertHabitReminderPolicy(id: policy.habitID, policy: flipped)
      await loadHabitDetail(id: policy.habitID)
      await rescheduleHabitReminders()
    }
  }

  /// Reconcile a habit's reminder policies to exactly `times` ("HH:mm"): delete
  /// policies whose time is no longer wanted and add an enabled policy for each
  /// new time, leaving unchanged times (and their enabled flag) intact. Backs the
  /// "throughout the day" generator, which rewrites the whole set at once.
  func setHabitReminderTimes(habitID: LorvexHabit.ID, times: [String]) async {
    await perform {
      let existing = try await core.getHabitReminderPolicies(id: habitID)
      let target = Set(times)
      let current = Set(existing.map(\.reminderTime))
      for policy in existing where !target.contains(policy.reminderTime) {
        _ = try await core.deleteHabitReminderPolicy(policyID: policy.id)
      }
      for time in target.subtracting(current) {
        _ = try await core.upsertHabitReminderPolicy(
          id: habitID, policy: Self.newReminderPolicy(habitID: habitID, time: time))
      }
      await loadHabitDetail(id: habitID)
      await rescheduleHabitReminders()
    }
  }

  /// A fresh enabled policy for `time`; the core fills `id`/`habitName`/timestamps.
  private static func newReminderPolicy(habitID: LorvexHabit.ID, time: String)
    -> HabitReminderPolicy
  {
    HabitReminderPolicy(
      id: "", habitID: habitID, habitName: "", reminderTime: time, enabled: true,
      createdAt: "", updatedAt: "")
  }
}

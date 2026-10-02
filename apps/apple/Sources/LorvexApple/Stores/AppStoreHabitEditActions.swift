import Foundation
import LorvexCore
import LorvexDomain

extension AppStore {
  /// Writes the given changes to a saved habit and leaves every field not
  /// passed as stored, so an edit made in the habit inspector never rewrites a
  /// field that another device or the assistant changed in the meantime.
  ///
  /// `name` nil and the `.unset` patches leave their field alone. For `icon`
  /// and `color`, `.clear` restores the default glyph or the per-habit hue;
  /// for `cue` and `milestoneTarget` it removes the encouragement or the goal.
  /// A `cadence` replaces the whole rhythm, and `targetCount` is the per-day
  /// count. A failure (an empty name, for one) shows as the app's error
  /// message and leaves the habit as it was. After the write commits, the
  /// habits, their stats, and an open inspector's detail reload, the habit
  /// reminders are planned again (their text carries the name, and the
  /// cadence picks their days), and the widgets and sync pick up the change.
  func updateHabitFields(
    _ habit: LorvexHabit,
    name: String? = nil,
    cue: Patch<String> = .unset,
    icon: Patch<String> = .unset,
    color: Patch<String> = .unset,
    targetCount: Int? = nil,
    cadence: HabitCadenceInput? = nil,
    milestoneTarget: Patch<Int> = .unset
  ) async {
    guard
      await performCanonicalMutation({
        try await core.updateHabit(
          id: habit.id,
          name: name,
          cue: cue,
          color: Self.coreAppearanceValue(color),
          icon: Self.coreAppearanceValue(icon),
          targetCount: targetCount,
          archived: nil,
          cadence: cadence,
          milestoneTarget: milestoneTarget
        )
      }) != nil
    else { return }
    await reconcileAfterCommittedMutation(source: "macos.habit.update.reconcile") {
      habits = try await core.loadHabits(date: logicalTodayDateString)
    }
    await loadAllHabitStats()
    await refreshHabitDetailIfLoaded(id: habit.id)
    await rescheduleHabitReminders()
    await republishSurfacesAfterLocalMutation()
  }

  /// Loads `habit`'s rhythm (its cadence and per-day count) into the habit
  /// draft, which the cadence editor binds to. The inspector's Repeat editor
  /// calls it as it opens; the draft's other fields are left as they are.
  func prepareHabitRhythmDraft(for habit: LorvexHabit) {
    draftHabitTargetCountText = "\(habit.targetCount)"
    applyCadenceDraft(from: habit)
  }

  /// Saves the rhythm the habit draft holds — the cadence and the per-day
  /// count, as ``draftHabitCadenceInput()`` assembles them — to `habit`,
  /// leaving its other fields as stored. A per-day count that does not parse
  /// saves nothing.
  func saveHabitRhythmDraft(_ habit: LorvexHabit) async {
    guard !draftHabitTargetCountBlocksConfirm else { return }
    let draft = draftHabitCadenceInput()
    await updateHabitFields(habit, targetCount: draft.targetCount, cadence: draft.cadence)
  }

  /// The core's `icon` / `color` argument for an appearance patch: the value
  /// to set, an empty string to clear (which the core stores as no value), or
  /// nil to leave the stored value alone.
  private static func coreAppearanceValue(_ patch: Patch<String>) -> String? {
    switch patch {
    case .unset: nil
    case .clear: ""
    case .set(let value): value
    }
  }
}

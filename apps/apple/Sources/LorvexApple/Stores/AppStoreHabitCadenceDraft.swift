import Foundation
import LorvexCore

/// The habit create/edit draft's cadence-editor mode. Distinct from the
/// `HabitCadenceInput.frequencyType` wire string (`"daily"` / `"weekly"` /
/// `"times_per_week"` / `"monthly"`, snake_case for the multi-word case): this
/// enum is the in-memory UI selection driving ``HabitCadenceEditor`` and
/// ``HabitFormFields``, with `timesPerWeek` spelled camelCase because it never
/// round-trips through the wire — ``AppStore/draftHabitCadenceInput()`` maps it
/// to the wire string on save.
enum HabitCadenceMode: String, CaseIterable, Sendable {
  case daily
  case weekly
  case timesPerWeek
  case monthly
}

/// Bridges the habit create/edit draft fields to the typed ``HabitCadenceInput``
/// + `targetCount`: parses an existing habit's cadence into the editor fields,
/// and assembles the editor's choices back into the typed cadence. Weekdays are
/// Monday-first raw values (0 = Mon … 6 = Sun) throughout.
extension AppStore {
  /// Load a stored habit's cadence into the draft editor fields, mapping each
  /// cadence onto one of the four editor modes. A weekly habit with no pinned
  /// days collapses to `daily` (every day).
  func applyCadenceDraft(from habit: LorvexHabit) {
    switch habit.frequencyType {
    case "weekly":
      if let days = habit.weekdays, !days.isEmpty {
        draftHabitCadenceMode = .weekly
        draftHabitWeekdays = Set(days)
      } else {
        draftHabitCadenceMode = .daily
      }
    case "times_per_week":
      draftHabitCadenceMode = .timesPerWeek
      let stored = habit.perPeriodTarget ?? Int(habit.targetCount)
      draftHabitTimesPerWeek = min(max(stored, 1), 7)
    case "monthly":
      draftHabitCadenceMode = .monthly
      draftHabitDayOfMonth = min(max(habit.dayOfMonth ?? 1, 1), 31)
    default:
      draftHabitCadenceMode = .daily
    }
  }

  /// Assemble the draft cadence fields into a typed ``HabitCadenceInput`` and the
  /// per-day `targetCount`. `timesPerWeek` (its count lives in `perPeriodTarget`)
  /// and `monthly` (a single check-in on a chosen day) both pin `targetCount` to
  /// 1; an empty weekday set degrades to `daily`.
  func draftHabitCadenceInput() -> (cadence: HabitCadenceInput, targetCount: Int) {
    let target = parsedDraftHabitTargetCount ?? 1
    switch draftHabitCadenceMode {
    case .weekly:
      let days = draftHabitWeekdays.filter { (0...6).contains($0) }.sorted()
      guard !days.isEmpty else {
        return (HabitCadenceInput(frequencyType: "daily"), target)
      }
      return (HabitCadenceInput(frequencyType: "weekly", weekdays: days), target)
    case .timesPerWeek:
      let n = min(max(draftHabitTimesPerWeek, 1), 7)
      return (HabitCadenceInput(frequencyType: "times_per_week", perPeriodTarget: n), 1)
    case .monthly:
      let day = min(max(draftHabitDayOfMonth, 1), 31)
      return (HabitCadenceInput(frequencyType: "monthly", dayOfMonth: day), 1)
    case .daily:
      return (HabitCadenceInput(frequencyType: "daily"), target)
    }
  }
}

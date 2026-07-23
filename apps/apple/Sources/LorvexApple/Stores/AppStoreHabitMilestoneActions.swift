import Foundation
import LorvexCore

/// Milestone-goal draft parsing and the completion-driven milestone celebration,
/// kept separate from the core habit CRUD/completion actions.
extension AppStore {
  /// The optional milestone goal parsed from the draft field: a positive integer,
  /// or nil when the field is empty or not a positive number (an optional
  /// personal goal, so a blank / invalid field simply means "no goal").
  var parsedDraftHabitMilestoneTarget: Int? {
    let text = draftHabitMilestoneTargetText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let value = Int(text), value > 0 else { return nil }
    return value
  }

  /// Fire a milestone celebration when `updated` shows `before` just crossed a
  /// milestone. Prefers the authoritative `justReached` (stamped by
  /// `completeHabit`); falls back to a `currentMilestone` increase for the adjust
  /// path (the card ring / accumulative stepper, which the core does not stamp).
  /// A completion that crosses nothing does nothing.
  func celebrateMilestoneIfReached(_ before: LorvexHabit, updated: HabitCatalogSnapshot) {
    guard let after = updated.habits.first(where: { $0.id == before.id }),
      let info = after.milestone
    else { return }
    let reached: Int?
    if let justReached = info.justReached {
      reached = justReached
    } else if let current = info.currentMilestone,
      current > (before.milestone?.currentMilestone ?? 0)
    {
      reached = current
    } else {
      reached = nil
    }
    guard let reached else { return }
    feedbackProvider.playFeedback(.habitMilestoneReached)
    lorvexAnimated(.spring(response: 0.42, dampingFraction: 0.62)) {
      milestoneCelebration = HabitMilestoneCelebration(
        habitName: after.name,
        milestone: reached,
        metric: info.metric,
        frequencyType: after.frequencyType,
        tint: LorvexHabitPalette.baseColor(for: after))
    }
  }
}

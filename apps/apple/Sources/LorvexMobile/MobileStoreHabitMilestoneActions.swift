import LorvexCore
import SwiftUI

extension MobileStore {
  /// Stage a milestone celebration when the just-completed habit crossed a
  /// waypoint. Reads the authoritative `justReached` stamped by the completion op
  /// on the refreshed `habits` snapshot; plays the celebratory feedback and
  /// springs the badge in. Returns whether a celebration was staged so the caller
  /// can fall back to the ordinary completion feedback when nothing was crossed.
  @discardableResult
  func stageMilestoneCelebrationIfReached(habitID: LorvexHabit.ID) -> Bool {
    guard let habit = habits?.habits.first(where: { $0.id == habitID }),
      let info = habit.milestone, let reached = info.justReached
    else { return false }
    feedbackProvider.playFeedback(.habitMilestoneReached)
    withAnimation(.spring(response: 0.42, dampingFraction: 0.62)) {
      milestoneCelebration = MobileHabitMilestoneCelebration(
        habitName: habit.name,
        milestone: reached,
        metric: info.metric,
        frequencyType: habit.frequencyType,
        tint: habit.tileTint)
    }
    return true
  }
}

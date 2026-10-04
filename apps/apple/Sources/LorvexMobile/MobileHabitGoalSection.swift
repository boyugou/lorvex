import LorvexCore
import SwiftUI

/// The goal section of the create and edit habit sheets: how many check-ins
/// complete a day, as a stepper row that reads as a sentence ("Once a day",
/// "3 times a day"). It appears only for the cadences that count per day
/// (``MobileHabitDraft/showsPerDayTarget``); a count-per-week or monthly habit
/// carries its target in its cadence. The stepper edits
/// ``MobileHabitDraft/perDayTarget`` and its row is `<idPrefix>.targetCount`.
struct MobileHabitGoalSection: View {
  @Binding var draft: MobileHabitDraft
  let idPrefix: String

  var body: some View {
    if draft.showsPerDayTarget {
      Section(
        String(
          localized: "habits.section.goal", defaultValue: "Goal", table: "Localizable",
          bundle: MobileL10n.bundle)
      ) {
        Stepper(value: $draft.perDayTarget, in: 1...99) {
          Text(
            String(
              localized: "habits.goal.times_per_day_value",
              defaultValue: "\(draft.perDayTarget) times a day",
              table: "Localizable", bundle: MobileL10n.bundle))
        }
        .accessibilityIdentifier("\(idPrefix).targetCount")
      }
    }
  }
}

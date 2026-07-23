import LorvexCore
import SwiftUI

/// The optional milestone-goal form section shared by the create and edit habit
/// sheets: a clearable numeric field labeled as an optional personal goal that
/// the habit continues past, with a cadence-aware hint. Writes the typed value
/// into the draft's `milestoneTargetText`, which the store threads to the core
/// as a positive `Int?` on create and a `.set` / `.clear` patch on update.
struct MobileHabitMilestoneGoalField: View {
  @Binding var text: String
  /// The habit's cadence wire string, selecting the streak-length vs completion-
  /// count phrasing of the hint. Create is always a daily (streak) habit.
  let frequencyType: String
  let idPrefix: String

  var body: some View {
    Section {
      HStack(spacing: LorvexDesign.Spacing.s) {
        TextField(
          String(localized: "habits.sheet.field.milestone_goal_placeholder", defaultValue: "None", table: "Localizable", bundle: MobileL10n.bundle),
          text: $text
        )
        #if os(iOS) || os(visionOS)
          .keyboardType(.numberPad)
        #endif
        .mobileKeyboardDoneToolbar()
        .accessibilityIdentifier("\(idPrefix).milestoneTarget")

        if !text.isEmpty {
          Button {
            text = ""
          } label: {
            Image(systemName: "xmark.circle.fill")
              .foregroundStyle(.secondary)
          }
          .buttonStyle(.borderless)
          .accessibilityLabel(
            String(localized: "habits.sheet.field.milestone_goal_clear", defaultValue: "Clear milestone goal", table: "Localizable", bundle: MobileL10n.bundle))
          .accessibilityIdentifier("\(idPrefix).milestoneTarget.clear")
        }
      }
    } header: {
      Text(String(localized: "habits.sheet.field.milestone_goal", defaultValue: "Milestone goal", table: "Localizable", bundle: MobileL10n.bundle))
    } footer: {
      Text(MobileHabitDisplayText.milestoneGoalHint(frequencyType: frequencyType))
    }
  }
}

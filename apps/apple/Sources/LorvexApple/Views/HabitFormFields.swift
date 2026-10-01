import LorvexCore
import SwiftUI

/// The top of the create and edit habit sheets: the habit's icon tile and
/// name (``CreationSheetHeader``), with the encouragement typed on the line
/// under the name.
struct HabitSheetHeader: View {
  @Bindable var store: AppStore
  let idPrefix: String

  var body: some View {
    CreationSheetHeader(
      icon: $store.draftHabitIcon,
      color: $store.draftHabitColor,
      name: $store.draftHabitName,
      defaultIcon: "repeat.circle",
      namePrompt: String(
        localized: "habits.sheet.field.name_prompt", defaultValue: "Habit name", table: "Localizable",
        bundle: LorvexL10n.bundle),
      nameAccessibilityLabel: String(
        localized: "habits.sheet.field.name_a11y", defaultValue: "Habit name", table: "Localizable",
        bundle: LorvexL10n.bundle),
      idPrefix: idPrefix
    ) {
      // "Encouragement", not "Cue": a motivating line shown on the habit, not a
      // when-to-do trigger. The storage column stays `cue`.
      TextField(
        String(
          localized: "habits.sheet.field.encouragement_prompt", defaultValue: "Add an encouraging line",
          table: "Localizable", bundle: LorvexL10n.bundle),
        text: $store.draftHabitCue
      )
      .font(LorvexDesign.Typography.secondaryText)
      .foregroundStyle(.secondary)
      .textFieldStyle(.plain)
      .accessibilityLabel(String(
        localized: "habits.sheet.field.encouragement_a11y", defaultValue: "Habit encouragement",
        table: "Localizable", bundle: LorvexL10n.bundle))
      .accessibilityIdentifier("\(idPrefix).cue")
    }
  }
}

/// The rhythm of a habit as grouped form sections, shared by the create and
/// edit habit sheets: the frequency, the check-ins that complete a day (for
/// the cadences that count per day), and the optional milestone to celebrate.
struct HabitFormSections: View {
  @Bindable var store: AppStore
  let idPrefix: String

  var body: some View {
    Section {
      HabitCadenceEditor(store: store, idPrefix: idPrefix)
      // "Times a week" owns its count in its own stepper, and monthly is one
      // check-in on a chosen day, so neither shows a per-day count.
      if store.draftHabitCadenceMode != .timesPerWeek && store.draftHabitCadenceMode != .monthly {
        LabeledContent(
          String(
            localized: "habits.sheet.field.target_times_per_day", defaultValue: "Times per day",
            table: "Localizable", bundle: LorvexL10n.bundle)
        ) {
          HStack(spacing: LorvexDesign.Spacing.s) {
            Text("\(targetCount.wrappedValue)")
              .monospacedDigit()
            Stepper(
              String(
                localized: "habits.sheet.field.target_times_per_day", defaultValue: "Times per day",
                table: "Localizable", bundle: LorvexL10n.bundle),
              value: targetCount, in: 1...99
            )
            .labelsHidden()
          }
        }
        .accessibilityIdentifier("\(idPrefix).targetCount")
      }
    } header: {
      Text(LocalizedStringResource(
        "habits.sheet.field.frequency", defaultValue: "Frequency", table: "Localizable",
        bundle: LorvexL10n.bundle))
    }

    Section {
      LabeledContent(
        String(
          localized: "habits.sheet.field.milestone_goal", defaultValue: "Celebrate after",
          table: "Localizable", bundle: LorvexL10n.bundle)
      ) {
        TextField(
          String(
            localized: "habits.sheet.field.milestone_goal_none", defaultValue: "None",
            table: "Localizable", bundle: LorvexL10n.bundle),
          text: $store.draftHabitMilestoneTargetText
        )
        .multilineTextAlignment(.trailing)
        .textFieldStyle(.plain)
        .frame(maxWidth: 80)
        .accessibilityLabel(String(
          localized: "habits.sheet.field.milestone_goal", defaultValue: "Celebrate after",
          table: "Localizable", bundle: LorvexL10n.bundle))
        .accessibilityIdentifier("\(idPrefix).milestoneTarget")
      }
    } footer: {
      Text(milestoneGoalHint)
    }
  }

  /// The per-day check-in goal, stored as the draft's text so the store's
  /// validation keeps owning it; the stepper reads an unparsable draft as 1.
  private var targetCount: Binding<Int> {
    Binding(
      get: { store.parsedDraftHabitTargetCount ?? 1 },
      set: { store.draftHabitTargetCountText = "\($0)" })
  }

  /// A streak length for the streak cadences (daily, weekly days), a
  /// completion count for the cumulative ones (times a week, monthly). Both
  /// note the habit keeps going: a milestone is a celebration, not an end.
  private var milestoneGoalHint: String {
    switch store.draftHabitCadenceMode {
    case .timesPerWeek, .monthly:
      return String(
        localized: "habits.sheet.field.milestone_goal_hint_count",
        defaultValue: "Total completions, like 50. The habit keeps going.",
        table: "Localizable",
        bundle: LorvexL10n.bundle)
    default:
      return String(
        localized: "habits.sheet.field.milestone_goal_hint_streak",
        defaultValue: "Streak length in days, like 30. The habit keeps going.",
        table: "Localizable",
        bundle: LorvexL10n.bundle)
    }
  }
}

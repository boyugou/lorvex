import LorvexCore
import SwiftUI

/// The calm field panel shared by the create and edit habit sheets.
struct HabitFormFields: View {
  @Bindable var store: AppStore
  let idPrefix: String
  var nameTitle: String = String(
    localized: "habits.sheet.field.name", defaultValue: "Name",
    table: "Localizable",
    bundle: LorvexL10n.bundle)
  /// Claimed when the sheet appears so the user can type immediately.
  @FocusState private var nameFocused: Bool

  var body: some View {
    DraftSheetPanel(accessibilityIdentifier: "\(idPrefix).fields") {
      DraftSheetField(
        title: nameTitle,
        systemImage: "text.cursor"
      ) {
        TextField(
          nameTitle,
          text: $store.draftHabitName
        )
        .font(LorvexDesign.Typography.primaryText)
        .textFieldStyle(.plain)
        .focused($nameFocused)
        .accessibilityLabel(String(
          localized: "habits.sheet.field.name_a11y",
          defaultValue: "Habit name",
          table: "Localizable",
          bundle: LorvexL10n.bundle
        ))
        .accessibilityIdentifier("\(idPrefix).name")
      }

      // "Encouragement", not "Cue": this field is a motivating line shown on the
      // habit (matching iOS), not a when-to-do trigger. The storage column stays
      // `cue` (the Apple schema column), so the `draftHabitCue` binding is kept.
      DraftSheetField(
        title: String(
          localized: "habits.sheet.field.encouragement", defaultValue: "Encouragement",
          table: "Localizable",
          bundle: LorvexL10n.bundle),
        systemImage: "sparkles"
      ) {
        LorvexPlainTextEditor(
          text: $store.draftHabitCue,
          placeholder: String(
            localized: "habits.sheet.field.encouragement_placeholder",
            defaultValue: "A motivating line you’ll see on the habit",
            table: "Localizable",
            bundle: LorvexL10n.bundle),
          minHeight: 40,
          maxHeight: 44,
          fontSize: 14
        )
        .accessibilityLabel(String(
          localized: "habits.sheet.field.encouragement_a11y",
          defaultValue: "Habit encouragement",
          table: "Localizable",
          bundle: LorvexL10n.bundle
        ))
        .accessibilityIdentifier("\(idPrefix).cue")
      }

      DraftSheetField(
        title: String(localized: "habits.sheet.field.frequency", defaultValue: "Frequency", table: "Localizable", bundle: LorvexL10n.bundle),
        systemImage: "repeat"
      ) {
        HabitCadenceEditor(store: store, idPrefix: idPrefix)
      }

      // "Times a week" owns its count via its own stepper, and monthly is a
      // single check-in on a chosen day — so neither shows the per-period count
      // field (a second, conflicting count for the former; a "5×/month but one
      // reminder" mismatch for the latter).
      if store.draftHabitCadenceMode != .timesPerWeek && store.draftHabitCadenceMode != .monthly {
        DraftSheetField(title: targetTitle, systemImage: "number") {
          TextField(targetTitle, text: $store.draftHabitTargetCountText)
            .font(LorvexDesign.Typography.primaryText)
            .textFieldStyle(.plain)
            .frame(maxWidth: 120, alignment: .leading)
            .accessibilityLabel(targetTitle)
            .accessibilityIdentifier("\(idPrefix).targetCount")
          Text(LocalizedStringResource("habits.sheet.field.target_per_day_hint", defaultValue: "How many check-ins complete a day.", table: "Localizable", bundle: LorvexL10n.bundle))
            .font(LorvexDesign.Typography.tertiaryText)
            .foregroundStyle(.secondary)
        }
      }

      DraftSheetField(
        title: String(
          localized: "habits.sheet.field.milestone_goal", defaultValue: "Celebrate after",
          table: "Localizable",
          bundle: LorvexL10n.bundle),
        systemImage: "flag.checkered"
      ) {
        HStack(spacing: LorvexDesign.Spacing.s) {
          TextField(
            String(
              localized: "habits.sheet.field.milestone_goal_placeholder", defaultValue: "Optional number",
              table: "Localizable",
              bundle: LorvexL10n.bundle),
            text: $store.draftHabitMilestoneTargetText
          )
          .font(LorvexDesign.Typography.primaryText)
          .textFieldStyle(.plain)
          .frame(maxWidth: 120, alignment: .leading)
          .accessibilityLabel(String(
            localized: "habits.sheet.field.milestone_goal", defaultValue: "Celebrate after",
            table: "Localizable",
            bundle: LorvexL10n.bundle))
          .accessibilityIdentifier("\(idPrefix).milestoneTarget")

          if !store.draftHabitMilestoneTargetText.isEmpty {
            Button {
              store.draftHabitMilestoneTargetText = ""
            } label: {
              Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(String(
              localized: "habits.sheet.field.milestone_goal_clear", defaultValue: "Clear milestone goal",
              table: "Localizable",
              bundle: LorvexL10n.bundle))
            .accessibilityLabel(String(
              localized: "habits.sheet.field.milestone_goal_clear", defaultValue: "Clear milestone goal",
              table: "Localizable",
              bundle: LorvexL10n.bundle))
            .accessibilityIdentifier("\(idPrefix).milestoneTarget.clear")
          }
        }
        Text(milestoneGoalHint)
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.secondary)
      }

      LorvexIconColorField(
        icon: $store.draftHabitIcon,
        color: $store.draftHabitColor,
        idPrefix: idPrefix
      )
    }
    .task {
      nameFocused = false
      await Task.yield()
      nameFocused = true
    }
  }

  /// The per-day check-in goal. This field is shown only for Daily and
  /// Weekly-specific-days cadences, where `target_count` is the number of
  /// completions that mark one (scheduled) day done — so it reads as "times per
  /// day" rather than the ambiguous "per period". (Times-a-week and monthly hide
  /// it: the former's count lives in its own stepper, the latter is once.)
  private var targetTitle: String {
    String(
      localized: "habits.sheet.field.target_times_per_day", defaultValue: "Times per day",
      table: "Localizable",
      bundle: LorvexL10n.bundle)
  }

  /// Cadence-aware hint for the optional milestone goal: a streak length for the
  /// streak cadences (daily / weekly), a completion count for the cumulative
  /// cadences (times-a-week / monthly). Both note that the habit doesn't stop at
  /// the goal — a milestone is a celebration moment, not an end.
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

import LorvexCore
import SwiftUI

/// A goal being chosen in the habit inspector's Goal editor: the target the
/// editor holds while it is open, nil for no goal.
struct HabitGoalDraft: Equatable {
  var target: Int?
}

/// The popover behind a habit's Goal field, built like the task inspector's
/// How Long editor: the goal in a ring between a − and a + button, one-click
/// goals beneath (``HabitGoalChoices``), and No Goal to remove it.
///
/// The goal counts in the habit's milestone unit (days, weeks, or
/// completions), and the ring fills with the habit's current reading toward
/// it, so a 12-day streak against a 30-day goal shows two fifths.
///
/// The editor works on `draft`, which the inspector's Goal row also reads, so
/// the row shows the goal as it is chosen. When the popover closes, a changed
/// goal goes to `save`; an unchanged one just ends the draft. No Goal closes
/// the popover and saves at once, before the row turns into an addition.
/// `save` receives the goal to store (nil removes it) and ends the draft once
/// the write lands, so the row never shows the old goal in between.
struct HabitGoalEditor: View {
  let habit: LorvexHabit
  @Binding var draft: HabitGoalDraft?
  let save: (Int?) -> Void

  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.dismiss) private var dismiss
  @State private var didSave = false

  private var unit: HabitGoalChoices.Unit { HabitGoalChoices.unit(for: habit) }
  private var target: Int? { draft.map(\.target) ?? habit.milestoneTarget }
  private var tint: Color { LorvexHabitPalette.baseColor(for: habit) }

  /// The streak or completion count the habit stands at now.
  private var reading: Int { habit.milestone?.value ?? 0 }

  private func set(_ value: Int?) { draft = HabitGoalDraft(target: value) }

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
      InspectorEditorHeader(title: HabitDetailFieldCopy.goal, hint: hint)
      HStack(spacing: LorvexDesign.Spacing.l) {
        stepButton(
          systemImage: "minus",
          label: String(localized: "habit_detail.goal.decrease", defaultValue: "Lower Goal", table: "Localizable", bundle: LorvexL10n.bundle),
          isDisabled: (target ?? 0) <= 1
        ) {
          if let target { set(HabitGoalChoices.decrement(target)) }
        }
        ring
        stepButton(
          systemImage: "plus",
          label: String(localized: "habit_detail.goal.increase", defaultValue: "Raise Goal", table: "Localizable", bundle: LorvexL10n.bundle),
          isDisabled: (target ?? 0) >= HabitGoalChoices.maximum
        ) {
          set(target.map(HabitGoalChoices.increment) ?? HabitGoalChoices.firstGoal(for: unit))
        }
      }
      .frame(maxWidth: .infinity)
      LorvexFlowLayout(spacing: LorvexDesign.Spacing.xs, lineSpacing: LorvexDesign.Spacing.xs) {
        ForEach(HabitGoalChoices.presets(for: unit), id: \.self) { preset in
          InspectorEditorPill(label: preset.formatted(), isOn: target == preset) { set(preset) }
            .accessibilityLabel(phrase(preset))
        }
      }
      .accessibilityIdentifier("habit.detail.goal.presets")
      if target != nil {
        Button(
          String(localized: "habit_detail.goal.none", defaultValue: "No Goal", table: "Localizable", bundle: LorvexL10n.bundle),
          role: .destructive
        ) {
          didSave = true
          dismiss()
          save(nil)
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier("habit.detail.goal.clear")
      }
    }
    .frame(width: 280)
    .onAppear { draft = HabitGoalDraft(target: habit.milestoneTarget) }
    .onDisappear {
      guard !didSave, let draft else { return }
      if draft.target != habit.milestoneTarget {
        save(draft.target)
      } else {
        self.draft = nil
      }
    }
    .accessibilityIdentifier("habit.detail.goal.editor")
  }

  /// The goal over its unit inside a ring that fills with the current
  /// reading toward it; "No goal" while there is none.
  private var ring: some View {
    let fraction = target.map { min(Double(reading) / Double(max($0, 1)), 1) } ?? 0
    return ZStack {
      Circle()
        .stroke(tint.opacity(LorvexDesign.Palette.trackOpacity(for: colorScheme)), lineWidth: 6)
      LorvexProgressArc(fraction: fraction, style: tint, lineWidth: 6)
      if let target {
        VStack(spacing: 0) {
          Text(verbatim: target.formatted())
            .font(LorvexDesign.Typography.screenTitle.monospacedDigit())
            .contentTransition(.numericText(value: Double(target)))
          Text(unitLabel(for: target))
            .font(LorvexDesign.Typography.tertiaryText)
            .foregroundStyle(.secondary)
        }
      } else {
        Text(LocalizedStringResource("habit_detail.goal.unset", defaultValue: "No goal", table: "Localizable", bundle: LorvexL10n.bundle))
          .font(LorvexDesign.Typography.secondaryText)
          .foregroundStyle(.secondary)
      }
    }
    .frame(width: 96, height: 96)
    .reduceMotionAnimation(.snappy(duration: 0.2), value: target)
    .help(readingLabel)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(HabitDetailFieldCopy.goal)
    .accessibilityValue(target.map(phrase) ?? String(localized: "habit_detail.goal.unset", defaultValue: "No goal", table: "Localizable", bundle: LorvexL10n.bundle))
    .accessibilityHint(readingLabel)
  }

  private func stepButton(
    systemImage: String, label: String, isDisabled: Bool, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .frame(width: 28, height: 28)
    }
    .buttonStyle(.bordered)
    .buttonBorderShape(.circle)
    .disabled(isDisabled)
    .help(label)
    .accessibilityLabel(label)
  }

  /// What the goal measures, so the number reads in its unit.
  private var hint: String {
    switch unit {
    case .days:
      String(localized: "habit_detail.goal.hint.days", defaultValue: "A streak to celebrate, in days. The habit keeps going after it.", table: "Localizable", bundle: LorvexL10n.bundle)
    case .weeks:
      String(localized: "habit_detail.goal.hint.weeks", defaultValue: "A streak to celebrate, in weeks. The habit keeps going after it.", table: "Localizable", bundle: LorvexL10n.bundle)
    case .completions:
      String(localized: "habit_detail.goal.hint.completions", defaultValue: "A number of completions to celebrate. The habit keeps going after it.", table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }

  /// The unit under the ring's number ("day", "days"), in the plural form the
  /// display language uses for `value`. The catalog's plural forms leave the
  /// number out, since the ring shows it above; the default value carries it
  /// only so `value` reaches the plural rules.
  private func unitLabel(for value: Int) -> String {
    switch unit {
    case .days:
      String(localized: "habit_detail.goal.unit.days", defaultValue: "\(value) days", table: "Localizable", bundle: LorvexL10n.bundle)
    case .weeks:
      String(localized: "habit_detail.goal.unit.weeks", defaultValue: "\(value) weeks", table: "Localizable", bundle: LorvexL10n.bundle)
    case .completions:
      String(localized: "habit_detail.goal.unit.completions", defaultValue: "\(value) completions", table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }

  /// A goal value as the phrase the Goal row shows ("30-day streak", "50
  /// completions").
  private func phrase(_ value: Int) -> String {
    HabitDetailFieldCopy.goalValue(value, habit: habit)
  }

  /// The habit's current reading, which the ring's fill measures ("12-day
  /// streak", "No streak yet"): the ring's help tag and VoiceOver hint.
  private var readingLabel: String {
    let metric = unit == .completions ? "count" : "streak"
    return HabitDisplayText.milestoneValueLabel(
      metric: metric, value: reading, frequencyType: habit.frequencyType)
  }
}

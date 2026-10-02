import LorvexCore
import SwiftUI

/// The habit inspector's fields as rows, through the shared
/// ``InspectorProperties`` so they read and edit like a task's: how the habit
/// repeats, when it reminds, and the goal it celebrates. Every habit repeats,
/// so Repeat is always a row; a habit without reminders or a goal offers them
/// as dashed additions. The reminder field waits for the inspector's detail
/// (`reminderPolicies` nil) rather than offer an addition the loaded detail
/// might contradict.
///
/// Each field edits in a popover:
/// - Repeat holds the New Habit sheet's cadence editor and the per-day count.
///   It works on the store's habit draft, loaded from the habit as the popover
///   opens, and saves when the popover closes if the rhythm changed.
/// - Reminder is ``HabitReminderEditor``, which saves each change at once.
/// - Goal is ``HabitGoalEditor``, which saves when the popover closes.
///
/// While the Repeat or Goal popover is open, and until its save lands, the
/// row shows the value being chosen rather than the stored one.
struct HabitDetailProperties: View {
  @Bindable var store: AppStore
  let habit: LorvexHabit
  let reminderPolicies: [HabitReminderPolicy]?

  /// The habit as the open Repeat editor would leave it; nil while the editor
  /// is closed and its save has landed.
  @State private var rhythmPreview: LorvexHabit?
  @State private var goalDraft: HabitGoalDraft?

  var body: some View {
    let content = propertyContent
    InspectorProperties(rows: content.rows, additions: content.additions, idPrefix: "habit.detail") { id in
      Self.editor(
        id, store: store, habit: habit, reminderPolicies: reminderPolicies ?? [],
        rhythmPreview: $rhythmPreview, goalDraft: $goalDraft, saveGoal: saveGoal)
    }
  }

  /// The popover editor behind the field `id` ("repeat", "reminder", or
  /// "goal"). `rhythmPreview` and `goalDraft` receive the values the Repeat
  /// and Goal editors are choosing; `saveGoal` stores a goal (nil removes it)
  /// and ends `goalDraft` once the write lands.
  @ViewBuilder
  static func editor(
    _ id: String,
    store: AppStore,
    habit: LorvexHabit,
    reminderPolicies: [HabitReminderPolicy],
    rhythmPreview: Binding<LorvexHabit?>,
    goalDraft: Binding<HabitGoalDraft?>,
    saveGoal: @escaping (Int?) -> Void
  ) -> some View {
    switch id {
    case "repeat":
      HabitRhythmEditor(store: store, habit: habit, preview: rhythmPreview)
    case "reminder":
      HabitReminderEditor(store: store, habit: habit, policies: reminderPolicies)
    default:
      HabitGoalEditor(habit: habit, draft: goalDraft, save: saveGoal)
    }
  }

  private var propertyContent: (rows: [InspectorPropertyRow], additions: [InspectorPropertyAddition]) {
    typealias Copy = HabitDetailFieldCopy
    var rows: [InspectorPropertyRow] = []
    var additions: [InspectorPropertyAddition] = []
    func field(_ id: String, _ systemImage: String, _ label: String, _ value: String?) {
      if let value {
        rows.append(.init(id: id, systemImage: systemImage, label: label, value: value))
      } else {
        additions.append(.init(id: id, label: label))
      }
    }
    field("repeat", "repeat", Copy.repeatLabel, HabitDisplayText.repeatSummary(rhythmPreview ?? habit))
    if let reminderPolicies {
      field("reminder", "bell", Copy.reminder, Copy.reminderValue(reminderPolicies))
    }
    let goal = goalDraft.map(\.target) ?? habit.milestoneTarget
    field("goal", "flag.checkered", Copy.goal, goal.map { Copy.goalValue($0, habit: habit) })
    return (rows, additions)
  }

  private func saveGoal(_ target: Int?) {
    Task {
      await store.updateHabitFields(habit, milestoneTarget: target.map { .set($0) } ?? .clear)
      goalDraft = nil
    }
  }
}

/// The words of the habit inspector's fields: their names and the values
/// their rows show.
enum HabitDetailFieldCopy {
  static var repeatLabel: String {
    String(localized: "habit_detail.field.repeat", defaultValue: "Repeat", table: "Localizable", bundle: LorvexL10n.bundle)
  }
  static var reminder: String {
    String(localized: "habit_detail.field.reminder", defaultValue: "Reminder", table: "Localizable", bundle: LorvexL10n.bundle)
  }
  static var goal: String {
    String(localized: "habit_detail.field.goal", defaultValue: "Goal", table: "Localizable", bundle: LorvexL10n.bundle)
  }

  /// The habit's reminder times as its Reminder row reads them: up to three
  /// times in order ("8:00 AM · 9:00 PM"), a count and a span beyond that
  /// ("8 times, 9:00 AM–9:00 PM"), or "Off" while every reminder is switched
  /// off. Nil for a habit without reminders.
  static func reminderValue(_ policies: [HabitReminderPolicy]) -> String? {
    guard !policies.isEmpty else { return nil }
    let times = policies.filter(\.enabled).map(\.reminderTime).sorted()
    guard let first = times.first, let last = times.last else {
      return String(localized: "habit_detail.reminder.off", defaultValue: "Off", table: "Localizable", bundle: LorvexL10n.bundle)
    }
    guard times.count > 3 else {
      return times.map(HabitReminderTime.display).joined(separator: " · ")
    }
    let earliest = HabitReminderTime.display(first)
    let latest = HabitReminderTime.display(last)
    return String(
      localized: "habit_detail.reminder.many",
      defaultValue: "\(times.count) times, \(earliest)–\(latest)",
      table: "Localizable", bundle: LorvexL10n.bundle)
  }

  /// A goal as its Goal row reads it, in the habit's milestone unit: "30-day
  /// streak", "4-week streak", or "50 completions".
  static func goalValue(_ target: Int, habit: LorvexHabit) -> String {
    let metric = HabitGoalChoices.unit(for: habit) == .completions ? "count" : "streak"
    return HabitDisplayText.milestoneValueLabel(
      metric: metric, value: target, frequencyType: habit.frequencyType)
  }
}

/// The popover behind a habit's Repeat field: the New Habit sheet's cadence
/// editor (``HabitCadenceEditor``) and, for the cadences counted per day, the
/// check-ins that complete a day.
///
/// It edits the store's habit draft, which it loads from `habit` as it opens
/// (``AppStore/prepareHabitRhythmDraft(for:)``). While it is open, `preview`
/// holds the habit as the draft would leave it, for the Repeat row. When it
/// closes with the rhythm changed, it saves the draft
/// (``AppStore/saveHabitRhythmDraft(_:)``) and ends the preview once the save
/// lands; otherwise it ends the preview at once.
private struct HabitRhythmEditor: View {
  @Bindable var store: AppStore
  let habit: LorvexHabit
  @Binding var preview: LorvexHabit?

  private struct Rhythm: Equatable {
    let cadence: HabitCadenceInput
    let targetCount: Int
  }

  @State private var initial: Rhythm?

  private var current: Rhythm {
    let draft = store.draftHabitCadenceInput()
    return Rhythm(cadence: draft.cadence, targetCount: draft.targetCount)
  }

  private var countsPerDay: Bool {
    store.draftHabitCadenceMode != .timesPerWeek && store.draftHabitCadenceMode != .monthly
  }

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
      InspectorEditorHeader(title: HabitDetailFieldCopy.repeatLabel, hint: nil)
      HabitCadenceEditor(store: store, idPrefix: "habit.detail.repeat")
      if countsPerDay {
        Divider()
        timesPerDay
      }
    }
    .frame(width: 300, alignment: .leading)
    .onAppear {
      store.prepareHabitRhythmDraft(for: habit)
      initial = current
      preview = previewHabit(current)
    }
    .onChange(of: current) { _, rhythm in
      preview = previewHabit(rhythm)
    }
    .onDisappear {
      guard let initial, current != initial else {
        preview = nil
        return
      }
      Task {
        await store.saveHabitRhythmDraft(habit)
        preview = nil
      }
    }
  }

  /// The check-ins that complete a day, 1 to 99.
  private var timesPerDay: some View {
    let label = String(
      localized: "habits.sheet.field.target_times_per_day", defaultValue: "Times per day",
      table: "Localizable", bundle: LorvexL10n.bundle)
    return HStack(spacing: LorvexDesign.Spacing.s) {
      Text(label)
        .font(LorvexDesign.Typography.primaryText)
      Spacer(minLength: LorvexDesign.Spacing.s)
      Text(targetCount.wrappedValue, format: .number)
        .font(LorvexDesign.Typography.primaryText.monospacedDigit())
        .contentTransition(.numericText(value: Double(targetCount.wrappedValue)))
      Stepper(label, value: targetCount, in: 1...99)
        .labelsHidden()
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("habit.detail.repeat.targetCount")
  }

  /// The per-day count, kept as the draft's text so the store's validation
  /// owns it; an unparsable draft reads as 1.
  private var targetCount: Binding<Int> {
    Binding(
      get: { store.parsedDraftHabitTargetCount ?? 1 },
      set: { store.draftHabitTargetCountText = "\($0)" })
  }

  private func previewHabit(_ rhythm: Rhythm) -> LorvexHabit {
    var preview = habit
    preview.frequencyType = rhythm.cadence.frequencyType
    preview.weekdays = rhythm.cadence.weekdays
    preview.perPeriodTarget = rhythm.cadence.perPeriodTarget
    preview.dayOfMonth = rhythm.cadence.dayOfMonth
    preview.targetCount = rhythm.targetCount
    return preview
  }
}

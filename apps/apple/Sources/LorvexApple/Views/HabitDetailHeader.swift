import LorvexCore
import SwiftUI

/// The habit inspector's header, laid out like the task inspector's: the
/// habit's check-in ring where a task's completion circle sits, the name and
/// the encouragement edited in place beside it, and the inspector's close
/// button.
///
/// The ring is the habit card's (``HabitProgressRing``) at a smaller size, and
/// a click on it does what a click on the card's ring does
/// (``HabitRingAction``). The icon and color popover, which the overflow menu
/// opens through `isChoosingAppearance`, points at the ring; the ring shows
/// the choice while the popover is open and saves it when the popover
/// closes.
///
/// The name and the encouragement save when their field loses focus or on
/// Return. An emptied name reverts to the stored one; an emptied
/// encouragement removes it. While a field is not being edited, it follows the
/// stored value, so an edit from another device or the assistant shows here.
struct HabitDetailHeader: View {
  let store: AppStore
  let habit: LorvexHabit
  let progress: HabitPeriodProgress.Value
  @Binding var isChoosingAppearance: Bool

  private enum Field { case name, cue }

  @State private var name: String
  @State private var cue: String
  @State private var icon: String?
  @State private var color: String?
  @FocusState private var focusedField: Field?

  init(
    store: AppStore, habit: LorvexHabit, progress: HabitPeriodProgress.Value,
    isChoosingAppearance: Binding<Bool>
  ) {
    self.store = store
    self.habit = habit
    self.progress = progress
    _isChoosingAppearance = isChoosingAppearance
    _name = State(initialValue: habit.name)
    _cue = State(initialValue: habit.cue ?? "")
    _icon = State(initialValue: habit.icon)
    _color = State(initialValue: habit.color)
  }

  private var ringAction: HabitRingAction { HabitRingAction.action(habit: habit, progress: progress) }

  /// The habit's icon and identity color, or the ones being chosen while the
  /// icon and color popover is open.
  private var shownIcon: String? { isChoosingAppearance ? icon : habit.icon }
  private var identityColor: Color {
    LorvexHabitPalette.baseColor(id: habit.id, color: isChoosingAppearance ? color : habit.color)
  }

  private var ringTint: Color {
    progress.isComplete ? LorvexDesign.Palette.done : identityColor
  }

  var body: some View {
    HStack(alignment: .top, spacing: LorvexDesign.Spacing.s) {
      ring

      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
        TextField(
          String(localized: "habits.sheet.field.name_prompt", defaultValue: "Habit name", table: "Localizable", bundle: LorvexL10n.bundle),
          text: $name,
          axis: .vertical
        )
        .font(LorvexDesign.Typography.screenTitle)
        .textFieldStyle(.plain)
        .lineLimit(1...)
        .fixedSize(horizontal: false, vertical: true)
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .focused($focusedField, equals: .name)
        .onSubmit(commitName)
        .accessibilityLabel(String(localized: "habits.sheet.field.name_a11y", defaultValue: "Habit name", table: "Localizable", bundle: LorvexL10n.bundle))
        .accessibilityIdentifier("habit.detail.name")

        encouragementField
      }

      InspectorCloseButton(accessibilityIdentifier: "habit.detail.inspector.close") {
        store.selectedHabitID = nil
      }
    }
    .onChange(of: focusedField) { previous, _ in
      switch previous {
      case .name: commitName()
      case .cue: commitCue()
      case nil: break
      }
    }
    .onChange(of: habit.name) { _, stored in
      if focusedField != .name { name = stored }
    }
    .onChange(of: habit.cue) { _, stored in
      if focusedField != .cue { cue = stored ?? "" }
    }
    .onChange(of: isChoosingAppearance) { _, isOpen in
      if isOpen {
        icon = habit.icon
        color = habit.color
      } else {
        commitAppearance()
      }
    }
    // A switch to another habit replaces this header, so an edit still in a
    // field saves to the habit it was typed for. A field that already lost
    // focus saved then.
    .onDisappear {
      switch focusedField {
      case .name: commitName()
      case .cue: commitCue()
      case nil: break
      }
    }
    // A habit card's Edit command opens this inspector to type a new name.
    // The inspector appears with the selection, so focus waits a turn for
    // the field to join the window.
    .onChange(of: store.habitNameFocusRequest, initial: true) { _, requested in
      guard requested == habit.id else { return }
      store.habitNameFocusRequest = nil
      Task { @MainActor in
        await Task.yield()
        focusedField = .name
      }
    }
  }

  /// The check-in ring, which also anchors the icon and color popover.
  private var ring: some View {
    HabitProgressRing(
      completed: progress.completed,
      target: progress.required,
      tint: ringTint,
      icon: LorvexSymbol.name(for: shownIcon, fallback: "repeat.circle"),
      diameter: 34,
      action: ringTapped
    )
    .padding(.top, 2)
    .help(ringAction.label(for: habit))
    .accessibilityLabel(ringAction.label(for: habit))
    .accessibilityIdentifier("habit.detail.ring")
    .popover(isPresented: $isChoosingAppearance, arrowEdge: .bottom) {
      LorvexAppearancePicker(icon: $icon, color: $color, idPrefix: "habit.detail.appearance")
        .padding(LorvexDesign.Spacing.m)
        .frame(width: LorvexAppearancePicker.popoverWidth)
    }
  }

  /// The encouragement, a motivating line under the name in the habit's own
  /// color: a sparkle and italic text, with a quiet prompt to add one while
  /// the habit has none.
  private var encouragementField: some View {
    HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.xs) {
      Image(systemName: "sparkles")
        .font(LorvexDesign.Typography.tertiaryText)
        .foregroundStyle(
          cue.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(identityColor))
        .accessibilityHidden(true)
      TextField(
        String(localized: "habits.sheet.field.encouragement_prompt", defaultValue: "Add an encouraging line", table: "Localizable", bundle: LorvexL10n.bundle),
        text: $cue,
        axis: .vertical
      )
      .font(LorvexDesign.Typography.secondaryText.italic())
      .foregroundStyle(.secondary)
      .textFieldStyle(.plain)
      .lineLimit(1...)
      .focused($focusedField, equals: .cue)
      .onSubmit(commitCue)
      .accessibilityLabel(String(localized: "habits.sheet.field.encouragement_a11y", defaultValue: "Habit encouragement", table: "Localizable", bundle: LorvexL10n.bundle))
      .accessibilityIdentifier("habit.detail.cue")
    }
  }

  private func ringTapped() {
    switch ringAction {
    case .addOne: Task { await store.adjustHabitCompletion(habit, delta: 1) }
    case .checkIn: Task { await store.completeHabit(habit) }
    case .undoToday: Task { await store.uncompleteHabit(habit) }
    case .none: break
    }
  }

  private func commitName() {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      name = habit.name
      return
    }
    guard trimmed != habit.name else { return }
    Task { await store.updateHabitFields(habit, name: trimmed) }
  }

  private func commitCue() {
    let trimmed = cue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed != (habit.cue ?? "") else { return }
    Task { await store.updateHabitFields(habit, cue: trimmed.isEmpty ? .clear : .set(trimmed)) }
  }

  private func commitAppearance() {
    guard icon != habit.icon || color != habit.color else { return }
    Task {
      await store.updateHabitFields(
        habit,
        icon: icon.map { .set($0) } ?? .clear,
        color: color.map { .set($0) } ?? .clear)
    }
  }
}

import LorvexCore
import SwiftUI

/// The habit progress ring rendered as a real completion control: tapping it
/// logs today's completion (or resets it once the target is met) with a spring
/// pop and a success haptic, while the ring fills toward its target. Plain so it
/// owns only its own hit area — the rest of the row still selects/opens the
/// habit. Shared by the compact habit row and the regular/iPad catalog row so
/// both give the same on-row completion moment.
struct MobileHabitCompletionRing: View {
  let habit: LorvexHabit
  let isMutating: Bool
  let complete: () async -> Void
  let reset: () async -> Void
  /// Drives the tap feedback: the ring springs up and settles back as the
  /// completion lands and the fill animates to its new value.
  @State private var pulse = false

  var body: some View {
    Button(action: trigger) {
      MobileProgressRing(
        value: habit.todayProgressValue,
        tint: habit.isCompleteToday ? .green : habit.tileTint,
        size: 32,
        isComplete: habit.isCompleteToday
      )
      .scaleEffect(pulse ? 1.18 : 1)
      .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .disabled(isMutating)
    .lorvexSensoryFeedback(.success, trigger: pulse) { _, now in now }
    .accessibilityLabel(
      habit.isCompleteToday
        ? String(format: String(localized: "habits.reset.a11y", defaultValue: "Reset %@", table: "Localizable", bundle: MobileL10n.bundle), habit.name)
        : String(format: String(localized: "habits.complete.a11y", defaultValue: "Complete %@", table: "Localizable", bundle: MobileL10n.bundle), habit.name))
    .accessibilityValue(habit.todayProgressText)
    .accessibilityIdentifier("mobileHabits.completionRing.\(habit.id)")
  }

  private func trigger() {
    guard !isMutating else { return }
    let wasComplete = habit.isCompleteToday
    withAnimation(.spring(response: 0.34, dampingFraction: 0.5)) {
      pulse = true
    }
    Task {
      if wasComplete {
        await reset()
      } else {
        await complete()
      }
      withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
        pulse = false
      }
    }
  }
}

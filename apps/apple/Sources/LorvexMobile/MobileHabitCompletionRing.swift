import LorvexCore
import SwiftUI

/// The habit progress ring rendered as a real completion control: tapping it
/// logs today's completion (or resets it once the target is met) with a spring
/// pop and a success haptic, while the ring fills toward its target. Plain so it
/// owns only its own hit area — the rest of the row still selects/opens the
/// habit. Shared by the compact habit row, the regular/iPad catalog row, and
/// Today's habit strip so all give the same completion moment.
struct MobileHabitCompletionRing: View {
  let habit: LorvexHabit
  let isMutating: Bool
  /// Draws the habit's symbol inside the ring until it is complete, where the
  /// ring stands without the habit's icon tile beside it.
  var showsSymbol: Bool = false
  var size: CGFloat = 32
  let complete: () async -> Void
  let reset: () async -> Void
  /// Drives the tap feedback: the ring springs up and settles back as the
  /// completion lands and the fill animates to its new value.
  @State private var pulse = false

  var body: some View {
    Button(action: trigger) {
      MobileProgressRing(
        value: habit.todayProgressValue,
        tint: habit.isCompleteToday ? LorvexDesign.Palette.done : habit.tileTint,
        size: size,
        isComplete: habit.isCompleteToday,
        symbol: showsSymbol ? habit.tileSymbol : nil
      )
      .reduceMotionPop(isActive: pulse)
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
    lorvexAnimated(.spring(response: 0.34, dampingFraction: 0.5)) {
      pulse = true
    }
    Task {
      if wasComplete {
        await reset()
      } else {
        await complete()
      }
      lorvexAnimated(.spring(response: 0.3, dampingFraction: 0.7)) {
        pulse = false
      }
    }
  }
}

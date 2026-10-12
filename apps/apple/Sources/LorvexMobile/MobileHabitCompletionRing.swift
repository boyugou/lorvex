import LorvexCore
import SwiftUI

/// The habit progress ring rendered as a real completion control: tapping it
/// checks the habit in with a spring pop and a success haptic, while the ring
/// fills toward its target. A habit kept once a day toggles; one counted several
/// times a day adds one per tap until its count is met, after which a tap does
/// nothing, so a tap never wipes the day's tally (Reset Today in the menus
/// clears it). Plain so it
/// owns only its own hit area — the rest of the row still selects/opens the
/// habit. Shared by the compact habit row, the regular/iPad catalog row, and
/// Today's habit strip so all give the same completion moment.
///
/// The ring judges the habit against `basis`: Today's strip against the day, the
/// Habits screens against the habit's period, as the Mac's cards do, so a habit
/// kept three times a week that met its week reads done in both places. On the
/// period basis a habit whose period earlier days already met, and which holds no
/// check-in today, has nothing to check in: the ring shows it done and a tap does
/// nothing (``LorvexHabitCheckIn``).
///
/// A habit set aside for today draws as a skipped ring. Tapping it still checks
/// the habit in, which lifts the skip: a day holds a check-in or a skip, and the
/// check-in outranks it. Taking the skip back without checking in is the
/// Undo Skip command of the row and detail menus.
struct MobileHabitCompletionRing: View {
  let habit: LorvexHabit
  let isMutating: Bool
  /// Draws the habit's symbol inside the ring until it is complete, where the
  /// ring stands without the habit's icon tile beside it.
  var showsSymbol: Bool = false
  var size: CGFloat = 32
  /// What the ring judges the habit against. Today's strip keeps the day.
  var basis: LorvexHabitCheckIn.Basis = .day
  let complete: () async -> Void
  let reset: () async -> Void
  /// Drives the tap feedback: the ring springs up and settles back as the
  /// completion lands and the fill animates to its new value.
  @State private var pulse = false

  /// How far the tap target reaches past the ring, to make it 44pt across.
  private var tapOutset: CGFloat { max(0, (44 - size) / 2) }

  private var fraction: Double {
    basis == .period ? habit.periodProgressValue : habit.todayProgressValue
  }

  private var isComplete: Bool {
    basis == .period ? habit.isCompleteForPeriod : habit.isCompleteToday
  }

  /// What a tap does, by the shared rule (``LorvexHabitCheckIn``) on the ring's
  /// basis.
  private var checkIn: LorvexHabitCheckIn { LorvexHabitCheckIn.action(for: habit, basis: basis) }

  var body: some View {
    Button(action: trigger) {
      MobileProgressRing(
        value: fraction,
        tint: isComplete ? LorvexDesign.Palette.done : habit.tileTint,
        size: size,
        isComplete: isComplete,
        symbol: showsSymbol ? habit.tileSymbol : nil,
        isSkipped: habit.isSkipped,
        segments: habit.ringSegments
      )
      .reduceMotionPop(isActive: pulse)
      .padding(tapOutset)
      .contentShape(Circle())
    }
    .buttonStyle(.plain)
    // The layout keeps the ring's own size; the tap target reaches `tapOutset`
    // past it on every side.
    .padding(-tapOutset)
    .disabled(isMutating)
    .lorvexSensoryFeedback(.success, trigger: pulse) { _, now in now }
    .accessibilityLabel(MobileHabitCheckInCopy.ringLabel(for: habit, action: checkIn))
    .accessibilityValue(MobileHabitCheckInCopy.ringValue(for: habit, basis: basis))
    .accessibilityIdentifier("mobileHabits.completionRing.\(habit.id)")
  }

  private func trigger() {
    let action = checkIn
    guard !isMutating, action != .none else { return }
    lorvexAnimated(.spring(response: 0.34, dampingFraction: 0.5)) {
      pulse = true
    }
    Task {
      if action == .uncomplete {
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

import LorvexCore
import SwiftUI

/// A habit row for the Habits catalog list.
///
/// Two modes:
/// - Interactive (`onSelect` + `complete`/`reset` provided): the summary is a
///   select button and the trailing ring is a tappable complete/reset control,
///   laid out as sibling controls so the ring owns its own hit area while the
///   rest of the row selects the habit. This is the normal (non-batch) list.
/// - Passive (closures nil): a plain summary + a read-only ring, for batch-select
///   mode where the parent owns the whole-row tap.
struct MobileHabitCatalogRow: View {
  let habit: LorvexHabit
  var isMutating: Bool = false
  var onSelect: (() -> Void)? = nil
  var complete: (() async -> Void)? = nil
  var reset: (() async -> Void)? = nil

  var body: some View {
    if let onSelect, let complete, let reset {
      HStack(spacing: LorvexDesign.Spacing.m) {
        Button(action: onSelect) {
          summary
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        MobileHabitCompletionRing(
          habit: habit,
          isMutating: isMutating,
          complete: complete,
          reset: reset
        )
      }
      .padding(.vertical, LorvexDesign.Spacing.xs)
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("mobileHabits.catalogRow.\(habit.id)")
    } else {
      HStack(spacing: LorvexDesign.Spacing.m) {
        summary
        Spacer(minLength: LorvexDesign.Spacing.s)
        MobileProgressRing(
          value: habit.todayProgressValue,
          tint: habit.isCompleteToday ? .green : habit.tileTint,
          size: 32,
          isComplete: habit.isCompleteToday
        )
        .accessibilityHidden(true)
      }
      .padding(.vertical, LorvexDesign.Spacing.xs)
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier("mobileHabits.catalogRow.\(habit.id)")
    }
  }

  private var summary: some View {
    HStack(spacing: LorvexDesign.Spacing.m) {
      MobileIconTile(icon: habit.icon, fallback: "repeat", tint: habit.tileTint, size: 30)

      VStack(alignment: .leading, spacing: 3) {
        Text(habit.name)
          .font(.body)
          .lineLimit(1)
        Text(habit.todayProgressText)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .lineLimit(1)
        if let milestone = habit.milestone, habit.showsMilestoneStrip {
          MobileHabitMilestoneProgressView(
            milestone: milestone, frequencyType: habit.frequencyType, tint: habit.tileTint)
        }
      }
    }
  }
}

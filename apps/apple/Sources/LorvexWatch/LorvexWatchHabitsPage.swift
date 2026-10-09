import LorvexCore
import LorvexWidgetKitSupport
import SwiftUI
#if os(watchOS)
  import WatchKit
#endif

/// Today's habits as rings, two to a row (one at accessibility text sizes, so
/// names have the width to read): an open habit shows its own symbol in its
/// ring, a tap checks it off with a haptic, and a done habit fills green with
/// a check. A habit set aside for today draws its ring as dots around a skip
/// mark; a tap still checks it off, which lifts the skip.
struct LorvexWatchHabitsPage: View {
  @Bindable var store: LorvexWatchStore
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  private var columns: Int { dynamicTypeSize.isAccessibilitySize ? 1 : 2 }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
        Text(LorvexWatchCalmCopy.habitsLabel)
          .font(LorvexDesign.Typography.tertiaryText.weight(.semibold))
          .foregroundStyle(.secondary)
          .accessibilityAddTraits(.isHeader)
        Grid(horizontalSpacing: LorvexDesign.Spacing.s, verticalSpacing: LorvexDesign.Spacing.m) {
          ForEach(Array(stride(from: 0, to: store.habits.count, by: columns)), id: \.self) { start in
            GridRow {
              ForEach(store.habits[start..<min(start + columns, store.habits.count)], id: \.id) { habit in
                ring(habit)
              }
            }
          }
        }
      }
      .padding(.horizontal, LorvexDesign.Spacing.s)
    }
    .accessibilityIdentifier("watch.habits")
  }

  private func ring(_ habit: WidgetSnapshot.HabitSummary) -> some View {
    // A done habit stays at full strength (not disabled, which would grey
    // it like an unavailable control); tapping it again does nothing.
    Button {
      guard !habit.isDoneToday else { return }
      Task {
        await store.completeHabit(id: habit.id)
        #if os(watchOS)
          WKInterfaceDevice.current().play(store.error == nil ? .success : .failure)
        #endif
      }
    } label: {
      VStack(spacing: LorvexDesign.Spacing.xs) {
        // An open habit carries its own symbol in the ring, so it never
        // shows a check before it is done; a done one fills green with one.
        if habit.isSkipped && !habit.isDoneToday {
          LorvexHabitCheckRing(
            fraction: 0, tint: LorvexDesign.Palette.accent, diameter: 40, isSkipped: true)
        } else {
          LorvexTaskRing(
            progress: habit.target > 0 ? Double(habit.completedToday) / Double(habit.target) : 0,
            isDone: habit.isDoneToday, diameter: 40, showsCheckHint: false)
            .overlay {
              if !habit.isDoneToday {
                Image(systemName: LorvexSymbol.name(for: habit.icon, fallback: "repeat"))
                  .font(LorvexDesign.Typography.secondaryText.weight(.semibold))
                  .foregroundStyle(LorvexDesign.Palette.accent)
                  .accessibilityHidden(true)
              }
            }
        }
        Text(userContent: habit.name)
          .font(LorvexDesign.Typography.tertiaryText)
          .lineLimit(2)
          .multilineTextAlignment(.center)
      }
      .frame(maxWidth: .infinity)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(habit.name)
    .accessibilityValue(accessibilityValue(habit))
    .accessibilityIdentifier("watch.habit.\(habit.id)")
  }

  private func accessibilityValue(_ habit: WidgetSnapshot.HabitSummary) -> String {
    if habit.isDoneToday { return LorvexWatchCalmCopy.done }
    if habit.isSkipped { return LorvexWatchCalmCopy.skippedToday }
    return "\(habit.completedToday)/\(habit.target)"
  }
}

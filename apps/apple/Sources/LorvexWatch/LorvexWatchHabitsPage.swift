import LorvexCore
import LorvexWidgetKitSupport
import SwiftUI
#if os(watchOS)
  import WatchKit
#endif

/// Today's habits as rings, two to a row (one at accessibility text sizes, so
/// names have the width to read), drawn as the phone's Today and the widgets
/// draw them (``LorvexHabitRingTile``): an open habit shows its own symbol in
/// its identity color, a habit counted several times a day one arc per
/// check-in, and a done habit a green check over a quieted name. A tap checks
/// a habit off with a haptic. A habit set aside for today draws its ring as
/// dots around a skip mark; a tap still checks it off, which lifts the skip.
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
      LorvexHabitRingTile(
        name: habit.name,
        symbol: LorvexSymbol.name(for: habit.icon, fallback: "repeat"),
        fraction: habit.target > 0 ? Double(habit.completedToday) / Double(habit.target) : 0,
        tint: LorvexHabitPalette.baseColor(id: habit.id, color: habit.color),
        diameter: 40, segments: habit.target,
        isSkipped: habit.isSkipped && !habit.isDoneToday)
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

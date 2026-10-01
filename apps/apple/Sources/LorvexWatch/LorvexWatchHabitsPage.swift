import LorvexCore
import LorvexWidgetKitSupport
import SwiftUI
#if canImport(UIKit)
  import UIKit
#endif
#if os(watchOS)
  import WatchKit
#endif

/// Today's habits as rings, two to a row (one at accessibility text sizes, so
/// names have the width to read): an open habit shows its own symbol in its
/// ring, a tap checks it off with a haptic, and a done habit fills green with
/// a check.
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
        LorvexTaskRing(
          progress: habit.target > 0 ? Double(habit.completedToday) / Double(habit.target) : 0,
          isDone: habit.isDoneToday, diameter: 40, showsCheckHint: false)
          .overlay {
            if !habit.isDoneToday {
              Image(systemName: Self.symbol(for: habit.icon))
                .font(LorvexDesign.Typography.secondaryText.weight(.semibold))
                .foregroundStyle(LorvexDesign.Palette.accent)
                .accessibilityHidden(true)
            }
          }
        Text(habit.name)
          .font(LorvexDesign.Typography.tertiaryText)
          .lineLimit(2)
          .multilineTextAlignment(.center)
      }
      .frame(maxWidth: .infinity)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(habit.name)
    .accessibilityValue(habit.isDoneToday ? LorvexWatchCalmCopy.done : "\(habit.completedToday)/\(habit.target)")
    .accessibilityIdentifier("watch.habit.\(habit.id)")
  }

  /// The habit's own SF Symbol when it names a real one, else a repeat mark:
  /// the icon is free text an assistant or the user sets, and an unknown name
  /// would draw an empty box.
  static func symbol(for icon: String?) -> String {
    guard let icon, !icon.isEmpty, icon.unicodeScalars.allSatisfy(\.isASCII) else { return "repeat" }
    #if canImport(UIKit)
      return UIImage(systemName: icon) == nil ? "repeat" : icon
    #else
      return icon
    #endif
  }
}

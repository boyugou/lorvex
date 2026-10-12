import LorvexCore
import SwiftUI
import Testing

@testable import LorvexApple

/// The habit inspector's action row at widths narrower than its one line,
/// as a long translation of the standing makes of the inspector's narrowest
/// width: the row grows taller instead of wider. A row wider than the
/// inspector pushes the inspector's close button and every panel's right edge
/// out of view.
@MainActor
@Suite("Habit inspector action row layout")
struct HabitDetailActionsLayoutTests {
  private func renderedSize<V: View>(_ view: V, width: CGFloat) -> CGSize {
    let renderer = ImageRenderer(content: view)
    renderer.proposedSize = ProposedViewSize(width: width, height: nil)
    return renderer.nsImage?.size ?? .zero
  }

  private func row(_ habit: LorvexHabit, store: AppStore) -> some View {
    HabitDetailActions(
      store: store, habit: habit, progress: HabitPeriodProgress.current(habit: habit),
      isChoosingAppearance: .constant(false))
  }

  private func habit(isSkipped: Bool = false) -> LorvexHabit {
    LorvexHabit(
      id: "h", name: "Run", icon: nil, color: nil, cue: nil, frequencyType: "daily",
      targetCount: 1, completionsToday: 0, totalCompletions: 0, completionRate30d: 0,
      archived: false, isSkipped: isSkipped)
  }

  @Test("A row too narrow for its one line stacks the standing over the chips instead of widening")
  func narrowRowStacks() throws {
    let store = AppStore(core: try makeInMemoryCore())
    let open = row(habit(), store: store)
    let roomy = renderedSize(open, width: 600)
    let narrow = renderedSize(open, width: 190)

    #expect(narrow.width <= 190, "the row is \(narrow.width) pt wide in 190 pt")
    #expect(narrow.height > roomy.height, "the standing moves above the chips")
  }

  @Test("A habit set aside for today stacks the same way")
  func skippedRowStacks() throws {
    let store = AppStore(core: try makeInMemoryCore())
    let skipped = row(habit(isSkipped: true), store: store)
    let roomy = renderedSize(skipped, width: 600)
    let narrow = renderedSize(skipped, width: 150)

    #expect(narrow.width <= 150, "the row is \(narrow.width) pt wide in 150 pt")
    #expect(narrow.height > roomy.height)
  }
}

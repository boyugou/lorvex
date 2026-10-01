import LorvexCore
import SwiftUI
import Testing

@testable import LorvexMobile

/// Habit row sizing at widths narrower than the row's text, as at
/// accessibility text sizes, measured by rendering through `ImageRenderer` at a
/// proposed width and reading the image's size.
@MainActor
@Suite("Habit summary layout")
struct MobileHabitSummaryLayoutTests {
  private func renderedSize<V: View>(_ view: V, width: CGFloat) -> CGSize {
    let renderer = ImageRenderer(content: view)
    renderer.proposedSize = ProposedViewSize(width: width, height: nil)
    return renderer.nsImage?.size ?? .zero
  }

  private let milestone = HabitMilestoneInfo(
    metric: "streak", value: 3, currentMilestone: nil, nextMilestone: 7,
    progressToNext: 3.0 / 7.0)

  private var habit: LorvexHabit {
    LorvexHabit(
      id: "h1", name: "Morning run", icon: nil, color: nil, cue: "After waking up",
      frequencyType: "daily", targetCount: 1, completionsToday: 1,
      totalCompletions: 3, completionRate30d: 0.1, archived: false,
      milestone: milestone)
  }

  @Test("A milestone line too narrow for its reading wraps it instead of widening")
  func milestoneLineWrapsItsReading() {
    let line = MobileHabitMilestoneProgressView(
      milestone: milestone, frequencyType: "daily", tint: .orange)
    let roomy = renderedSize(line, width: 2000)
    let narrow = renderedSize(line, width: 48)

    #expect(roomy.width > 48)
    #expect(narrow.width <= 48)
    #expect(narrow.height > roomy.height)
  }

  @Test("A habit summary grows taller, never wider than the width its row offers")
  func summaryStaysInsideItsRow() {
    let summary = MobileHabitSummary(habit: habit)
    let roomy = renderedSize(summary, width: 2000)
    let narrow = renderedSize(summary, width: 100)

    #expect(roomy.width > 100)
    #expect(narrow.width <= 100)
    #expect(narrow.height > roomy.height)
  }
}

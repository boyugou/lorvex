import LorvexCore
import Testing

/// The segmented look of a habit's check-in ring: one arc per check-in for a habit
/// kept two to twelve times a day, the same on every surface.
@Suite("Ring segments")
struct RingSegmentsTests {
  @Test("two to twelve check-ins draw as separate arcs; any other count is one continuous ring")
  func segmentedRange() {
    for count in [-1, 0, 1, 13, 24] { #expect(!LorvexRingSegments.isSegmented(count), "\(count)") }
    for count in [2, 3, 8, 12] { #expect(LorvexRingSegments.isSegmented(count), "\(count)") }
  }

  @Test("the fraction fills as many arcs as it covers, rounded to the nearest")
  func filledSegments() {
    func filled(_ segments: Int, _ fraction: Double) -> Int {
      LorvexRingSegments(
        segments: segments, fraction: fraction, tint: .init(.green), lineWidth: 3, diameter: 34
      ).filledSegments
    }
    #expect(filled(3, 0) == 0)
    #expect(filled(3, 1.0 / 3.0) == 1)
    #expect(filled(3, 2.0 / 3.0) == 2)
    #expect(filled(8, 3.0 / 8.0) == 3)
    #expect(filled(4, 1) == 4)
    #expect(filled(4, 7) == 4, "a fraction past one fills them all")
    #expect(filled(4, -1) == 0)
  }

  @Test("a habit's ring counts its per-day target, whatever its cadence, and never fewer than one")
  func habitSegments() {
    func habit(_ target: Int, _ frequency: String = "daily") -> LorvexHabit {
      LorvexHabit(
        id: "h", name: "H", icon: nil, color: nil, cue: nil, frequencyType: frequency,
        targetCount: target, completionsToday: 0, totalCompletions: 0, completionRate30d: 0,
        archived: false)
    }
    #expect(habit(1).ringSegments == 1)
    #expect(habit(8).ringSegments == 8)
    #expect(habit(3, "weekly").ringSegments == 3)
    #expect(habit(0).ringSegments == 1)
  }
}

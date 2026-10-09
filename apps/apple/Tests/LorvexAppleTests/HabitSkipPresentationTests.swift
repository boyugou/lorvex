import Foundation
import LorvexCore
import SwiftUI
import Testing

@testable import LorvexApple
@testable import LorvexMobile

@Suite("Habit skip presentation")
struct HabitSkipPresentationTests {
  private func habit(
    frequencyType: String = "daily", completionsToday: Int = 0, isSkipped: Bool = false
  ) -> LorvexHabit {
    LorvexHabit(
      id: "h-\(frequencyType)-\(completionsToday)-\(isSkipped)", name: "Cardio", icon: nil, color: nil,
      cue: nil, frequencyType: frequencyType, targetCount: 1, completionsToday: completionsToday,
      totalCompletions: 0, completionRate30d: 0, archived: false, isSkipped: isSkipped)
  }

  @Test("The skip control follows the day's state: skip, undo, or none once checked in")
  func actionFollowsTheDay() {
    #expect(LorvexHabitSkip.action(for: habit()) == .skip)
    #expect(LorvexHabitSkip.action(for: habit(isSkipped: true)) == .unskip)
    #expect(LorvexHabitSkip.action(for: habit(completionsToday: 1)) == nil)
    #expect(LorvexHabitSkip.action(for: habit(frequencyType: "weekly")) == .skip)
  }

  @Test("Both surfaces name the commands apart and share one glyph per command")
  func copyNamesTheCommands() {
    #expect(MobileHabitSkipCopy.title(for: .skip) == MobileHabitSkipCopy.skipToday)
    #expect(MobileHabitSkipCopy.title(for: .unskip) == MobileHabitSkipCopy.undoSkip)
    #expect(MobileHabitSkipCopy.skipToday != MobileHabitSkipCopy.undoSkip)
    #expect(HabitSkipText.title(for: .skip) == HabitSkipText.skipToday)
    #expect(HabitSkipText.title(for: .unskip) == HabitSkipText.undoSkip)
    #expect(HabitSkipText.skipToday != HabitSkipText.undoSkip)
    #expect(MobileHabitSkipCopy.systemImage(for: .skip) == HabitSkipText.systemImage(for: .skip))
    #expect(MobileHabitSkipCopy.systemImage(for: .unskip) == LorvexHabitSkip.undoGlyph)
    #expect(HabitSkipText.systemImage(for: .skip) != HabitSkipText.systemImage(for: .unskip))
    // The skipped state's mark is not the command's glyph, and not a moon, which
    // marks the Someday status.
    #expect(LorvexHabitSkip.glyph == "forward.fill")
    #expect(!LorvexHabitSkip.glyph.contains("moon"))
  }

  @Test("A skipped habit's caption leads with the state, ahead of its count and cue")
  func captionLeadsWithTheSkippedState() {
    let skipped = MobileHabitSkipCopy.skippedToday
    var cued = habit(isSkipped: true)
    cued.cue = "After meals"
    #expect(MobileHabitSummary.caption(for: cued) == "\(skipped) · After meals")
    #expect(MobileHabitSummary.caption(for: habit(isSkipped: true)) == skipped)
    var counted = habit(isSkipped: true)
    counted.targetCount = 3
    #expect(MobileHabitSummary.caption(for: counted) == skipped)
    #expect(MobileHabitSummary.caption(for: habit()) == nil)
  }

  private func dotCount(_ path: Path) -> Int {
    var moves = 0
    path.forEach { element in
      if case .move = element { moves += 1 }
    }
    return moves
  }

  @Test("The dotted ring draws at least eight dots, more on a larger ring, none when it cannot fit")
  func dottedRingDotCount() {
    let floor = LorvexDottedRing(dotDiameter: 2).path(in: CGRect(x: 0, y: 0, width: 8, height: 8))
    let small = LorvexDottedRing(dotDiameter: 2).path(in: CGRect(x: 0, y: 0, width: 16, height: 16))
    let card = LorvexDottedRing(dotDiameter: 4).path(in: CGRect(x: 0, y: 0, width: 46, height: 46))
    let large = LorvexDottedRing(dotDiameter: 4).path(in: CGRect(x: 0, y: 0, width: 92, height: 92))
    #expect(dotCount(floor) == 8)
    #expect(dotCount(small) < dotCount(card))
    #expect(dotCount(card) < dotCount(large))
    #expect(LorvexDottedRing(dotDiameter: 0).path(in: CGRect(x: 0, y: 0, width: 46, height: 46)).isEmpty)
    #expect(LorvexDottedRing(dotDiameter: 30).path(in: CGRect(x: 0, y: 0, width: 46, height: 46)).isEmpty)
  }

  @Test("The first dot sits at the top of the circle a solid stroke of the same width follows")
  func dottedRingFirstDotLiesOnTheTrack() {
    let rect = CGRect(x: 10, y: 20, width: 46, height: 46)
    let path = LorvexDottedRing(dotDiameter: 4).path(in: rect)
    let top = CGPoint(x: rect.midX, y: rect.midY - rect.width / 2)
    #expect(path.contains(top))
    #expect(path.contains(CGPoint(x: top.x, y: top.y - 1.5)))
    #expect(!path.contains(CGPoint(x: top.x, y: top.y + 3)))
    #expect(!path.contains(CGPoint(x: rect.midX, y: rect.midY)))
  }

  @Test("A daily habit set aside for today counts toward neither the done nor the total")
  func workspaceTallyExcludesSkippedDailyHabits() {
    let open = habit()
    var skipped = habit(isSkipped: true)
    skipped.id = "skipped"
    var done = habit(completionsToday: 1)
    done.id = "done"
    var weeklySkipped = habit(frequencyType: "weekly", isSkipped: true)
    weeklySkipped.id = "weekly-skipped"
    let stats = HabitsWorkspaceStats(
      habits: [open, skipped, done, weeklySkipped],
      onTrack: [open.id: false, done.id: true, skipped.id: false, weeklySkipped.id: false])
    #expect(
      stats.buckets == [
        .init(cadence: .daily, completed: 1, total: 2),
        .init(cadence: .weekly, completed: 0, total: 1),
      ])

    var onlySkipped = habit(isSkipped: true)
    onlySkipped.id = "only"
    #expect(HabitsWorkspaceStats(habits: [onlySkipped], onTrack: [:]).buckets.isEmpty)
  }
}

import LorvexCore
import Testing

@testable import LorvexMobile

private func habit(cue: String?, done: Int, target: Int) -> LorvexHabit {
  LorvexHabit(
    id: "h", name: "Drink water", icon: nil, color: nil, cue: cue, frequencyType: "daily",
    targetCount: target, completionsToday: done, totalCompletions: 0, completionRate30d: 0,
    archived: false)
}

@Test("A habit row names its cue, and today's count only for a habit of several check-ins a day")
func habitCaptionNamesCueAndOnlyAMultiCheckInCount() {
  #expect(MobileHabitSummary.caption(for: habit(cue: "After meals", done: 0, target: 1)) == "After meals")
  #expect(MobileHabitSummary.caption(for: habit(cue: nil, done: 1, target: 1)) == nil)
  #expect(MobileHabitSummary.caption(for: habit(cue: "", done: 0, target: 1)) == nil)
  #expect(
    MobileHabitSummary.caption(for: habit(cue: "After meals", done: 2, target: 3)) == "2/3 today · After meals")
  #expect(MobileHabitSummary.caption(for: habit(cue: nil, done: 2, target: 3)) == "2/3 today")
}

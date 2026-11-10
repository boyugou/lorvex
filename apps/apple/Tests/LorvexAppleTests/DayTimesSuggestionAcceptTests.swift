import Foundation
import LorvexCore
import Testing

@testable import LorvexApple
@testable import LorvexMobile

/// A suggestion is drawn against the day as it stood when it was asked for.
/// Accepting it stores times for the day as it stands at that moment.
@Suite("Accepting suggested times keeps what changed since they were suggested")
struct DayTimesSuggestionAcceptTests {
  private func task(_ id: String) -> LorvexTask {
    LorvexTask(
      id: id, title: id, notes: "", priority: .p2, status: .open,
      dueDate: nil, estimatedMinutes: nil, tags: [])
  }

  private func proposal(_ placements: [(String, Range<Int>)]) -> DayTimesProposal {
    DayTimesProposal(
      date: "2026-03-06", workingHours: 540..<1020, availableMinutes: 480,
      placements: placements.map { .init(task: task($0.0), time: $0.1) })
  }

  private func stored(_ times: [LorvexTaskTime]) -> [String: Range<Int>] {
    Dictionary(uniqueKeysWithValues: times.map { ($0.taskID, $0.time) })
  }

  @Test
  func anUntouchedDayTakesTheSuggestionWhole() {
    let suggestion = proposal([("a", 540..<570), ("b", 570..<600)])
    let times = suggestion.timesToStore(
      timedWhenSuggested: ["a": 600..<630], timedNow: ["a": 600..<630],
      unfinishedToday: ["a", "b"])
    #expect(times == suggestion.times)
  }

  @Test
  func aTimeSetSinceTheSuggestionIsKept() {
    let suggestion = proposal([("a", 540..<570), ("b", 570..<600)])
    let times = suggestion.timesToStore(
      timedWhenSuggested: [:], timedNow: ["b": 900..<930, "c": 960..<990],
      unfinishedToday: ["a", "b", "c"])
    // `b` was re-timed by hand and `c` was timed by hand; `a` takes its suggestion.
    #expect(stored(times) == ["a": 540..<570, "b": 900..<930, "c": 960..<990])
  }

  @Test
  func aTimeClearedSinceTheSuggestionStaysCleared() {
    let suggestion = proposal([("a", 540..<570)])
    let times = suggestion.timesToStore(
      timedWhenSuggested: ["a": 600..<630], timedNow: [:], unfinishedToday: ["a"])
    #expect(times.isEmpty)
  }

  @Test
  func aTaskThatLeftTheDayIsNotPulledBack() {
    let suggestion = proposal([("a", 540..<570), ("done", 570..<600)])
    let times = suggestion.timesToStore(
      timedWhenSuggested: [:], timedNow: [:], unfinishedToday: ["a"])
    #expect(stored(times) == ["a": 540..<570])
  }

  @Test
  func aTaskTheSuggestionLeftOutLosesAnUnchangedTime() {
    // Timed before the suggestion, not placed by it, and untouched since: the
    // suggestion replaces the day's times, as it always has.
    let suggestion = proposal([("a", 540..<570)])
    let times = suggestion.timesToStore(
      timedWhenSuggested: ["old": 600..<630], timedNow: ["old": 600..<630],
      unfinishedToday: ["a", "old"])
    #expect(stored(times) == ["a": 540..<570])
  }

  @MainActor
  @Test
  func theIPhoneKeepsATimeSetAfterSuggest() async throws {
    let core = try await makeSeededInMemoryCore()
    let today = try await core.loadToday()
    let date = try #require(today.logicalDay)
    let store = MobileStore(core: core, todayString: { date })
    await store.refresh()

    await store.suggestDayTimes()
    let suggestion = try #require(store.proposedDayTimes)
    let placed = try #require(suggestion.placements.first)

    // Another writer times that task for the evening after the suggestion.
    let evening = 1200..<1230
    _ = try await core.saveDayTimes(
      date: date, times: [LorvexTaskTime(taskID: placed.task.id, time: evening)])

    await store.useSuggestedDayTimes()

    #expect(store.proposedDayTimes == nil)
    #expect(try await core.loadTask(id: placed.task.id).plannedTime == evening)
    for other in suggestion.placements.dropFirst() {
      #expect(try await core.loadTask(id: other.task.id).plannedTime == other.time)
    }
    #expect(store.errorMessage == nil)
  }

  @MainActor
  @Test
  func theMacKeepsATimeSetAfterSuggest() async throws {
    let core = try await makeSeededInMemoryCore()
    let store = AppStore(core: core)
    await store.refresh()
    let date = store.logicalTodayDateString

    await store.suggestDayTimes()
    let suggestion = try #require(store.proposedDayTimes)
    let placed = try #require(suggestion.placements.first)

    let evening = 1200..<1230
    _ = try await core.saveDayTimes(
      date: date, times: [LorvexTaskTime(taskID: placed.task.id, time: evening)])

    await store.acceptSuggestedDayTimes(undoManager: nil)

    #expect(store.proposedDayTimes == nil)
    #expect(try await core.loadTask(id: placed.task.id).plannedTime == evening)
    for other in suggestion.placements.dropFirst() {
      #expect(try await core.loadTask(id: other.task.id).plannedTime == other.time)
    }
    #expect(store.errorMessage == nil)
  }

  @MainActor
  @Test
  func aSuggestionForADayThatEndedIsDropped() async throws {
    let core = try await makeSeededInMemoryCore()
    let store = AppStore(core: core)
    await store.refresh()
    await store.suggestDayTimes()
    var suggestion = try #require(store.proposedDayTimes)
    let placed = try #require(suggestion.placements.first)
    suggestion.date = "2000-01-01"
    store.proposedDayTimes = suggestion

    await store.acceptSuggestedDayTimes(undoManager: nil)

    #expect(store.proposedDayTimes == nil)
    #expect(try await core.loadTask(id: placed.task.id).plannedTime == placed.task.plannedTime)
  }
}

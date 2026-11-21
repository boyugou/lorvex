import Foundation
import Testing

@testable import LorvexCore

@Suite("Weekly journal follow-up")
struct WeekJournalFollowUpTests {
  @Test("A selected blocker from a summary-less historical entry becomes a planned task")
  func planFromJournal() async throws {
    let core = try SwiftLorvexCoreService.inMemory()
    let sourceDay = "2024-12-31"
    let journal = try await core.importDailyReview(date: sourceDay, summary: "", mood: nil,
      energyLevel: nil, wins: "Fixed the build", blockers: "Waiting on design\n\n约不到评审时间。",
      learnings: "Book the room first")
    let history = try await core.getReviewHistory(from: sourceDay, to: sourceDay, limit: 7)
    let entry = try #require(history.first)
    #expect(WeekJournalScope.blockers.includes(entry))
    var ratingsOnly = entry
    ratingsOnly.blockers = "   "
    ratingsOnly.wins = nil
    ratingsOnly.learnings = nil
    ratingsOnly.mood = 4
    #expect(WeekJournalScope.allCases.filter { $0.includes(ratingsOnly) } == [.all])
    #expect(entry.wins == "Fixed the build")
    #expect(entry.learnings == "Book the room first")
    let blockers = ReviewBlocker.entries(in: entry)
    #expect(blockers.map(\.text) == ["Waiting on design", "约不到评审时间。"])
    let choice = try #require(blockers.last)
    let monday = try #require(ReviewBlocker.nextMonday(after: "2026-12-31"))
    #expect(choice.draft(title: "  ", plannedDate: monday) == nil)
    let title = "Ask #design about Friday at 3"
    let draft = try #require(choice.draft(title: title, plannedDate: monday))
    let created = try await core.createTask(draft)
    let nextWeek = try await LorvexAgendaDay.loadWeek(after: "2026-12-31", from: core)
    let planned = try #require(nextWeek.first { $0.key == "2027-01-04" }?.tasks.first)
    #expect(planned.id == created.id)
    #expect(planned.title == title)
    #expect(planned.dueDate == nil)
    #expect(planned.tags.isEmpty)
    #expect(planned.notes.contains(sourceDay))
    #expect(planned.notes.hasSuffix(choice.text))
    #expect(!planned.notes.contains("Waiting on design"))
    #expect(try await core.loadDailyReview(date: sourceDay) == journal)
  }

  @Test("Next Monday is strictly ahead even on Monday, across DST and year boundaries",
    arguments: [("2026-11-01", "2026-11-02"), ("2026-11-02", "2026-11-09"),
      ("2026-12-31", "2027-01-04"), ("2026-03-07", "2026-03-09")])
  func nextMonday(today: String, expected: String) throws {
    let day = try #require(ReviewBlocker.nextMonday(after: today))
    #expect(LorvexDateFormatters.ymdUTC.string(from: day) == expected)
  }
}

import Foundation
import LorvexCore
import Testing

@Test func journalPhraseReachesOlderDaysAndPaginatesDistinctMatches() async throws {
  let core = try makeInMemoryCore()
  let first = "2025-01-01"
  func day(_ offset: Int) throws -> String {
    try #require(LorvexDateFormatters.ymdUTCAddingDays(first, days: offset))
  }
  for index in 0..<85 {
    _ = try await core.importDailyReview(date: day(index), summary: index == 0 ? "Café filter" : "",
      mood: nil, energyLevel: nil, wins: index == 1 ? "The café filter held." : nil,
      blockers: index == 2 ? "Order CAFÉ\n filter and 50%_paper." : nil,
      learnings: index == 3 ? "Use the café filter once." : nil,
      timezone: nil, updatedAt: nil, linkedTaskIDs: nil, linkedListIDs: nil)
  }
  let through = try day(84)
  let page = try await core.searchReviewJournal(" cafe  filter ", through: through, limit: 2)
  #expect(page.matches.map(\.date) == (try [day(3), day(2)]))
  #expect(page.matches.map(\.field) == [.learnings, .blockers])
  #expect(String(page.matches[1].excerpt.characters).contains("CAFÉ filter"))
  let older = try await core.searchReviewJournal("cafe filter", through: #require(page.nextThrough), limit: 2)
  #expect(older.matches.map(\.date) == (try [day(1), day(0)]))
  #expect(older.nextThrough == nil)
  let literal = try await core.searchReviewJournal("%_", through: through)
  #expect(literal.matches.map(\.date) == (try [day(2)]))
  #expect(try await core.searchReviewJournal("   ", through: through).matches.isEmpty)
}

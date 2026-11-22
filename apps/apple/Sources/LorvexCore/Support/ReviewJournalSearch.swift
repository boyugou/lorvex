import Foundation

/// One day in the journal, quoted from the field that contained the phrase.
public struct ReviewJournalMatch: Identifiable, Equatable, Sendable {
  public enum Field: Equatable, Sendable { case note, wins, blockers, learnings }

  public let date: String
  public let field: Field
  public let excerpt: AttributedString
  public var id: String { date }

  public static func find(_ phrase: String, in entry: DailyReviewEntry) -> Self? {
    let fields: [(Field, String?)] = [
      (.note, entry.summary), (.wins, entry.wins), (.blockers, entry.blockers), (.learnings, entry.learnings),
    ]
    for (field, source) in fields {
      guard let source else { continue }
      let text = source.split(whereSeparator: \.isWhitespace).joined(separator: " ")
      if let quote = LorvexTaskSearchMatch.excerpt(of: phrase, in: text, field: .notes) {
        return Self(date: entry.date, field: field, excerpt: quote.attributedExcerpt)
      }
    }
    return nil
  }
}

public struct ReviewJournalSearchPage: Sendable {
  public let matches: [ReviewJournalMatch]
  /// Inclusive upper bound for the next history scan.
  public let nextThrough: String?
}

extension LorvexReviewServicing {
  /// Scan dated pages so a rare phrase can reach the oldest entry without
  /// materializing the whole journal. Newer writes cannot shift date cursors.
  public func searchReviewJournal(_ query: String, through day: String, limit: Int = 30) async throws
    -> ReviewJournalSearchPage
  {
    let phrase = query.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    var matches: [ReviewJournalMatch] = []
    var through = day
    let batchSize = 64
    guard !phrase.isEmpty, limit > 0 else { return .init(matches: [], nextThrough: nil) }
    while true {
      try Task.checkCancellation()
      let entries = try await getReviewHistory(from: nil, to: through, limit: batchSize)
      for entry in entries {
        try Task.checkCancellation()
        if let match = ReviewJournalMatch.find(phrase, in: entry) {
          // Look ahead to an actual hit before offering another page.
          if matches.count == limit { return .init(matches: matches, nextThrough: match.date) }
          matches.append(match)
        }
      }
      guard entries.count == batchSize, let oldest = entries.last?.date,
        let previous = LorvexDateFormatters.ymdUTCAddingDays(oldest, days: -1), previous < through
      else { return .init(matches: matches, nextThrough: nil) }
      through = previous
    }
  }
}

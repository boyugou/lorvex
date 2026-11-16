/// What a day's review sentence says, in order, before any wording. Each
/// platform words the parts with its own copy table, so the macOS and iPhone
/// reviews never disagree about what the day was.
public enum LorvexReviewSentence {
  public enum Part: Equatable, Sendable {
    /// Nothing happened: no tasks, events, due work, or habits.
    case quiet
    case finished(Int)
    case nothingFinished
    /// Tasks due that day that are still open.
    case stillDue(Int)
    case habitsAll
    case habitsSome(kept: Int, total: Int)
    case habitsNone
  }

  public static func parts(_ summary: DayReviewSummary) -> [Part] {
    if summary.completedCount == 0, summary.dueOpenCount == 0, summary.eventCount == 0,
      summary.habitsTotal == 0
    {
      return [.quiet]
    }
    var parts: [Part] = [summary.completedCount > 0 ? .finished(summary.completedCount) : .nothingFinished]
    if summary.dueOpenCount > 0 { parts.append(.stillDue(summary.dueOpenCount)) }
    if summary.habitsTotal > 0 {
      switch summary.habitsCompleted {
      case summary.habitsTotal...: parts.append(.habitsAll)
      case 0: parts.append(.habitsNone)
      default: parts.append(.habitsSome(kept: summary.habitsCompleted, total: summary.habitsTotal))
      }
    }
    return parts
  }

  /// Joins the worded sentences of a day or week review as their language
  /// writes them: a space after a sentence that ends in Western punctuation
  /// ("You finished 3 tasks. 1 due task is still open."), nothing after a
  /// full-width mark, whose glyph already carries the gap
  /// ("你完成了 3 项任务。还有 1 项到期任务没完成。").
  public static func join(_ sentences: [String]) -> String {
    sentences.reduce(into: "") { text, sentence in
      guard !sentence.isEmpty else { return }
      if let last = text.last, !fullWidthSentenceEnds.contains(last) { text.append(" ") }
      text.append(sentence)
    }
  }

  private static let fullWidthSentenceEnds: Set<Character> = ["。", "！", "？", "」", "』", "）"]
}

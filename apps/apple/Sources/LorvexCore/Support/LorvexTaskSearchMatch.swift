import Foundation

/// Why a task is in a search result when its title does not show the match:
/// the text around the first search term that nothing visible on the row
/// explains, taken from the task field that holds it.
///
/// Platform-neutral so the macOS row, the command palette, and the iOS row
/// draw the same explanation. The excerpt is one line: whitespace runs and
/// line breaks in the source collapse to single spaces. A source of 64
/// characters or fewer is quoted whole; a longer one is cut to a window around
/// the match, on a word boundary where the text has words, with an ellipsis
/// marking each cut end.
public struct LorvexTaskSearchMatch: Equatable, Sendable {
  /// The task field the excerpt comes from.
  public enum Field: Equatable, Sendable {
    case notes
    case tags
    case assistantContext
  }

  public let field: Field
  /// The text before the match; begins with an ellipsis when the excerpt
  /// starts inside the source text.
  public let before: String
  /// The matched term as the task writes it. Empty when only the folded
  /// comparison found the term (an accent, width, or letter-form difference
  /// the range search cannot locate); `before` is then empty too and `after`
  /// is the start of the source text.
  public let matched: String
  /// The text after the match; ends with an ellipsis when the excerpt stops
  /// inside the source text.
  public let after: String

  /// The excerpt as plain text.
  public var text: String { before + matched + after }

  /// The excerpt with the matched term in bold, ready for `Text`.
  public var attributedExcerpt: AttributedString {
    var excerpt = AttributedString(before)
    var term = AttributedString(matched)
    term.inlinePresentationIntent = .stronglyEmphasized
    excerpt.append(term)
    excerpt.append(AttributedString(after))
    return excerpt
  }

  /// The longest source quoted whole.
  static let wholeTextLimit = 64
  /// Characters kept before the match when the source is longer than the limit.
  static let leadingContext = 18
  /// Characters kept after the match when the source is longer than the limit.
  static let trailingContext = 44

  /// The excerpt of `source` around the first occurrence of `term`, or `nil`
  /// when `source` does not contain the term.
  static func excerpt(of term: String, in source: String, field: Field) -> LorvexTaskSearchMatch? {
    guard source.containsSearchTerm(term) else { return nil }
    let text = source.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    guard let range = text.localizedStandardRange(of: term) else {
      return LorvexTaskSearchMatch(
        field: field, before: "", matched: "",
        after: window(of: text, from: text.startIndex, to: text.startIndex).after)
    }
    let (before, after) = window(of: text, from: range.lowerBound, to: range.upperBound)
    return LorvexTaskSearchMatch(
      field: field, before: before, matched: String(text[range]), after: after)
  }

  /// The text kept before `lower` and after `upper`, each snapped to a word
  /// boundary when it cuts the source and marked with an ellipsis.
  private static func window(
    of text: String, from lower: String.Index, to upper: String.Index
  ) -> (before: String, after: String) {
    if text.count <= wholeTextLimit { return (String(text[..<lower]), String(text[upper...])) }
    var start = text.index(lower, offsetBy: -leadingContext, limitedBy: text.startIndex) ?? text.startIndex
    if start > text.startIndex, text[text.index(before: start)] != " ",
      let space = text[start..<lower].firstIndex(of: " ")
    {
      start = text.index(after: space)
    }
    let leadingCut = start > text.startIndex

    var end = text.index(upper, offsetBy: trailingContext, limitedBy: text.endIndex) ?? text.endIndex
    let trailingCut = end < text.endIndex
    if trailingCut, let space = text[upper..<end].lastIndex(of: " "), space > upper {
      end = space
    }
    let before = (leadingCut ? "…" : "") + String(text[start..<lower])
    let after = String(text[upper..<end]) + (trailingCut ? "…" : "")
    return (before, after)
  }
}

extension LorvexTask {
  /// The excerpt that explains why `query` finds this task, or `nil` when the
  /// title already shows every term, a tag the row shows explains the rest, or
  /// no field holds a term the title lacks.
  ///
  /// The first query term the title lacks decides the excerpt. A tag among
  /// the first `visibleTagCount` is on the row already, so a term it holds
  /// needs no excerpt and the next such term is considered. Otherwise the term
  /// is looked up in the notes, then in the hidden tags, then in the assistant
  /// context, and the first field holding it supplies the text. Term matching
  /// is ``String/containsSearchTerm(_:)``, the comparison task search uses.
  public func searchMatch(for query: String, visibleTagCount: Int = 0) -> LorvexTaskSearchMatch? {
    let visibleTags = tags.prefix(max(visibleTagCount, 0))
    let hiddenTags = tags.dropFirst(max(visibleTagCount, 0))
    for term in query.split(whereSeparator: \.isWhitespace).map(String.init)
    where !title.containsSearchTerm(term) && !visibleTags.contains(where: { $0.containsSearchTerm(term) }) {
      if let match = LorvexTaskSearchMatch.excerpt(of: term, in: notes, field: .notes) { return match }
      for tag in hiddenTags {
        if let match = LorvexTaskSearchMatch.excerpt(of: term, in: tag, field: .tags) { return match }
      }
      if let aiNotes,
        let match = LorvexTaskSearchMatch.excerpt(of: term, in: aiNotes, field: .assistantContext)
      {
        return match
      }
    }
    return nil
  }
}

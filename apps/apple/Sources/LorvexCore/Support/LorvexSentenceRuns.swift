import Foundation

/// A piece of a sentence drawn as separate views: connecting text, which
/// carries its own spaces and punctuation (" for ", ", due ", "。"), or a value
/// word the user taps to change.
public protocol LorvexSentenceToken: Identifiable where ID == String {
  /// The connecting text, or `nil` for a value word.
  var connectingText: String? { get }
}

/// A run of sentence pieces that a flow layout keeps on one line, so a
/// sentence of separate views breaks where set type would: at any space in
/// the connecting text, never before closing punctuation, never between a
/// value and a suffix written onto it, and never with a space opening the
/// next line.
///
/// ``runs(_:)`` starts a new run before each value word and after each space
/// in connecting text (", due " becomes ", " and "due "), except that:
/// - text opening with closing punctuation joins the run before it, so no line
///   starts with "," or "。";
/// - text written onto a value word with no space between them joins that
///   word's run (Chinese 高 + 优先级, "high priority");
/// - text opening with spaces leaves them at the end of the run before it and
///   starts its own run with the rest, so the line breaks at the space and the
///   next line does not start indented by it.
///
/// A space that does not allow a line break (no-break, narrow no-break, and
/// figure spaces) never splits a run.
public struct LorvexSentenceRun<Token: LorvexSentenceToken>: Identifiable {
  public enum Piece: Identifiable {
    /// A value word, drawn by the caller.
    case word(Token)
    /// Connecting text. `closesUp` is true when it opens with punctuation
    /// directly after a value word, so it may tuck into that word's padding
    /// the way punctuation sits in set type.
    case text(id: String, String, closesUp: Bool)
    /// The spaces that end a run: invisible at the end of a line, and nothing
    /// for VoiceOver to stop on.
    case space(id: String, String)

    public var id: String {
      switch self {
      case .word(let token): token.id
      case .text(let id, _, _), .space(let id, _): id
      }
    }
  }

  public private(set) var pieces: [Piece]

  public var id: String { pieces.first?.id ?? "" }

  public static func runs(_ tokens: [Token]) -> [LorvexSentenceRun] {
    var runs: [LorvexSentenceRun] = []
    for token in tokens {
      guard let text = token.connectingText else {
        runs.append(LorvexSentenceRun(pieces: [.word(token)]))
        continue
      }
      var remainder = Substring(text)
      let spaces = remainder.prefix(while: isBreakingSpace)
      let movedSpaces = !spaces.isEmpty && !runs.isEmpty
      if movedSpaces {
        runs[runs.count - 1].pieces.append(.space(id: "\(token.id).space", String(spaces)))
        remainder = remainder.dropFirst(spaces.count)
      }
      for (index, segment) in segments(remainder).enumerated() {
        let id = index == 0 ? token.id : "\(token.id).\(index)"
        let followsWord = if case .word = runs.last?.pieces.last { true } else { false }
        let opensWithPunctuation = segment.first.map(isClosingPunctuation) ?? false
        if index == 0, !movedSpaces, opensWithPunctuation || followsWord, !runs.isEmpty {
          runs[runs.count - 1].pieces.append(
            .text(id: id, String(segment), closesUp: opensWithPunctuation && followsWord))
        } else {
          runs.append(LorvexSentenceRun(pieces: [.text(id: id, String(segment), closesUp: false)]))
        }
      }
    }
    return runs
  }

  /// `text` cut after each stretch of breaking spaces that follows other
  /// characters, each piece keeping its trailing spaces: ", due " becomes
  /// ", " and "due ", " Due " stays whole.
  private static func segments(_ text: Substring) -> [Substring] {
    var segments: [Substring] = []
    var start = text.startIndex
    var hasText = false
    var index = text.startIndex
    while index < text.endIndex {
      let isSpace = isBreakingSpace(text[index])
      if !isSpace, hasText, isBreakingSpace(text[text.index(before: index)]) {
        segments.append(text[start..<index])
        start = index
      }
      if !isSpace { hasText = true }
      index = text.index(after: index)
    }
    if start < text.endIndex { segments.append(text[start...]) }
    return segments
  }

  /// Whitespace a line may break at: every whitespace character except the
  /// no-break, narrow no-break, and figure spaces.
  private static func isBreakingSpace(_ character: Character) -> Bool {
    character.isWhitespace && !"\u{00A0}\u{202F}\u{2007}".contains(character)
  }

  /// Punctuation that closes up against the text before it and may not start
  /// a line, in Latin and in CJK text.
  private static func isClosingPunctuation(_ character: Character) -> Bool {
    ",.;:!?)，。；：、！？）」』".contains(character)
  }
}

extension LorvexSentenceRun.Piece: Equatable where Token: Equatable {}
extension LorvexSentenceRun: Equatable where Token: Equatable {}

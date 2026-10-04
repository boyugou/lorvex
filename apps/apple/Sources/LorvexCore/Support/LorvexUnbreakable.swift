import Foundation

/// `text` with its spaces made no-break, so a label, a duration, or a date
/// wraps as one unit, except after a dash, so a range ("9:45 – 10:30 AM",
/// "Sep 27 – Oct 3") breaks only after its dash and never starts a line with
/// it. The interval formatters set thin spaces around the dash; the one
/// before it becomes a narrow no-break space. Chinese text still breaks
/// between its characters, as Chinese text does.
public func lorvexUnbreakable(_ text: String) -> String {
  text
    .replacingOccurrences(of: " ", with: "\u{00A0}")
    .replacingOccurrences(of: "–\u{00A0}", with: "– ")
    .replacingOccurrences(of: "\u{2009}–", with: "\u{202F}–")
}

/// `text` kept on one line wherever it is set: its spaces made no-break and
/// each dash or tilde joined to both neighbours with a word joiner (U+2060),
/// so a time span beside other words ("Today, 9:45 – 10:30 AM",
/// "Сегодня, 09:45—10:45") moves to the next line whole instead of breaking
/// after its dash. Only for spans short enough to always fit a line on their
/// own; a span of days goes through ``lorvexUnbreakable(_:)``, which still
/// lets it break after its dash.
public func lorvexWholeSpan(_ text: String) -> String {
  var result = ""
  for character in text {
    switch character {
    case " ":
      result.append("\u{00A0}")
    case "\u{2009}":
      result.append("\u{202F}")
    case "-", "–", "—", "~", "〜", "～":
      result.append("\u{2060}")
      result.append(character)
      result.append("\u{2060}")
    default:
      result.append(character)
    }
  }
  return result
}

/// `text` with the space after each number made no-break, so a count never
/// ends a line apart from the word it counts: "...came in. 16 tasks are
/// overdue." wraps before "16", not between "16" and "tasks". A number is a run
/// of decimal digits in any script, and only a plain space between a number and
/// a letter is tied; a number before a dash, a dot, or any other mark, and every
/// other space, still breaks normally.
public func lorvexNumbersTied(_ text: String) -> String {
  let characters = Array(text)
  var result = ""
  for (index, character) in characters.enumerated() {
    let endsNumber =
      index > 0 && characters[index - 1].unicodeScalars.allSatisfy { $0.properties.generalCategory == .decimalNumber }
    let startsWord = index + 1 < characters.count && characters[index + 1].isLetter
    result.append(character == " " && endsNumber && startsWord ? "\u{00A0}" : character)
  }
  return result
}

/// `facts` joined by dots, with a no-break space tying each dot to the fact
/// before it, so a line that wraps breaks after a dot and never starts with
/// one. Facts passed through ``lorvexUnbreakable(_:)`` first stay whole as
/// well.
public func lorvexDotJoined(_ facts: [String]) -> String {
  facts.joined(separator: "\u{00A0}· ")
}

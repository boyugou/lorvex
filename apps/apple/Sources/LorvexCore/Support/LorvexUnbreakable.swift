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

/// `facts` joined by dots, with a no-break space tying each dot to the fact
/// before it, so a line that wraps breaks after a dot and never starts with
/// one. Facts passed through ``lorvexUnbreakable(_:)`` first stay whole as
/// well.
public func lorvexDotJoined(_ facts: [String]) -> String {
  facts.joined(separator: "\u{00A0}· ")
}

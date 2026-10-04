import Foundation

/// `sentence` with a doubled final period reduced to one.
///
/// A sentence template carries its own full stop, and a formatted value placed
/// last in it can end in a period of its own: the Polish hour abbreviation in
/// "około 11 godz.", the Portuguese minutes in "há 5 min.", the Spanish clock
/// in "5:00 p.m.". Composed as written, the sentence would end in two periods.
/// An abbreviation's period doubles as the sentence's full stop, so one of the
/// two is dropped. Exactly two periods at the very end collapse; an ellipsis of
/// three or more dots, a single period, and text that ends in any other mark
/// are returned unchanged.
public func lorvexSingleFinalPeriod(_ sentence: String) -> String {
  guard sentence.hasSuffix(".."), !sentence.hasSuffix("...") else { return sentence }
  return String(sentence.dropLast())
}

import SwiftUI

/// A short run of facts separated by dots ("5 tasks left · 2 meetings · 2 hr
/// planned · 1 done") that wraps between facts rather than inside one, and
/// never leaves a dot at the end or the start of a line.
///
/// The facts sit on one line when they fit. Otherwise they split into two lines
/// at the latest fact boundary that lets both lines fit, so the first line holds
/// as much as it can. With too little room for that, each fact takes a line of
/// its own, without dots; only a fact wider than the whole line (at the largest
/// Dynamic Type sizes, or a single fact that is a sentence) wraps, between its
/// words. Up to four facts are shown; the font and the facts' color come from
/// the environment, and the dots read `.tertiary`. VoiceOver reads the facts as
/// one localized list rather than stopping at each dot.
///
/// Every candidate is built up front from plain text, with no `ForEach`:
/// SwiftUI builds a `ViewThatFits` candidate it has not needed before during
/// layout, which an animation frame may run off the main thread, and a
/// main-actor `ForEach` closure run there traps.
public struct LorvexFactsLine: View {
  public let facts: [String]

  public init(_ facts: [String]) {
    self.facts = Array(facts.prefix(4))
  }

  public var body: some View {
    ViewThatFits(in: .horizontal) {
      row(from: 0, to: facts.count)
      if facts.count >= 4 { lines(splitAt: 3) }
      if facts.count >= 3 { lines(splitAt: 2) }
      if facts.count >= 2 { lines(splitAt: 1) }
      factPerLine
    }
    .accessibilityElement(children: .ignore)
    .accessibilityAddTraits(.isStaticText)
    .accessibilityLabel(Text(verbatim: ListFormatter.localizedString(byJoining: facts)))
  }

  private func lines(splitAt split: Int) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      row(from: 0, to: split)
      row(from: split, to: facts.count)
    }
  }

  /// Each fact on a line of its own, wrapping between its words when it is
  /// wider than the line. The layout of last resort, so it takes whatever
  /// width it is given and grows downward.
  private var factPerLine: some View {
    VStack(alignment: .leading, spacing: 2) {
      if facts.count > 0 { Text(verbatim: facts[0]) }
      if facts.count > 1 { Text(verbatim: facts[1]) }
      if facts.count > 2 { Text(verbatim: facts[2]) }
      if facts.count > 3 { Text(verbatim: facts[3]) }
    }
    .fixedSize(horizontal: false, vertical: true)
  }

  private func row(from start: Int, to end: Int) -> some View {
    HStack(spacing: 4) {
      if start < end { fact(start, leadingDot: false) }
      if start + 1 < end { fact(start + 1, leadingDot: true) }
      if start + 2 < end { fact(start + 2, leadingDot: true) }
      if start + 3 < end { fact(start + 3, leadingDot: true) }
    }
    .lineLimit(1)
  }

  @ViewBuilder
  private func fact(_ index: Int, leadingDot: Bool) -> some View {
    if leadingDot {
      Text(verbatim: "·").foregroundStyle(.tertiary)
    }
    Text(verbatim: facts[index])
  }
}

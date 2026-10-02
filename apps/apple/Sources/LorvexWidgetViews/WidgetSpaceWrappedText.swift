import SwiftUI

/// A short label on at most two lines that starts its second line at a space.
///
/// The label takes one line when it fits, then two lines cut at the last space
/// that lets both fit, and wraps freely only when no space does (a Japanese
/// range such as "9時45分～10時30分" has none). SwiftUI's line breaking can break
/// between a digit and the Hangul after it, which splits a Korean word whose
/// particle follows a time: "오전 10:30까지" would wrap as "오전 10:30" / "까지",
/// and a word joiner in the string does not prevent that break. Cutting at a
/// space keeps every word whole: "오전" / "10:30까지". A no-break space binds
/// like a letter, so a time's "10:30 AM" stays on one line.
struct WidgetSpaceWrappedText: View {
  let text: String

  init(_ text: String) {
    self.text = text
  }

  var body: some View {
    let cuts = Self.cuts(of: text)
    ViewThatFits(in: .horizontal) {
      Text(text).lineLimit(1)
      // Written out rather than a ForEach, which ViewThatFits does not
      // reliably measure; a label of four or more words wraps freely.
      if cuts.count > 0 { lines(cuts[0]) }
      if cuts.count > 1 { lines(cuts[1]) }
      if cuts.count > 2 { lines(cuts[2]) }
      Text(text).lineLimit(2)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(text)
  }

  private func lines(_ cut: Cut) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(cut.head).lineLimit(1)
      Text(cut.tail).lineLimit(1)
    }
  }

  /// The label cut into two lines at one of its spaces.
  struct Cut: Equatable {
    var head: String
    var tail: String
  }

  /// Every way to cut `text` at one of its spaces, the last space first, so the
  /// first cut puts the most words on the first line.
  nonisolated static func cuts(of text: String) -> [Cut] {
    text.indices.filter { text[$0] == " " }.reversed().map { index in
      Cut(head: String(text[..<index]), tail: String(text[text.index(after: index)...]))
    }
  }
}

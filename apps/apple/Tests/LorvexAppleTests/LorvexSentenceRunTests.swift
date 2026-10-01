import LorvexCore
import Testing

private enum Piece: LorvexSentenceToken, Equatable {
  case text(id: String, String)
  case word(String)

  var id: String {
    switch self {
    case .text(let id, _): "text.\(id)"
    case .word(let label): "word.\(label)"
    }
  }

  var connectingText: String? {
    if case .text(_, let text) = self { text } else { nil }
  }
}

/// Each run as one string: a word as "[label]", text that closes up against
/// the word before it prefixed with "^", and each moved space as "_".
private func rendered(_ runs: [LorvexSentenceRun<Piece>]) -> [String] {
  runs.map { run in
    run.pieces.map { piece in
      switch piece {
      case .word(let token):
        if case .word(let label) = token { "[\(label)]" } else { "?" }
      case .text(_, let text, let closesUp):
        closesUp ? "^" + text : text
      case .space(_, let text):
        String(repeating: "_", count: text.count)
      }
    }.joined()
  }
}

@Test
func sentenceRunsBreakAnEnglishSentenceOnlyAtSpaces() {
  let tokens: [Piece] = [
    .word("Today"), .text(id: "for", " for "), .word("90 min"), .text(id: "due", ", due "),
    .word("Tomorrow"), .text(id: "period.time", ". "), .text(id: "in", "In "), .word("Offsite 2026"),
    .text(id: "comma", ", "), .word("high"), .text(id: "suffix", " priority"), .text(id: "period.list", ". "),
  ]
  let runs = LorvexSentenceRun.runs(tokens)
  // Punctuation stays with the word before it and tucks into its padding only
  // after a value word, never after plain text ("priority."); a connector's
  // leading space stays at the end of the run before it, and a space inside a
  // connector (", due ") is a break too.
  #expect(rendered(runs) == [
    "[Today]_", "for ", "[90 min]^, ", "due ", "[Tomorrow]^. ", "In ", "[Offsite 2026]^, ", "[high]_",
    "priority. ",
  ])
  let ids = runs.flatMap { $0.pieces.map(\.id) }
  #expect(Set(ids).count == ids.count)
  #expect(runs.map(\.id).first == "word.Today")
}

@Test
func sentenceRunsKeepAChineseSuffixAndFullWidthPunctuationWithTheirWord() {
  let tokens: [Piece] = [
    .word("今天"), .text(id: "for", "，用时 "), .word("90 分钟"), .text(id: "due", "，截止 "), .word("明天"),
    .text(id: "period.time", "。"), .text(id: "in", "位于 "), .word("Offsite 2026"), .text(id: "comma", "，"),
    .word("高"), .text(id: "suffix", "优先级"), .text(id: "period.list", "。"),
  ]
  #expect(rendered(LorvexSentenceRun.runs(tokens)) == [
    "[今天]^，用时 ", "[90 分钟]^，截止 ", "[明天]^。", "位于 ", "[Offsite 2026]^，", "[高]优先级。",
  ])
}

@Test
func sentenceRunsHandleEdgeTokens() {
  // A sentence that opens with text keeps it whole, spaces included; an empty
  // connector adds nothing; an all-space connector only ends the run before it.
  let tokens: [Piece] = [
    .text(id: "lead", " Due "), .word("Friday"), .text(id: "empty", ""), .text(id: "gap", "  "), .word("Later"),
  ]
  #expect(rendered(LorvexSentenceRun.runs(tokens)) == [" Due ", "[Friday]__", "[Later]"])
}

@Test
func sentenceRunsBreakAtEverySpaceInAConnectorButNotAtANoBreakSpace() {
  let tokens: [Piece] = [
    .word("Tomorrow"), .text(id: "hidden", ". Hidden until "), .word("Friday"),
    .text(id: "nbsp", "\u{00A0}at\u{00A0}9 "), .word("Later"),
  ]
  let runs = LorvexSentenceRun.runs(tokens)
  #expect(rendered(runs) == ["[Tomorrow]^. ", "Hidden ", "until ", "[Friday]\u{00A0}at\u{00A0}9 ", "[Later]"])
  let ids = runs.flatMap { $0.pieces.map(\.id) }
  #expect(Set(ids).count == ids.count)
}

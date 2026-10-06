import LorvexCore
import Testing

// 2026-09-22 is a Tuesday: weekday 3 in the Gregorian convention.
private func parse(_ text: String) -> LorvexCaptureParse {
  LorvexCaptureParser.parse(
    text, lists: [], todayWeekday: 3, today: "2026-09-22", languages: ["en-US"])
}

/// A single-line field keeps the line breaks of a multi-line paste. A capture
/// line is read as one line, so the task's title never holds a break and the
/// details are read across the breaks.
@Suite("Capture parser line breaks")
struct CaptureParserLineBreakTests {
  /// Every character Swift counts as a line break.
  private static let breaks = ["\n", "\r\n", "\r", "\u{2028}", "\u{2029}", "\u{85}", "\u{0B}", "\u{0C}"]

  @Test("A break between words reads as one space")
  func breakBetweenWords() {
    let line = parse("Buy milk\nand eggs")
    #expect(line.title == "Buy milk and eggs")
    #expect(!line.hasDetails)
  }

  @Test("Every kind of line break reads the same way")
  func everyKindOfBreak() {
    for lineBreak in Self.breaks {
      #expect(parse("Buy milk\(lineBreak)and eggs").title == "Buy milk and eggs")
    }
  }

  @Test("The whitespace around a break goes with it")
  func whitespaceAroundABreak() {
    #expect(parse("Buy milk  \n\n \t and eggs").title == "Buy milk and eggs")
    #expect(parse("Buy milk\r\n\r\nand eggs").title == "Buy milk and eggs")
  }

  @Test("Breaks at either end of the line are dropped")
  func breaksAtTheEnds() {
    #expect(parse("\n\nCall mom\n").title == "Call mom")
    #expect(parse("  \nCall mom \n  ").title == "Call mom")
  }

  @Test("Details are read across a break")
  func detailsAcrossBreaks() {
    let day = parse("Call mom\ntomorrow 3pm")
    #expect(day.title == "Call mom")
    #expect(day.plannedDayOffset == 1)
    #expect(day.startMinutes == 15 * 60)

    let split = parse("Call mom tomorrow\n3pm")
    #expect(split.title == "Call mom")
    #expect(split.plannedDayOffset == 1)
    #expect(split.startMinutes == 15 * 60)
  }

  @Test("A line of only details keeps its text on one line")
  func onlyDetails() {
    let line = parse("tomorrow\n3pm")
    #expect(line.title == "tomorrow 3pm")
    #expect(!line.hasDetails)
  }

  @Test("A line too long to read for details is one line too")
  func tooLongALine() {
    let words = Array(repeating: "word", count: 600)
    let pasted = words.joined(separator: "\n")
    #expect(pasted.utf16.count > LorvexCaptureParser.maxReadLength)

    let line = parse(pasted)
    #expect(line.title == words.joined(separator: " "))
    #expect(!line.hasDetails)
  }

  @Test("Text without a break is returned as typed")
  func textWithoutABreak() {
    #expect(LorvexCaptureParser.singleLine("Buy  milk ") == "Buy  milk ")
    #expect(LorvexCaptureParser.singleLine("") == "")
  }

  @Test("singleLine joins the lines of a paste")
  func joinsTheLines() {
    #expect(LorvexCaptureParser.singleLine("a\r\nb\nc") == "a b c")
    #expect(LorvexCaptureParser.singleLine("a \n\n b") == "a b")
    #expect(LorvexCaptureParser.singleLine("\na\n") == "a")
    #expect(LorvexCaptureParser.singleLine("\n \n") == "")
  }
}

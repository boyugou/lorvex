import LorvexCore
import Testing

// 2026-09-22 is a Tuesday: weekday 3 in the Gregorian convention.
private func parse(_ text: String, languages: [String] = ["en-US"]) -> LorvexCaptureParse {
  LorvexCaptureParser.parse(text, lists: [], todayWeekday: 3, today: "2026-09-22", languages: languages)
}

/// A sentence mark that stood right after a recognized phrase (a dictated line
/// ends with a period) is kept on the word before it, or goes with the phrase
/// when the phrase made a sentence of its own; it never survives alone.
@Suite("Capture parser sentence marks")
struct CaptureParserSentenceMarkTests {
  @Test("A mark after a removed phrase stays on the word before it")
  func markStaysOnPreviousWord() {
    let line = parse("Call mom tomorrow.")
    #expect(line.title == "Call mom.")
    #expect(line.plannedDayOffset == 1)
    #expect(line.phrases.map(\.text) == ["tomorrow"])

    #expect(parse("Call mom tomorrow!").title == "Call mom!")
    #expect(parse("Call mom tomorrow?").title == "Call mom?")
    #expect(parse("Call mom tomorrow...").title == "Call mom...")
    #expect(parse("Call mom tomorrow…").title == "Call mom…")
    #expect(parse("Call mom tomorrow. Then dinner").title == "Call mom. Then dinner")
  }

  @Test("Two phrases before the mark leave one clean title")
  func severalPhrases() {
    #expect(parse("Pay rent at 5pm tomorrow.").title == "Pay rent.")
    // The period after "5pm" reads as the end of "p.m.", so it goes with the time.
    let late = parse("Pay rent tomorrow at 5pm.")
    #expect(late.title == "Pay rent")
    #expect(late.plannedDayOffset == 1)
    #expect(late.startMinutes == 17 * 60)
  }

  @Test("A phrase that makes a sentence of its own takes its mark with it")
  func phraseOwnsItsSentence() {
    #expect(parse("Tomorrow. Call mom").title == "Call mom")
    #expect(parse("Tomorrow... call mom").title == "call mom")
    #expect(parse("Buy milk. Tomorrow. Call mom").title == "Buy milk. Call mom")
    #expect(parse("Buy milk, tomorrow.").title == "Buy milk")
  }

  @Test("A line that is only a phrase and a mark keeps its text")
  func onlyAPhrase() {
    let line = parse("tomorrow.")
    #expect(line.title == "tomorrow.")
    #expect(line.plannedDayOffset == nil)
  }

  @Test("Spacing the writer chose, and lines without a removed phrase, are untouched")
  func writersSpacingKept() {
    // French sets a space before "?"; a writer who typed none gets none.
    #expect(parse("Appeler Marie demain ?", languages: ["fr-FR"]).title == "Appeler Marie ?")
    #expect(parse("Appeler Marie demain?", languages: ["fr-FR"]).title == "Appeler Marie?")
    #expect(parse("Meet Mr. Smith").title == "Meet Mr. Smith")
    #expect(parse("Call mom.").title == "Call mom.")
    #expect(parse("Run 5.5 km tomorrow").title == "Run 5.5 km")
  }

  @Test("Full-width and Indic sentence marks")
  func otherScripts() {
    #expect(parse("整理报销 明天。", languages: ["zh-Hans"]).title == "整理报销。")
    #expect(parse("整理报销明天。", languages: ["zh-Hans"]).title == "整理报销。")
    #expect(parse("明天。整理报销", languages: ["zh-Hans"]).title == "整理报销")
    #expect(parse("मीटिंग कल।", languages: ["hi-IN"]).title == "मीटिंग।")
    #expect(parse("कल। मीटिंग", languages: ["hi-IN"]).title == "मीटिंग")
  }

  @Test("Indonesian and Malay lines end the same way")
  func indonesianAndMalay() {
    #expect(parse("Rapat besok.", languages: ["id-ID"]).title == "Rapat.")
    #expect(parse("Mesyuarat esok.", languages: ["ms-MY"]).title == "Mesyuarat.")
  }
}

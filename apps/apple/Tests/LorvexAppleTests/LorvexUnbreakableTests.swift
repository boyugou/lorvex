import LorvexCore
import Testing

@Suite("Unbreakable labels")
struct LorvexUnbreakableTests {
  @Test("a label's words stay on one line when the text around it wraps")
  func labelsKeepTheirWordsTogether() {
    #expect(lorvexUnbreakable("in 4d") == "in\u{00A0}4d")
    #expect(lorvexUnbreakable("deep work") == "deep\u{00A0}work")
    #expect(lorvexUnbreakable("10 hr 13 min") == "10\u{00A0}hr\u{00A0}13\u{00A0}min")
  }

  @Test("a range breaks only after its dash")
  func rangesBreakAfterTheirDash() {
    // The interval formatter's output: thin spaces around the dash and a
    // narrow no-break space before the day period.
    #expect(
      lorvexUnbreakable("9:45\u{2009}–\u{2009}10:30\u{202F}AM")
        == "9:45\u{202F}–\u{2009}10:30\u{202F}AM")
    #expect(
      lorvexUnbreakable("Sep 27\u{2009}–\u{2009}Oct 3") == "Sep\u{00A0}27\u{202F}–\u{2009}Oct\u{00A0}3")
    // The fallback range, spelled with plain spaces.
    #expect(lorvexUnbreakable("9:45 AM – 10:30 AM") == "9:45\u{00A0}AM\u{00A0}– 10:30\u{00A0}AM")
  }

  @Test("a time span beside other words never breaks inside itself")
  func timeSpansStayWhole() {
    #expect(
      lorvexWholeSpan("9:45\u{2009}–\u{2009}10:30\u{202F}AM")
        == "9:45\u{202F}\u{2060}–\u{2060}\u{202F}10:30\u{202F}AM")
    #expect(lorvexWholeSpan("09:45—10:45") == "09:45\u{2060}—\u{2060}10:45")
    #expect(lorvexWholeSpan("9:45～10:30") == "9:45\u{2060}～\u{2060}10:30")
    #expect(lorvexWholeSpan("9:45 AM – 10:30 AM") == "9:45\u{00A0}AM\u{00A0}\u{2060}–\u{2060}\u{00A0}10:30\u{00A0}AM")
  }

  @Test("a number stays with the word it counts")
  func numbersStayWithTheirWords() {
    #expect(
      lorvexNumbersTied("65 new tasks came in. 16 tasks are overdue.")
        == "65\u{00A0}new tasks came in. 16\u{00A0}tasks are overdue.")
    // The break between sentences stays: the space after the dot is not tied.
    #expect(lorvexNumbersTied("It took 3 hours. 2 more") == "It took 3\u{00A0}hours. 2\u{00A0}more")
    // A number before a mark, a number after a letter, and a word before a
    // number keep their ordinary spaces.
    #expect(lorvexNumbersTied("9:45 – 10:30 AM") == "9:45 – 10:30\u{00A0}AM")
    #expect(lorvexNumbersTied("Tasks 12 · 3") == "Tasks 12 · 3")
    #expect(lorvexNumbersTied("Due in 4d") == "Due in 4d")
    // Digits of any script count, and a string with no number is unchanged.
    #expect(lorvexNumbersTied("١٦ مهمة") == "١٦\u{00A0}مهمة")
    #expect(lorvexNumbersTied("A quiet week.") == "A quiet week.")
    #expect(lorvexNumbersTied("") == "")
  }

  @Test("a dot stays with the fact before it")
  func dotsStayWithTheFactBeforeThem() {
    #expect(lorvexDotJoined(["9:45 AM", "Due"]) == "9:45 AM\u{00A0}· Due")
    #expect(lorvexDotJoined(["Due"]) == "Due")
    #expect(lorvexDotJoined([]) == "")
  }
}

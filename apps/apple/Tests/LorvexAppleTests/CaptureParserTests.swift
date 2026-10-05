import LorvexCore
import Testing

private let lists = [
  LorvexCaptureParser.ListOption(id: "list-offsite", name: "Offsite 2026"),
  LorvexCaptureParser.ListOption(id: "list-home", name: "Home"),
]

// 2026-09-22 is a Tuesday: weekday 3 in the Gregorian convention.
private func parse(_ text: String) -> LorvexCaptureParse {
  LorvexCaptureParser.parse(text, lists: lists, todayWeekday: 3, languages: ["en"])
}

@Test
func captureParserReadsDayLengthAndList() {
  let result = parse("Call the caterer tomorrow 20 min #offsite2026")
  #expect(result.title == "Call the caterer")
  #expect(result.plannedDayOffset == 1)
  #expect(result.estimatedMinutes == 20)
  #expect(result.listID == "list-offsite")
  #expect(result.listName == "Offsite 2026")
  #expect(result.phrases.map(\.kind) == [.when, .length, .list])
  #expect(result.phrases.map(\.text) == ["tomorrow", "20 min", "#offsite2026"])
}

@Test
func captureParserKeepsTheFirstPhraseOfAKind() {
  let result = parse("Tomorrow prep for friday review")
  #expect(result.plannedDayOffset == 1)
  #expect(result.title == "prep for friday review")
  #expect(parse("Pay rent 30 min then file taxes 2h").estimatedMinutes == 30)
}

@Test
func captureParserReadsDueDayBeforePlannedDay() {
  let result = parse("Send the deck by friday")
  #expect(result.title == "Send the deck")
  #expect(result.dueDayOffset == 3)
  #expect(result.plannedDayOffset == nil)
}

@Test
func captureParserResolvesWeekdays() {
  // A weekday naming today means a week ahead; "next" adds a week.
  #expect(parse("Standup notes tuesday").plannedDayOffset == 7)
  #expect(parse("Standup notes on wed").plannedDayOffset == 1)
  #expect(parse("Standup notes next wed").plannedDayOffset == 8)
  #expect(parse("Plan the trip next week").plannedDayOffset == 7)
  #expect(parse("Plan the trip next week").title == "Plan the trip")
  #expect(parse("Book a table for tomorrow").title == "Book a table")
  #expect(parse("Book a table for tomorrow").plannedDayOffset == 1)
}

@Test
func captureParserReadsHoursAndChineseWords() {
  let hours = parse("Write the review for 1.5h")
  #expect(hours.title == "Write the review")
  #expect(hours.estimatedMinutes == 90)
  let chinese = parse("整理报销 明天 30分钟")
  #expect(chinese.title == "整理报销")
  #expect(chinese.plannedDayOffset == 1)
  #expect(chinese.estimatedMinutes == 30)
}

@Test
func captureParserReadsPriority() {
  #expect(parse("Renew passport !!").priority == .p1)
  #expect(parse("Renew passport !!").title == "Renew passport")
  #expect(parse("Renew passport urgent").priority == .p1)
  #expect(parse("Sort photos low priority").priority == .p3)
  #expect(parse("Sort photos").priority == nil)
}

@Test
func captureParserKeepsUnknownHashWordsAsTags() {
  let result = parse("Buy paint #home #weekend")
  #expect(result.title == "Buy paint")
  #expect(result.listID == "list-home")
  #expect(result.tags == ["weekend"])
}

@Test
func captureParserReadsTagsInEveryScript() {
  // Vowel signs and joiners belong to the word they are in.
  #expect(parse("काम करना #दफ़्तर").tags == ["दफ़्तर"])
  #expect(parse("خرید #می\u{200C}خواهم").tags == ["می\u{200C}خواهم"])
  #expect(parse("ซื้อของ #สวัสดี").tags == ["สวัสดี"])
  #expect(parse("Plan #tag-one, #two").tags == ["tag-one", "two"])
}

@Test
func captureParserMatchesListsIgnoringCaseAndAccents() {
  let options = [LorvexCaptureParser.ListOption(id: "list-tomorrow", name: "Mañana")]
  let result = LorvexCaptureParser.parse("Call the bank #MANANA", lists: options, todayWeekday: 3)
  #expect(result.listID == "list-tomorrow")
  #expect(result.listName == "Mañana")
  #expect(result.tags.isEmpty)
}

@Test
func captureParserMatchesListsIgnoringLetterVariants() {
  let options = [
    LorvexCaptureParser.ListOption(id: "list-lodz", name: "Łódź"),
    LorvexCaptureParser.ListOption(id: "list-street", name: "Straße"),
    LorvexCaptureParser.ListOption(id: "list-light", name: "Işık"),
  ]
  func listID(_ line: String) -> String? {
    LorvexCaptureParser.parse(line, lists: options, todayWeekday: 3).listID
  }
  #expect(listID("Book a hotel #lodz") == "list-lodz")
  #expect(listID("Pay the bill #STRASSE") == "list-street")
  #expect(listID("Buy a lamp #isik") == "list-light")
  #expect(listID("Buy a lamp #krakow") == nil)
}

@Test
func captureParserLeavesOrdinaryWordsInTheTitle() {
  // Words that only look like details inside a title stay put.
  let memo = parse("Read Monday Morning Memo draft")
  #expect(memo.title == "Read Monday Morning Memo draft")
  #expect(memo.plannedDayOffset == nil)
  #expect(parse("Prep the Monday Memo on Monday").plannedDayOffset == 6)
  #expect(parse("Prep the Monday Memo on Monday").title == "Prep the Monday Memo")
  #expect(parse("Call the bank Friday").plannedDayOffset == 3)
  let ladder = parse("Buy a 3 m ladder")
  #expect(ladder.title == "Buy a 3 m ladder")
  #expect(ladder.estimatedMinutes == nil)
  #expect(parse("Stretch 20m").estimatedMinutes == 20)
  let noDetails = parse("Water the plants")
  #expect(noDetails.title == "Water the plants")
  #expect(!noDetails.hasDetails)
}

@Test
func captureParserKeepsADetailsOnlyLineAsTheTitle() {
  let result = parse("tomorrow 20 min")
  #expect(result.title == "tomorrow 20 min")
  #expect(!result.hasDetails)
  #expect(result.plannedDayOffset == nil)
}

@Test
func captureParserReadsALineUpToTheReadLimit() {
  let limit = LorvexCaptureParser.maxReadLength
  let filler = String(repeating: "a", count: limit - " tomorrow".utf16.count)
  let line = filler + " tomorrow"
  #expect(line.utf16.count == limit)
  let result = parse(line)
  #expect(result.title == filler)
  #expect(result.plannedDayOffset == 1)
}

@Test
func captureParserTakesALineBeyondTheReadLimitAsATitleAlone() {
  // A pasted page: no title can be this long, and every pattern would scan all of it.
  let line = String(repeating: "call the caterer tomorrow ", count: 100) + "#work 20 min"
  #expect(line.utf16.count > LorvexCaptureParser.maxReadLength)
  let result = parse(line)
  #expect(result.title == line)
  #expect(!result.hasDetails)
  #expect(result.tags.isEmpty)
  #expect(result.phrases.isEmpty)
  #expect(parse("  " + line + "\n").title == line)
}

@Test
func captureListMatchesAnAliasAndReportsTheShownName() {
  let inbox = LorvexCaptureParser.ListOption(id: "inbox", name: "收件箱", aliases: ["Inbox"])
  let byShownName = LorvexCaptureParser.parse("Call the caterer #收件箱", lists: [inbox], todayWeekday: 3)
  #expect(byShownName.listID == "inbox")
  #expect(byShownName.listName == "收件箱")
  #expect(byShownName.title == "Call the caterer")
  let byStoredName = LorvexCaptureParser.parse("Call the caterer #inbox", lists: [inbox], todayWeekday: 3)
  #expect(byStoredName.listID == "inbox")
  #expect(byStoredName.listName == "收件箱")
}

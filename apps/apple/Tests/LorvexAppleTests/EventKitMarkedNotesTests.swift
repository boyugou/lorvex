import Testing

@testable import LorvexApple

// A mirrored event keeps its Lorvex id on the last line of `EKEvent.notes`.
// Reading the notes back must drop only that exact line and keep every other
// line break once, whether the account stored LF, CR LF, or a lone CR (Swift
// reads CR LF as one `Character` that `== "\n"` does not match).

private let markedNotesEventID = "event-1"
private let markedNotesMarker = "\(lorvexCalendarEventPrefix)\(markedNotesEventID)"

private func readUserNotes(_ notes: String?) -> String? {
  LiveEventKitAccess.userNotes(fromMarkedNotes: notes, lorvexID: markedNotesEventID)
}

@Test
func markedNotesRoundTripThroughTheMarker() {
  let marked = LiveEventKitAccess.notesWithMarker(
    userNotes: "Bring the slides", lorvexID: markedNotesEventID)

  #expect(marked == "Bring the slides\n\(markedNotesMarker)")
  #expect(readUserNotes(marked) == "Bring the slides")
}

@Test
func markedNotesKeepEveryLineAndBlankLineOfMultiLineNotes() {
  let marked = LiveEventKitAccess.notesWithMarker(
    userNotes: "Agenda\n\n1. Intro\n2. Q&A", lorvexID: markedNotesEventID)

  #expect(readUserNotes(marked) == "Agenda\n\n1. Intro\n2. Q&A")
}

@Test
func markedNotesWithOnlyTheMarkerOrNothingYieldNoNotes() {
  #expect(readUserNotes(markedNotesMarker) == nil)
  #expect(readUserNotes("") == nil)
  #expect(readUserNotes(nil) == nil)
  #expect(
    LiveEventKitAccess.notesWithMarker(userNotes: nil, lorvexID: markedNotesEventID)
      == markedNotesMarker)
}

@Test
func markedNotesReadWindowsLineBreaksAsOneBreakEach() {
  #expect(readUserNotes("line one\r\nline two\r\n\(markedNotesMarker)") == "line one\nline two")
  #expect(
    readUserNotes("line one\r\n\r\nline three\r\n\(markedNotesMarker)")
      == "line one\n\nline three")
}

@Test
func markedNotesReadALoneCarriageReturnAsOneBreak() {
  #expect(readUserNotes("line one\rline two\r\(markedNotesMarker)") == "line one\nline two")
}

@Test
func markedNotesDropTheMarkerWhereverItSits() {
  #expect(readUserNotes("first\r\n\(markedNotesMarker)\r\nsecond") == "first\nsecond")
  #expect(readUserNotes("\(markedNotesMarker)\nonly this") == "only this")
}

@Test
func markedNotesKeepLinesThatMerelyMentionThePrefix() {
  let otherEvent = "\(lorvexCalendarEventPrefix)event-2"

  #expect(
    readUserNotes("see \(markedNotesMarker) for details\n\(markedNotesMarker)")
      == "see \(markedNotesMarker) for details")
  #expect(readUserNotes("\(otherEvent)\n\(markedNotesMarker)") == otherEvent)
}

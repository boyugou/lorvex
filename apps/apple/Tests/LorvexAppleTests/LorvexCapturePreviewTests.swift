import LorvexCore
import Testing

/// The words a capture line previews, shared by the Mac's quick-add row and
/// the iPhone's capture sheet.
@Suite("Capture preview")
struct LorvexCapturePreviewTests {
  /// A Monday, so weekday phrases within the coming week are predictable.
  private let today = "2026-09-28"

  private func preview(_ line: String) -> LorvexCapturePreview {
    LorvexCapturePreview(
      parse: LorvexCaptureParser.parse(line, lists: [], todayWeekday: 2, today: today), logicalDay: today)
  }

  @Test func aPlainTitleShowsNothing() {
    #expect(preview("Water the plants") == .empty)
  }

  @Test func wordsFollowTheOrderATaskIsPlannedIn() {
    let preview = preview("Call the caterer tomorrow 25 min by friday !! #food")
    #expect(preview.title == "Call the caterer")
    #expect(preview.addsLine == "Adds “Call the caterer”")
    #expect(preview.words.map(\.id) == ["when", "length", "due", "priority", "tag.food"])
    #expect(
      preview.words.map(\.label)
        == ["Tomorrow", LorvexDurationFormat.minutes(25), "Due Friday", "High priority", "#food"])
    #expect(preview.words.map(\.role) == [.plan, .plan, .due, .urgent, .plain])
  }

  /// A repeating task is planned and due on its first occurrence; the day word
  /// already names it, so "Due" does not repeat it.
  @Test func aRepeatingTaskNamesItsFirstOccurrenceOnce() {
    let words = preview("Standup every mon and thu 9:30am").words
    #expect(words.map(\.id) == ["when", "time", "repeats"])
    #expect(words.first?.label == "Today")
  }

  /// Without a time the task has no planned day, so the due day is the only
  /// word that says when the first occurrence is.
  @Test func aRepeatingTaskWithoutATimeShowsItsFirstDueDay() {
    let words = preview("Water the plants every thursday").words
    #expect(words.map(\.id) == ["repeats", "due"])
    #expect(words.last?.label == "Due Thursday")
  }
}

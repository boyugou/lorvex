import Foundation
import Testing

private func mobileSource(_ name: String) throws -> String {
  let url = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appending(path: "Sources/LorvexMobile/\(name)")
  return try String(contentsOf: url, encoding: .utf8)
}

/// How many times `needle` occurs in `text`.
private func occurrences(of needle: String, in text: String) -> Int {
  text.components(separatedBy: needle).count - 1
}

@Test(
  "A small icon control on the phone grows its tap target past its glyph and gives the layout the glyph's size back",
  arguments: [
    ("MobileTodayScheduleTimelineSection.swift", "Self.completionTapOutset", 1),
    ("MobileTaskComposerRows.swift", "composerAddTapOutset", 2),
    ("MobileHabitReminderList.swift", "Self.menuTapOutset", 1),
    ("MobileHabitMilestoneGoalField.swift", "Self.clearTapOutset", 1),
  ])
func smallPhoneControlsCarryATapOutset(file: String, outset: String, controls: Int) throws {
  let text = try mobileSource(file)

  // Padding on the label and a content shape widen the target; the negative
  // padding outside the control returns the layout to the glyph's own size.
  #expect(occurrences(of: ".padding(\(outset))\n", in: text) == controls)
  #expect(occurrences(of: ".padding(-\(outset))\n", in: text) == controls)
  #expect(occurrences(of: ".contentShape(Rectangle())", in: text) >= controls)
}

@Test("The schedule's earlier toggle is a thumb-high row")
func scheduleEarlierToggleIsThumbHigh() throws {
  let text = try mobileSource("MobileTodayScheduleTimelineSection.swift")

  let toggle = try #require(text.range(of: "private func pastToggle"))
  let height = try #require(text.range(of: ".frame(minHeight: 44, alignment: .leading)"))
  #expect(toggle.lowerBound < height.lowerBound)
}

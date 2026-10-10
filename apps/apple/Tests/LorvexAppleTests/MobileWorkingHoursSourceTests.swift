import Foundation
import Testing

private func source(_ path: String) throws -> String {
  let url = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appending(path: path)
  return try String(contentsOf: url, encoding: .utf8)
}

@Test("Each Day Hours picker offers only times that keep the end after the start")
func dayHoursPickersCannotPickAnInvertedWindow() throws {
  let text = try source("Sources/LorvexMobile/MobileStoreSettingsWorkingHoursSection.swift")

  // A start at or after the end, or an end at or before the start, would reach the
  // store's refusal, which the person sees as a "Something went wrong" alert.
  #expect(text.contains("selection: $start, in: ...end.addingTimeInterval(-Self.minimumWindow)"))
  #expect(text.contains("selection: $end, in: start.addingTimeInterval(Self.minimumWindow)..."))
  #expect(text.contains("private static let minimumWindow: TimeInterval = 60"))
}

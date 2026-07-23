import Foundation
import Testing

@Test
func nonMainAppCancelSurfacesLabelOccurrenceOnlySemantics() throws {
  let root = packageRoot()
  let systemIntent = try String(
    contentsOf: root.appending(path: "Sources/LorvexSystemIntents/CancelLorvexTaskIntent.swift"),
    encoding: .utf8)
  let watchButton = try String(
    contentsOf: root.appending(path: "Sources/LorvexWatch/LorvexWatchCancelButton.swift"),
    encoding: .utf8)

  #expect(systemIntent.contains("Cancel Lorvex Task Occurrence"))
  #expect(systemIntent.contains("Repeating tasks continue."))
  #expect(watchButton.contains(#""Cancel occurrence""#))
  #expect(watchButton.contains("Cancel this occurrence of %@?"))
  #expect(watchButton.contains("only this occurrence is cancelled"))
}

private func packageRoot() -> URL {
  URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
}

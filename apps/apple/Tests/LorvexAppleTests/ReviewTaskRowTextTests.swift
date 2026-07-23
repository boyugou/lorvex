import LorvexCore
import Testing

@testable import LorvexApple

@Test
func reviewTaskRowSubtitleLocalizesKnownStatus() {
  let task = ReviewTaskSummary(id: "done", title: "Ship", status: "completed", deferCount: 0)

  #expect(ReviewTaskRowText.subtitle(for: task) == "Completed")
}

@Test
func reviewTaskRowSubtitleFormatsDeferredCountWithLocalizedStatus() {
  let task = ReviewTaskSummary(id: "deferred", title: "Polish", status: "open", deferCount: 3)

  #expect(ReviewTaskRowText.subtitle(for: task) == "Open · deferred 3x")
}

@Test
func reviewTaskRowSubtitlePreservesUnknownStatus() {
  let task = ReviewTaskSummary(id: "custom", title: "Custom", status: "blocked", deferCount: 0)

  #expect(ReviewTaskRowText.subtitle(for: task) == "blocked")
}

import LorvexCore
import Testing

@testable import LorvexMobile

@Test
func mobileReviewTaskRowSubtitleLocalizesKnownStatus() {
  let task = ReviewTaskSummary(id: "done", title: "Ship", status: "completed", deferCount: 0)

  #expect(MobileReviewTaskRowText.subtitle(for: task) == "Completed")
}

@Test
func mobileReviewTaskRowSubtitleFormatsDeferredCountWithLocalizedStatus() {
  let task = ReviewTaskSummary(id: "deferred", title: "Polish", status: "open", deferCount: 3)

  #expect(MobileReviewTaskRowText.subtitle(for: task) == "Open · deferred 3 times")
}

@Test
func mobileReviewTaskRowSubtitleUsesSingularDeferredCount() {
  let task = ReviewTaskSummary(id: "deferred-once", title: "Polish", status: "open", deferCount: 1)

  #expect(MobileReviewTaskRowText.subtitle(for: task) == "Open · deferred 1 time")
}

@Test
func mobileReviewTaskRowSubtitlePreservesUnknownStatus() {
  let task = ReviewTaskSummary(id: "custom", title: "Custom", status: "blocked", deferCount: 0)

  #expect(MobileReviewTaskRowText.subtitle(for: task) == "blocked")
}

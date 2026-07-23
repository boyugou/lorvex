import Foundation
import LorvexCore
@testable import LorvexMobile
import Testing

/// The mobile recurrence surface renders through the `MobileL10n`-backed wrapper
/// rather than the raw English core helper, and pluralizes the interval unit via
/// CLDR categories instead of an English `+"s"`.
@Suite("Mobile recurrence localization")
struct MobileRecurrenceLocalizationTests {
  @Test("interval phrase is fully formatted and count-aware")
  func intervalPhraseFormatsCount() {
    let one = TaskRecurrenceRule.Frequency.daily.mobileLocalizedEveryInterval(1)
    let many = TaskRecurrenceRule.Frequency.daily.mobileLocalizedEveryInterval(3)

    // Fully substituted — no leftover format placeholder leaks to the UI.
    #expect(!one.contains("%"))
    #expect(!many.contains("%"))
    #expect(one.contains("1"))
    #expect(many.contains("3"))
    // Singular and plural counts resolve to distinct phrases.
    #expect(one != many)
  }

  @Test("display summary composes localized parts without raw placeholders")
  func displaySummaryComposesLocalizedParts() {
    let rule = TaskRecurrenceRule(freq: .weekly, interval: 2, byDay: ["MO", "WE"], count: 10)
    let summary = rule.mobileLocalizedDisplaySummary()

    #expect(!summary.isEmpty)
    #expect(!summary.contains("%"))
    #expect(summary.contains("2"))
    #expect(summary.contains("10"))
    #expect(!summary.contains("MO"))
    #expect(!summary.contains("WE"))
    #expect(summary.contains(Calendar.current.shortWeekdaySymbols[1]))
    #expect(summary.contains(Calendar.current.shortWeekdaySymbols[3]))
    #expect(summary.contains("·"))
  }

  @Test("anchor labels and explanations are localized presentation strings")
  func anchorPresentationIsLocalized() {
    let anchors = TaskRecurrenceRule.Anchor.allCases
    let names = Set(anchors.map(\.mobileLocalizedDisplayName))
    let hints = Set(anchors.map(\.mobileLocalizedHint))

    #expect(names.count == anchors.count)
    #expect(hints.count == anchors.count)
    #expect(names.allSatisfy { !$0.isEmpty && !$0.contains("%") })
    #expect(hints.allSatisfy { !$0.isEmpty && !$0.contains("%") })
  }

  @Test("frequency display names differ per frequency")
  func frequencyNamesAreDistinct() {
    let names = Set(
      TaskRecurrenceRule.Frequency.allCases.map { $0.mobileLocalizedDisplayName })
    #expect(names.count == TaskRecurrenceRule.Frequency.allCases.count)
  }
}

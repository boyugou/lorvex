import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

/// The words a recurrence rule is shown in come from LorvexCore, so the Mac
/// and the phone say a rule alike. The interval is one phrase in the
/// frequency's unit, so each language words and pluralizes it whole; exactly
/// one period is said without a number ("Every week", "Every 2 weeks").
@Suite("Recurrence wording")
struct TaskRecurrenceLocalizationTests {
  @Test("One period is said without a number; longer intervals agree with their count")
  func phraseAgreesWithInterval() {
    #expect(TaskRecurrenceRule.Frequency.weekly.localizedEveryInterval(1) == "Every week")
    #expect(TaskRecurrenceRule.Frequency.weekly.localizedEveryInterval(2) == "Every 2 weeks")
    #expect(TaskRecurrenceRule.Frequency.daily.localizedEveryInterval(1) == "Every day")
    #expect(TaskRecurrenceRule.Frequency.daily.localizedEveryInterval(3) == "Every 3 days")
    #expect(TaskRecurrenceRule.Frequency.monthly.localizedEveryInterval(12) == "Every 12 months")
    #expect(TaskRecurrenceRule.Frequency.yearly.localizedEveryInterval(1) == "Every year")
  }

  @Test("The Repeat menu, the field label, and the summary say the interval alike")
  func surfacesShareTheCadence() {
    let weekly = TaskRecurrenceRule(freq: .weekly)
    #expect(weekly.localizedCadence == "Every week")
    #expect(weekly.localizedDisplaySummary() == "Every week")
    #expect(TaskDetailRecurrencePreset.weekly.title == weekly.localizedCadence)
    #expect(TaskDetailRecurrencePreset.biweekly.title == "Every 2 weeks")
    // A stored interval below one reads as one period.
    #expect(TaskRecurrenceRule(freq: .monthly, interval: 0).localizedCadence == "Every month")
  }

  @Test("The summary adds the end, the anchor, and skipped dates to the cadence")
  func summaryExtendsTheCadence() {
    let rule = TaskRecurrenceRule(freq: .weekly, interval: 2, byDay: ["MO", "WE"], count: 10)
    let cadence = rule.localizedCadence
    #expect(cadence == "Every 2 weeks · " + LorvexRecurrenceWeekdays.summary(["MO", "WE"]))
    #expect(!cadence.contains("10"))
    #expect(rule.localizedDisplaySummary(exceptions: ["2026-10-12"]) == cadence + " · 10 times · 1 skipped")

    let afterCompletion = TaskRecurrenceRule(freq: .daily, interval: 3, anchor: .completion)
    #expect(afterCompletion.localizedDisplaySummary() == "Every 3 days · after completion")
  }

  @Test("A weekly rule without chosen weekdays names its anchor's weekday; other rules read as before")
  func plainWeeklyRuleNamesTheAnchorWeekday() throws {
    // October 5, 2026 is a Monday.
    let monday = try #require(LorvexDateFormatters.ymdUTC.date(from: "2026-10-05"))
    let mon = LorvexRecurrenceWeekdays.summary(["MO"])
    #expect(TaskRecurrenceRule(freq: .weekly).localizedCadence(anchorDay: monday) == "Every week · \(mon)")
    #expect(TaskRecurrenceRule(freq: .weekly, interval: 2).localizedCadence(anchorDay: monday) == "Every 2 weeks · \(mon)")
    #expect(TaskRecurrenceRule(freq: .weekly).localizedCadence(anchorDay: nil) == "Every week")
    #expect(
      TaskRecurrenceRule(freq: .weekly, count: 4).localizedDisplaySummary(anchorDay: monday)
        == "Every week · \(mon) · 4 times")
    // Chosen weekdays win over the anchor; a rule counted from completion or
    // by another unit names no day.
    #expect(
      TaskRecurrenceRule(freq: .weekly, byDay: ["WE"]).localizedCadence(anchorDay: monday)
        == "Every week · " + LorvexRecurrenceWeekdays.summary(["WE"]))
    #expect(TaskRecurrenceRule(freq: .weekly, anchor: .completion).localizedCadence(anchorDay: monday) == "Every week")
    #expect(TaskRecurrenceRule(freq: .monthly).localizedCadence(anchorDay: monday) == "Every month")
  }

  @Test("Anchor names and hints and frequency names are distinct, finished strings")
  func namesAreDistinct() {
    let anchors = TaskRecurrenceRule.Anchor.allCases
    let names = Set(anchors.map(\.localizedDisplayName))
    let hints = Set(anchors.map(\.localizedHint))
    #expect(names.count == anchors.count)
    #expect(hints.count == anchors.count)
    #expect(names.union(hints).allSatisfy { !$0.isEmpty && !$0.contains("%") })

    let frequencies = TaskRecurrenceRule.Frequency.allCases
    #expect(Set(frequencies.map(\.localizedDisplayName)).count == frequencies.count)
  }
}

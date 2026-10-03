import LorvexCore
import Testing

@Suite("Task recurrence editor draft")
struct TaskRecurrenceEditorDraftTests {
  @Test("opening a full-fidelity rule is a semantic no-op")
  func fullRuleOpensClean() throws {
    let rule = TaskRecurrenceRule(
      freq: .monthly,
      interval: 2,
      byDay: ["1MO", "-1FR"],
      byMonth: [3, 9],
      byMonthDay: [1, 15],
      bySetPos: [-1, 1],
      wkst: "MO",
      until: "2027-12-31"
    )
    let draft = TaskRecurrenceEditorDraft(rule: rule)

    #expect(!draft.hasChanges)
    #expect(try draft.saveIntent(liveRule: rule) == .none)
  }

  @Test("an interval edit preserves every hidden modifier")
  func intervalEditPreservesHiddenFields() throws {
    let rule = TaskRecurrenceRule(
      freq: .yearly,
      interval: 1,
      byDay: ["1MO"],
      byMonth: [1, 7],
      byMonthDay: [1, 15],
      bySetPos: [1],
      wkst: "SU",
      count: 20
    )
    var draft = TaskRecurrenceEditorDraft(rule: rule)
    draft.intervalText = "3"

    let updated = try #require(try draft.saveIntent(liveRule: rule).ruleToSet)
    #expect(updated.freq == .yearly)
    #expect(updated.interval == 3)
    #expect(updated.byDay == rule.byDay)
    #expect(updated.byMonth == rule.byMonth)
    #expect(updated.byMonthDay == rule.byMonthDay)
    #expect(updated.bySetPos == rule.bySetPos)
    #expect(updated.wkst == rule.wkst)
    #expect(updated.count == rule.count)
  }

  @Test("a frequency edit clears old positional constraints but preserves termination")
  func frequencyEditClearsPositionalFields() throws {
    let rule = TaskRecurrenceRule(
      freq: .yearly,
      interval: 1,
      byDay: ["1MO"],
      byMonth: [3],
      byMonthDay: [10],
      bySetPos: [1],
      wkst: "MO",
      until: "2028-03-10"
    )
    var draft = TaskRecurrenceEditorDraft(rule: rule)
    draft.frequency = .daily

    let updated = try #require(try draft.saveIntent(liveRule: rule).ruleToSet)
    #expect(updated.freq == .daily)
    #expect(updated.byDay == nil)
    #expect(updated.byMonth == nil)
    #expect(updated.byMonthDay == nil)
    #expect(updated.bySetPos == nil)
    #expect(updated.wkst == nil)
    #expect(updated.until == rule.until)
  }

  @Test("completion anchor round-trips and clears incompatible scheduling fields")
  func completionAnchorRoundTrip() throws {
    let completion = TaskRecurrenceRule(
      freq: .weekly, interval: 2, count: 12, anchor: .completion)
    var unchanged = TaskRecurrenceEditorDraft(rule: completion)
    #expect(unchanged.anchor == .completion)
    #expect(!unchanged.hasChanges)
    unchanged.intervalText = "3"
    let intervalEdit = try #require(
      try unchanged.saveIntent(liveRule: completion).ruleToSet)
    #expect(intervalEdit.anchor == .completion)
    #expect(intervalEdit.count == 12)

    let scheduled = TaskRecurrenceRule(
      freq: .weekly, interval: 1, byDay: ["MO", "FR"], byMonth: [3], wkst: "SU")
    var anchored = TaskRecurrenceEditorDraft(rule: scheduled)
    anchored.anchor = .completion
    let anchoredRule = try #require(
      try anchored.saveIntent(liveRule: scheduled).ruleToSet)
    #expect(anchoredRule.anchor == .completion)
    #expect(anchoredRule.byDay == nil)
    #expect(anchoredRule.byMonth == nil)
    #expect(anchoredRule.byMonthDay == nil)
    #expect(anchoredRule.bySetPos == nil)
    #expect(anchoredRule.wkst == nil)
  }

  @Test("weekday edits use canonical Monday-first order")
  func weekdayEditsAreCanonical() throws {
    let rule = TaskRecurrenceRule(freq: .weekly, interval: 1, byDay: ["MO"])
    var draft = TaskRecurrenceEditorDraft(rule: rule)
    draft.weeklyDays = [.friday, .monday, .wednesday]

    let updated = try #require(try draft.saveIntent(liveRule: rule).ruleToSet)
    #expect(updated.byDay == ["MO", "WE", "FR"])

    let savedDraft = TaskRecurrenceEditorDraft(rule: updated)
    #expect(!savedDraft.hasChanges)
    #expect(try savedDraft.saveIntent(liveRule: updated) == .none)
  }

  @Test("disable and invalid interval produce explicit safe intents")
  func removalAndValidation() throws {
    let rule = TaskRecurrenceRule(freq: .daily, interval: 1)
    var existing = TaskRecurrenceEditorDraft(rule: rule)
    existing.isEnabled = false
    #expect(try existing.saveIntent(liveRule: rule) == .remove)

    var absent = TaskRecurrenceEditorDraft()
    absent.isEnabled = false
    #expect(try absent.saveIntent(liveRule: nil) == .none)

    for invalid in ["0", "10001", "x"] {
      var draft = TaskRecurrenceEditorDraft(rule: rule)
      draft.intervalText = invalid
      #expect(draft.validatedInterval == nil)
      #expect(throws: TaskRecurrenceEditorError.self) {
        _ = try draft.saveIntent(liveRule: rule)
      }
    }
  }

  @Test("removal does not overwrite a concurrently changed recurrence")
  func removalRejectsConcurrentChange() throws {
    let original = TaskRecurrenceRule(freq: .daily, interval: 1)
    var draft = TaskRecurrenceEditorDraft(rule: original)
    draft.isEnabled = false

    #expect(
      throws: TaskRecurrenceEditorError.concurrentChange
    ) {
      _ = try draft.saveIntent(
        liveRule: TaskRecurrenceRule(freq: .daily, interval: 2))
    }
    // A peer already removing the rule reaches the same desired state and is a
    // no-op, while a rule created after this editor opened must not be deleted.
    #expect(try draft.saveIntent(liveRule: nil) == .none)

    var initiallyAbsent = TaskRecurrenceEditorDraft()
    initiallyAbsent.isEnabled = false
    #expect(
      throws: TaskRecurrenceEditorError.concurrentChange
    ) {
      _ = try initiallyAbsent.saveIntent(
        liveRule: TaskRecurrenceRule(freq: .weekly, interval: 1))
    }
  }

  @Test("a concurrent hidden-field edit merges with the local visible edit")
  func liveHiddenFieldMerge() throws {
    let original = TaskRecurrenceRule(
      freq: .monthly, interval: 1, byMonthDay: [1], until: "2027-01-01")
    var draft = TaskRecurrenceEditorDraft(rule: original)
    draft.intervalText = "2"

    let live = TaskRecurrenceRule(
      freq: .monthly, interval: 1, byMonthDay: [1], until: "2028-01-01")
    let merged = try #require(try draft.saveIntent(liveRule: live).ruleToSet)
    #expect(merged.interval == 2)
    #expect(merged.until == "2028-01-01")
  }

  @Test("conflicting edits to the same axis are rejected")
  func conflictingAxisEditIsRejected() {
    let original = TaskRecurrenceRule(freq: .weekly, interval: 1, byDay: ["MO"])
    var draft = TaskRecurrenceEditorDraft(rule: original)
    draft.intervalText = "2"
    let live = TaskRecurrenceRule(freq: .weekly, interval: 3, byDay: ["MO"])

    #expect(throws: TaskRecurrenceEditorError.self) {
      _ = try draft.saveIntent(liveRule: live)
    }
  }

  @Test("edits made during a save rebase onto the persisted rule")
  func inFlightEditsRebaseOntoPersistedRule() throws {
    var submitted = TaskRecurrenceEditorDraft()
    submitted.isEnabled = true
    submitted.frequency = .daily
    submitted.intervalText = "2"

    var current = submitted
    current.intervalText = "3"
    let persisted = TaskRecurrenceRule(freq: .daily, interval: 2)
    let rebased = current.rebasedPreservingEdits(
      since: submitted, onto: persisted)

    #expect(rebased.originalRule == persisted)
    #expect(rebased.intervalText == "3")
    #expect(rebased.hasChanges)
    #expect(
      try rebased.saveIntent(liveRule: persisted)
        == .set(TaskRecurrenceRule(freq: .daily, interval: 3)))
  }

  @Test("a weekly picker shows the anchor's weekday while no weekday is chosen")
  func shownWeeklyDaysFallBackToTheAnchorWeekday() throws {
    // October 5, 2026 is a Monday; October 11 a Sunday.
    let monday = try #require(LorvexDateFormatters.ymdUTC.date(from: "2026-10-05"))
    let sunday = try #require(LorvexDateFormatters.ymdUTC.date(from: "2026-10-11"))
    #expect(TaskRecurrenceWeekday(storedDay: monday) == .monday)
    #expect(TaskRecurrenceWeekday(storedDay: sunday) == .sunday)

    var draft = TaskRecurrenceEditorDraft(rule: TaskRecurrenceRule(freq: .weekly))
    #expect(draft.shownWeeklyDays(anchorDay: monday) == [.monday])
    #expect(draft.shownWeeklyDays(anchorDay: nil).isEmpty)
    #expect(!draft.hasChanges, "showing the anchor's day changes nothing")

    draft.weeklyDays = [.monday, .wednesday]
    #expect(draft.shownWeeklyDays(anchorDay: monday) == [.monday, .wednesday])
    draft.weeklyDays = [.friday]
    #expect(draft.shownWeeklyDays(anchorDay: monday) == [.friday])
  }

  @Test("the anchor day is the series anchor while repeating, else the deadline, else today")
  func recurrenceAnchorDayResolution() throws {
    let today = try #require(LorvexDateFormatters.ymdUTC.date(from: "2026-10-03"))
    let due = try #require(LorvexDateFormatters.ymdUTC.date(from: "2026-10-08"))
    let seriesAnchor = try #require(LorvexDateFormatters.ymdUTC.date(from: "2026-10-05"))
    var task = LorvexTask(
      id: "t", title: "Water the plants", notes: "", priority: .p2, status: .open,
      dueDate: nil, estimatedMinutes: nil, tags: [])
    #expect(task.recurrenceAnchorDay(logicalDay: "2026-10-03") == today)
    task.dueDate = due
    #expect(task.recurrenceAnchorDay(logicalDay: "2026-10-03") == due)
    task.recurrence = TaskRecurrenceRule(freq: .weekly)
    task.canonicalOccurrenceDate = seriesAnchor
    #expect(task.recurrenceAnchorDay(logicalDay: "2026-10-03") == seriesAnchor)
    task.recurrence = nil
    #expect(
      task.recurrenceAnchorDay(logicalDay: "2026-10-03") == due,
      "an anchor left on a task that no longer repeats is ignored")
  }
}

private extension TaskRecurrenceEditorSaveIntent {
  var ruleToSet: TaskRecurrenceRule? {
    guard case .set(let rule) = self else { return nil }
    return rule
  }
}

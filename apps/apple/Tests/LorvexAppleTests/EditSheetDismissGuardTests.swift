import Foundation
import LorvexCore
import Testing

@testable import LorvexMobile

// An iPhone or iPad editor sheet refuses a swipe-down while its draft holds an
// edit the swipe would lose. Each predicate is clean when the sheet opens, dirty
// after a change, and clean again once the change is undone or adds only
// whitespace.

private func storedDay(_ key: String) throws -> Date {
  try #require(PlannedDayBridge.storageDate(forLogicalDay: key))
}

private func fullyPopulatedTask() throws -> LorvexTask {
  LorvexTask(
    id: "task-guard",
    title: "Draft the launch notes ",
    notes: "Cover sync and widgets.\n",
    priority: .p2,
    status: .open,
    dueDate: try storedDay("2026-05-29"),
    plannedDate: try storedDay("2026-05-26"),
    plannedTime: 540..<600,
    availableFrom: try storedDay("2026-05-24"),
    estimatedMinutes: 45,
    tags: ["launch", "writing"],
    dependsOn: ["task-outline"])
}

private func habit(
  frequencyType: String, weekdays: [Int]? = nil, perPeriodTarget: Int? = nil,
  dayOfMonth: Int? = nil, targetCount: Int = 1, milestoneTarget: Int? = nil
) -> LorvexHabit {
  LorvexHabit(
    id: "habit-guard", name: "Evening walk", icon: "figure.walk", color: "#34C759",
    cue: "After dinner", frequencyType: frequencyType, targetCount: targetCount,
    completionsToday: 0, totalCompletions: 0, completionRate30d: 0, archived: false,
    weekdays: weekdays, perPeriodTarget: perPeriodTarget, dayOfMonth: dayOfMonth,
    milestoneTarget: milestoneTarget)
}

private func event(allDay: Bool) -> CalendarTimelineEvent {
  CalendarTimelineEvent(
    id: "event-guard", title: "Design review", source: "lorvex", editable: true,
    startDate: "2026-05-23", startTime: allDay ? nil : "10:00", endDate: nil,
    endTime: allDay ? nil : "11:00", allDay: allDay, location: "Studio", notes: "Bring the deck",
    color: nil, eventType: "event", timezone: nil, isRecurring: false)
}

@Suite("Edit sheet dismiss guard")
struct EditSheetDismissGuardTests {
  // MARK: Task edit and field sheets

  @Test("a task draft opens clean with every field filled")
  func taskDraftOpensClean() throws {
    let draft = MobileTaskEditDraft(task: try fullyPopulatedTask())
    #expect(!draft.hasUnsavedChanges())
    #expect(!draft.hasUnsavedChanges(pendingTag: ""))
  }

  @Test("a task draft is dirty after a change and clean once it is undone")
  func taskDraftChangeAndRevert() throws {
    let task = try fullyPopulatedTask()
    var draft = MobileTaskEditDraft(task: task)

    draft.title = "Draft the release notes"
    #expect(draft.hasUnsavedChanges())
    draft.title = task.title
    #expect(!draft.hasUnsavedChanges())

    draft.priority = .p1
    #expect(draft.hasUnsavedChanges())
    draft.priority = task.priority
    #expect(!draft.hasUnsavedChanges())

    draft.hasDueDate = false
    #expect(draft.hasUnsavedChanges())
    draft.hasDueDate = true
    #expect(!draft.hasUnsavedChanges())

    draft.plannedTime = 600..<660
    #expect(draft.hasUnsavedChanges())
    draft.plannedTime = task.plannedTime
    #expect(!draft.hasUnsavedChanges())

    draft.tags = ["launch"]
    #expect(draft.hasUnsavedChanges())
    draft.tags = task.tags
    #expect(!draft.hasUnsavedChanges())

    draft.estimatedMinutesText = "60"
    #expect(draft.hasUnsavedChanges())
    draft.estimatedMinutesText = "45"
    #expect(!draft.hasUnsavedChanges())
  }

  @Test("whitespace alone is no task edit, and a typed pending tag is one")
  func taskDraftWhitespaceAndPendingTag() throws {
    var draft = MobileTaskEditDraft(task: try fullyPopulatedTask())

    draft.title = "  Draft the launch notes\n"
    draft.notes = "Cover sync and widgets.  \n\n"
    #expect(!draft.hasUnsavedChanges())
    #expect(!draft.hasUnsavedChanges(pendingTag: "   "))

    #expect(draft.hasUnsavedChanges(pendingTag: "urgent"))

    draft.notes = "Cover sync, widgets, and the watch."
    #expect(draft.hasUnsavedChanges())
  }

  // MARK: Recurrence editor

  @Test("the recurrence draft is dirty while it differs from the task's rule")
  func recurrenceDraftChangeAndRevert() {
    var none = TaskRecurrenceEditorDraft(rule: nil)
    #expect(!none.hasChanges)
    none.isEnabled = true
    #expect(none.hasChanges)
    none.isEnabled = false
    #expect(!none.hasChanges)

    var weekly = TaskRecurrenceEditorDraft(
      rule: TaskRecurrenceRule(freq: .weekly, interval: 1, byDay: ["MO"]))
    #expect(!weekly.hasChanges)
    weekly.intervalText = "2"
    #expect(weekly.hasChanges)
    weekly.intervalText = " 1 "
    #expect(!weekly.hasChanges)
  }

  // MARK: Habit sheets

  @Test(
    "an edited habit's draft opens clean for every cadence",
    arguments: [
      habit(frequencyType: "daily", targetCount: 2, milestoneTarget: 30),
      habit(frequencyType: "weekly", weekdays: [0, 2, 4]),
      habit(frequencyType: "times_per_week", perPeriodTarget: 4),
      habit(frequencyType: "monthly", dayOfMonth: 15),
    ])
  func habitDraftOpensClean(habit: LorvexHabit) {
    #expect(!MobileHabitDraft(habit: habit).hasUnsavedChanges)
  }

  @Test("an edited habit's draft is dirty after a change and clean once it is undone")
  func habitEditDraftChangeAndRevert() {
    var draft = MobileHabitDraft(habit: habit(frequencyType: "daily"))

    draft.name = "Morning walk"
    #expect(draft.hasUnsavedChanges)
    draft.name = "  Evening walk "
    #expect(!draft.hasUnsavedChanges)

    draft.cadenceMode = .monthly
    #expect(draft.hasUnsavedChanges)
    draft.cadenceMode = .daily
    #expect(!draft.hasUnsavedChanges)

    draft.weekdays = [1]
    #expect(!draft.hasUnsavedChanges, "a daily habit saves no weekdays")

    draft.milestoneTargetText = "21"
    #expect(draft.hasUnsavedChanges)
    draft.milestoneTargetText = ""
    #expect(!draft.hasUnsavedChanges)
  }

  @Test("a new habit's draft is dirty once any field leaves its default")
  func habitCreateDraftChangeAndRevert() {
    var draft = MobileHabitDraft()
    #expect(!draft.hasUnsavedChanges)

    draft.name = "   "
    #expect(!draft.hasUnsavedChanges)
    draft.name = "Read"
    #expect(draft.hasUnsavedChanges)
    draft.name = ""
    #expect(!draft.hasUnsavedChanges)

    draft.color = "#FF9500"
    #expect(draft.hasUnsavedChanges)
    draft.color = nil
    #expect(!draft.hasUnsavedChanges)

    draft.perDayTarget = 3
    #expect(draft.hasUnsavedChanges)
    draft.perDayTarget = 1
    #expect(!draft.hasUnsavedChanges)
  }

  // MARK: List sheets

  @Test("an edited list's draft is dirty after a change and clean once it is undone")
  func listEditDraftChangeAndRevert() {
    let list = LorvexList(
      id: "list-guard", name: "Apple Platform", color: "#007AFF", icon: "apple.logo",
      description: "Ship the native apps", openCount: 3, totalCount: 5,
      updatedAt: "2026-05-23T09:00:00Z")
    var draft = MobileListDraft(list: list)
    #expect(!draft.hasUnsavedChanges)

    draft.description = "Ship the native apps  \n"
    #expect(!draft.hasUnsavedChanges)
    draft.description = ""
    #expect(draft.hasUnsavedChanges)
    draft.description = "Ship the native apps"
    #expect(!draft.hasUnsavedChanges)

    draft.icon = "hammer"
    #expect(draft.hasUnsavedChanges)
    draft.icon = "apple.logo"
    #expect(!draft.hasUnsavedChanges)
  }

  @Test("a new list's draft is dirty once any field leaves empty")
  func listCreateDraftChangeAndRevert() {
    var draft = MobileListDraft()
    #expect(!draft.hasUnsavedChanges)

    draft.name = " \n"
    #expect(!draft.hasUnsavedChanges)
    draft.name = "Errands"
    #expect(draft.hasUnsavedChanges)
    draft.name = ""
    #expect(!draft.hasUnsavedChanges)

    draft.icon = "cart"
    #expect(draft.hasUnsavedChanges)
  }

  // MARK: Calendar event sheets

  @Test("an edited event's draft opens clean", arguments: [false, true])
  func calendarEditDraftOpensClean(allDay: Bool) {
    let draft = MobileCalendarDraft(event: event(allDay: allDay), fallbackDate: Date())
    #expect(!draft.hasUnsavedChanges())
  }

  @Test("an edited event's draft is dirty after a change and clean once it is undone")
  func calendarEditDraftChangeAndRevert() {
    var draft = MobileCalendarDraft(event: event(allDay: false), fallbackDate: Date())
    let opened = draft.timing

    draft.title = "Design review, round two"
    #expect(draft.hasUnsavedChanges())
    draft.title = " Design review "
    #expect(!draft.hasUnsavedChanges())

    draft.notes = "Bring the deck\n"
    #expect(!draft.hasUnsavedChanges())

    draft.timing.moveStart(to: opened.start.addingTimeInterval(1_800))
    #expect(draft.hasUnsavedChanges())
    draft.timing.moveStart(to: opened.start)
    #expect(!draft.hasUnsavedChanges())

    draft.timing.allDay = true
    #expect(draft.hasUnsavedChanges())
    draft.timing.allDay = false
    #expect(!draft.hasUnsavedChanges())
  }

  @Test("a new event's draft compares with the draft its sheet opened with")
  func calendarCreateDraftChangeAndRevert() throws {
    var components = DateComponents(year: 2026, month: 5, day: 23, hour: 14)
    components.calendar = Calendar(identifier: .gregorian)
    let start = try #require(components.date)
    let opening = MobileCalendarDraft.timedDefault(start: start)
    var draft = opening
    #expect(!draft.hasUnsavedChanges(opening: opening))

    draft.title = "   "
    #expect(!draft.hasUnsavedChanges(opening: opening))
    draft.title = "Coffee with Sam"
    #expect(draft.hasUnsavedChanges(opening: opening))
    draft.title = ""
    #expect(!draft.hasUnsavedChanges(opening: opening))

    draft.timing.moveStart(to: start.addingTimeInterval(3_600))
    #expect(draft.hasUnsavedChanges(opening: opening))
    #expect(!draft.hasUnsavedChanges(), "with no opening draft only text counts")
    draft.timing.moveStart(to: start)
    #expect(!draft.hasUnsavedChanges(opening: opening))
  }

  // MARK: Memory edit sheet

  @Test("a memory edit is dirty while its key or content differs")
  func memoryEditChangeAndRevert() {
    let entry = MemoryEntry(
      key: "user_profile", content: "Prefers mornings for deep work.",
      updatedAt: "2026-05-23T09:00:00Z")
    #expect(!entry.isEdited(key: entry.key, content: entry.content))
    #expect(!entry.isEdited(key: " user_profile ", content: "Prefers mornings for deep work.\n"))
    #expect(entry.isEdited(key: "profile", content: entry.content))
    #expect(entry.isEdited(key: entry.key, content: "Prefers evenings."))
  }

  // MARK: Habit reminder time sheet

  @Test("a reminder time is dirty once the picker names another minute")
  func reminderTimeChangeAndRevert() {
    let opened = MobileHabitReminderTime.date(from: "07:30")
    #expect(!MobileHabitReminderTime.isChanged(opened, from: "07:30"))
    #expect(
      MobileHabitReminderTime.isChanged(MobileHabitReminderTime.date(from: "08:00"), from: "07:30"))
    #expect(
      !MobileHabitReminderTime.isChanged(MobileHabitReminderTime.date(from: "07:30"), from: "07:30"))
    let fallback = MobileHabitReminderTime.date(from: "not a time")
    #expect(!MobileHabitReminderTime.isChanged(fallback, from: "not a time"))
  }
}

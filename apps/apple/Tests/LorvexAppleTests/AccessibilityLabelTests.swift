import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

// MARK: - taskAccessibilityLabel

private func task(
  _ title: String, priority: LorvexTask.Priority = .p2, status: LorvexTask.Status = .open,
  estimatedMinutes: Int? = nil, tags: [String] = [], recurrence: TaskRecurrenceRule? = nil
) -> LorvexTask {
  LorvexTask(
    id: "a11y-\(title)", title: title, notes: "", priority: priority, status: status, dueDate: nil,
    estimatedMinutes: estimatedMinutes, tags: tags, recurrence: recurrence)
}

/// The title leads, then a priority other than normal, named as the interface
/// names it rather than by its storage code.
@Test
func taskAccessibilityLabelLeadsWithTheTitle() {
  #expect(taskAccessibilityLabel(task("Write release notes", priority: .p1)) == "Write release notes: High priority")
  #expect(!taskAccessibilityLabel(task("Write release notes", priority: .p1)).contains("P1"))
}

/// Normal priority and the open status are what a task is unless it says
/// otherwise, so a plain open task is read by its title alone.
@Test
func taskAccessibilityLabelLeavesTheDefaultsUnsaid() {
  #expect(taskAccessibilityLabel(task("Water the plants")) == "Water the plants")
}

@Test
func taskAccessibilityLabelIncludesEstimateWhenPresent() {
  #expect(
    taskAccessibilityLabel(task("Design sprint", estimatedMinutes: 45))
      == "Design sprint: \(LorvexDurationFormat.minutes(45, style: .spoken))")
}

/// The estimate is spoken as a duration in the display language, so a
/// one-minute estimate takes the singular ("1 minute", not "1 minutes").
@Test
func taskAccessibilityLabelSpeaksTheEstimateAsADuration() {
  #expect(
    taskAccessibilityLabel(task("Quick check", estimatedMinutes: 1))
      .hasSuffix(LorvexDurationFormat.minutes(1, style: .spoken)))
  #expect(
    LorvexDurationFormat.minutes(1, style: .spoken, locale: Locale(identifier: "en_US"))
      == "1 minute")
}

@Test
func taskAccessibilityLabelIncludesTags() {
  let label = taskAccessibilityLabel(task("Review PR", priority: .p3, tags: ["eng", "review"]))
  #expect(label == "Review PR: Low priority, #eng, #review")
}

/// A status other than open is named the way the interface names it.
@Test
func taskAccessibilityLabelNamesAStatusOtherThanOpen() {
  #expect(
    taskAccessibilityLabel(task("Ship widget", priority: .p1, status: .inProgress))
      == "Ship widget: High priority, In Progress")
  #expect(taskAccessibilityLabel(task("Follow up", status: .someday)) == "Follow up: Someday")
  #expect(
    taskAccessibilityLabel(task("Sync notes", priority: .p3, status: .completed))
      == "Sync notes: Low priority, Completed")
}

/// A row's time on the day and what it shows beyond the task's own fields
/// are spoken after the priority and status, in the order the row gives them.
@Test
func taskAccessibilityLabelSpeaksTheRowsTimeAndDetails() {
  let label = taskAccessibilityLabel(
    task("Review the Q3 planning doc", priority: .p1, estimatedMinutes: 45, tags: ["work"]),
    timeLabel: "9:45 – 10:30 AM", details: ["Until 3:00 PM", "Blocked"])
  #expect(
    label
      == "Review the Q3 planning doc: High priority, 9:45 – 10:30 AM, Until 3:00 PM, Blocked, 45 minutes, #work"
  )
}

/// A repeating task says so, as its row shows a repeat glyph.
@Test
func taskAccessibilityLabelSpeaksARepeatingTask() {
  let repeating = task("Submit the weekly timesheet", priority: .p3, recurrence: TaskRecurrenceRule(freq: .weekly))
  #expect(taskAccessibilityLabel(repeating) == "Submit the weekly timesheet: Low priority, repeats")
}

// MARK: - memoryEntryAccessibilityLabel

@Test
func memoryEntryAccessibilityLabelCombinesTitleAndContent() {
  let entry = MemoryEntry(key: "project_goal", content: "Ship v1 by Q3", updatedAt: "2026-05-01")
  let label = memoryEntryAccessibilityLabel(entry)
  #expect(label == "Project goal: Ship v1 by Q3", "the row is read by its title, not its handle")
}

// MARK: - calendarEventAccessibilityLabel

// An event reads as its title, its clock times, and its place when it has
// one, never as the internal name of the calendar source it came from.
@Test
func calendarEventAccessibilityLabelReadsTitleTimeAndPlace() {
  var standup = CalendarTimelineEvent(
    id: "standup", title: "Standup", source: "eventkit", editable: false,
    startDate: "2026-10-02", startTime: "09:00", endDate: nil, endTime: "09:30",
    allDay: false, location: "Zoom", color: nil, eventType: "event", timezone: nil,
    isRecurring: false)
  let time = lorvexClockRangeLabel(start: "09:00", end: "09:30")
  #expect(calendarEventAccessibilityLabel(standup) == "Standup, \(time), Zoom")

  standup.location = nil
  #expect(calendarEventAccessibilityLabel(standup) == "Standup, \(time)")
}

// An event that runs into a later day reads as one span across its days.
@Test
func calendarEventAccessibilityLabelReadsAnOvernightEventAsASpan() throws {
  let flight = CalendarTimelineEvent(
    id: "flight", title: "Night flight", source: "lorvex", editable: true,
    startDate: "2026-10-02", startTime: "22:30", endDate: "2026-10-03", endTime: "01:30",
    allDay: false, location: nil, color: nil, eventType: "event", timezone: nil,
    isRecurring: false)
  let span = try #require(flight.timedSpanLabel)
  #expect(calendarEventAccessibilityLabel(flight) == "Night flight, \(span)")
}

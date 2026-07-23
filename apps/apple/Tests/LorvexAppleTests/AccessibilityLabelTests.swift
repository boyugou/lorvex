import LorvexCore
import Testing

@testable import LorvexApple

// MARK: - taskAccessibilityLabel

@Test
func taskAccessibilityLabelIncludesPriorityAndTitle() {
  let task = LorvexTask(
    id: "t1",
    title: "Write release notes",
    notes: "",
    priority: .p1,
    status: .open,
    dueDate: nil,
    estimatedMinutes: nil,
    tags: []
  )
  let label = taskAccessibilityLabel(task)
  #expect(label.contains("P1 task"))
  #expect(label.contains("Write release notes"))
  #expect(label.contains("open"))
}

/// A localized vocabulary replaces the English connectives + status word, so
/// VoiceOver speaks the user's language. Verifies the composer honors every
/// vocabulary slot (the wiring that makes the 10-language a11y labels work).
@Test
func taskAccessibilityLabelUsesProvidedVocabulary() {
  let task = LorvexTask(
    id: "t1",
    title: "Reunión",
    notes: "",
    priority: .p2,
    status: .someday,
    dueDate: nil,
    estimatedMinutes: 30,
    tags: []
  )
  let vocab = TaskAccessibilityVocabulary(
    focusedTask: "Tarea en foco",
    priorityTaskFormat: "Tarea %@",
    minutesFormat: "%lld minutos",
    dueFormat: "vence %@",
    overdueFormat: "vencida %@",
    statusName: { _ in "algún día" }
  )
  let label = taskAccessibilityLabel(task, vocabulary: vocab)
  #expect(label.contains("Tarea P2"))
  #expect(label.contains("algún día"))
  #expect(label.contains("30 minutos"))
  #expect(!label.contains("someday"))
  #expect(!label.contains("minutes"))
}

@Test
func taskAccessibilityLabelIncludesEstimateWhenPresent() {
  let task = LorvexTask(
    id: "t2",
    title: "Design sprint",
    notes: "",
    priority: .p2,
    status: .open,
    dueDate: nil,
    estimatedMinutes: 45,
    tags: []
  )
  let label = taskAccessibilityLabel(task)
  #expect(label.contains("45 minutes"))
}

@Test
func taskAccessibilityLabelUsesPluralAwareMinutesProviderWhenPresent() {
  let task = LorvexTask(
    id: "t2-singular",
    title: "Quick check",
    notes: "",
    priority: .p2,
    status: .open,
    dueDate: nil,
    estimatedMinutes: 1,
    tags: []
  )
  let vocabulary = TaskAccessibilityVocabulary(
    minutesFormat: "wrong fallback",
    minutesText: { $0 == 1 ? "1 minute" : "\($0) minutes" }
  )

  let label = taskAccessibilityLabel(task, vocabulary: vocabulary)

  #expect(label.contains("1 minute"))
  #expect(!label.contains("wrong fallback"))
}

@Test
func taskAccessibilityLabelKeepsMutableMinutesFormatAsTheFallbackSourceOfTruth() {
  let task = LorvexTask(
    id: "t2-mutable-format",
    title: "Quick check",
    notes: "",
    priority: .p2,
    status: .open,
    dueDate: nil,
    estimatedMinutes: 5,
    tags: []
  )
  var vocabulary = TaskAccessibilityVocabulary(minutesFormat: "%lld old units")
  vocabulary.minutesFormat = "%lld updated units"

  let label = taskAccessibilityLabel(task, vocabulary: vocabulary)

  #expect(label.contains("5 updated units"))
  #expect(!label.contains("old units"))
}

@Test
func taskAccessibilityLabelIncludesTags() {
  let task = LorvexTask(
    id: "t3",
    title: "Review PR",
    notes: "",
    priority: .p3,
    status: .open,
    dueDate: nil,
    estimatedMinutes: nil,
    tags: ["eng", "review"]
  )
  let label = taskAccessibilityLabel(task)
  #expect(label.contains("#eng"))
  #expect(label.contains("#review"))
}

@Test
func taskAccessibilityLabelMarkedFocusedWhenFocused() {
  let task = LorvexTask(
    id: "t4",
    title: "Ship widget",
    notes: "",
    priority: .p1,
    status: .open,
    dueDate: nil,
    estimatedMinutes: nil,
    tags: []
  )
  let label = taskAccessibilityLabel(task, isFocused: true)
  #expect(label.contains("Focused task"))
  #expect(!label.contains("P1 task"))
}

@Test
func taskAccessibilityLabelReflectsSomedayStatus() {
  let task = LorvexTask(
    id: "t5",
    title: "Follow up",
    notes: "",
    priority: .p2,
    status: .someday,
    dueDate: nil,
    estimatedMinutes: nil,
    tags: []
  )
  let label = taskAccessibilityLabel(task)
  #expect(label.contains("someday"))
}

@Test
func taskAccessibilityLabelReflectsCompletedStatus() {
  let task = LorvexTask(
    id: "t6",
    title: "Sync notes",
    notes: "",
    priority: .p3,
    status: .completed,
    dueDate: nil,
    estimatedMinutes: nil,
    tags: []
  )
  let label = taskAccessibilityLabel(task)
  #expect(label.contains("completed"))
}

// MARK: - focusTaskCountAccessibilityValue

@Test
func focusTaskCountAccessibilityValueSingular() {
  #expect(focusTaskCountAccessibilityValue(1) == "1 task in focus")
}

@Test
func focusTaskCountAccessibilityValuePlural() {
  #expect(focusTaskCountAccessibilityValue(0) == "0 tasks in focus")
  #expect(focusTaskCountAccessibilityValue(5) == "5 tasks in focus")
}

// MARK: - menuBarActionAccessibilityLabel

@Test
func menuBarActionAccessibilityLabelPassesThroughTitle() {
  #expect(menuBarActionAccessibilityLabel("Complete Task") == "Complete Task")
  #expect(menuBarActionAccessibilityLabel("Defer to Tomorrow") == "Defer to Tomorrow")
}

// MARK: - habitAccessibilityLabel

@Test
func habitAccessibilityLabelIncludesNameAndProgress() {
  let habit = LorvexHabit(
    id: "h1", name: "Morning Run", icon: nil, color: nil, cue: nil,
    frequencyType: "daily", targetCount: 3, completionsToday: 1,
    totalCompletions: 30, completionRate30d: 0.9, archived: false
  )
  let label = habitAccessibilityLabel(habit)
  #expect(label.contains("Morning Run"))
  #expect(label.contains("1 of 3 completions today"))
  #expect(label.contains("daily"))
}

@Test
func habitAccessibilityLabelIncludesCueWhenPresent() {
  let habit = LorvexHabit(
    id: "h2", name: "Meditate", icon: nil, color: nil, cue: "After coffee",
    frequencyType: "daily", targetCount: 1, completionsToday: 0,
    totalCompletions: 5, completionRate30d: 0.5, archived: false
  )
  let label = habitAccessibilityLabel(habit)
  #expect(label.contains("After coffee"))
}

@Test
func habitActionAccessibilityLabelReturnsCorrectString() {
  #expect(habitActionAccessibilityLabel(isComplete: false) == "Complete today")
  #expect(habitActionAccessibilityLabel(isComplete: true) == "Reset today")
}

// MARK: - memoryEntryAccessibilityLabel

@Test
func memoryEntryAccessibilityLabelCombinesKeyAndContent() {
  let entry = MemoryEntry(key: "project_goal", content: "Ship v1 by Q3", updatedAt: "2026-05-01")
  let label = memoryEntryAccessibilityLabel(entry)
  #expect(label.contains("project_goal"))
  #expect(label.contains("Ship v1 by Q3"))
}

// MARK: - calendarEventAccessibilityLabel

@Test
func calendarEventAccessibilityLabelAllDay() {
  let label = calendarEventAccessibilityLabel(
    title: "Company Holiday", allDay: true, startTime: nil, endTime: nil,
    location: nil, source: "Google Calendar"
  )
  #expect(label.contains("Company Holiday"))
  #expect(label.contains("All day"))
  #expect(label.contains("Google Calendar"))
}

@Test
func calendarEventAccessibilityLabelWithTime() {
  let label = calendarEventAccessibilityLabel(
    title: "Standup", allDay: false, startTime: "9:00 AM", endTime: "9:30 AM",
    location: "Zoom", source: "Google Calendar"
  )
  #expect(label.contains("Standup"))
  #expect(label.contains("9:00 AM"))
  #expect(label.contains("9:30 AM"))
  #expect(label.contains("Zoom"))
}

// MARK: - listAccessibilityLabel

@Test
func listAccessibilityLabelIncludesNameAndCounts() {
  let list = LorvexList(
    id: "l1", name: "Work", color: nil, icon: nil, description: nil,
    openCount: 4, totalCount: 10, updatedAt: "2026-05-01"
  )
  let label = listAccessibilityLabel(list)
  #expect(label.contains("Work"))
  #expect(label.contains("4 open tasks"))
  #expect(label.contains("10 total"))
}

@Test
func listAccessibilityLabelSingularOpenTask() {
  let list = LorvexList(
    id: "l2", name: "Personal", color: nil, icon: nil, description: nil,
    openCount: 1, totalCount: 3, updatedAt: "2026-05-01"
  )
  let label = listAccessibilityLabel(list)
  #expect(label.contains("1 open task,"))
}

// MARK: - reviewMetricAccessibilityLabel

@Test
func reviewMetricAccessibilityLabelFormatsCorrectly() {
  #expect(reviewMetricAccessibilityLabel(title: "Completed", value: 5) == "Completed: 5")
  #expect(reviewMetricAccessibilityLabel(title: "Overdue", value: 0) == "Overdue: 0")
}

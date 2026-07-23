import Foundation
import LorvexCore
import Testing

// MARK: - Recurrence anchor round-trip

@Test
func exportRecurrenceRulePreservesCompletionAnchor() throws {
  // A completion-anchored rule must survive the DTO + JSON round-trip; before
  // the anchor field was carried it silently reverted to the schedule anchor.
  let completion = TaskRecurrenceRule(freq: .weekly, interval: 3, anchor: .completion)
  let dto = ExportRecurrenceRule(from: completion)
  #expect(dto.anchor == "completion")
  #expect(dto.rule?.anchor == .completion)

  let data = try JSONEncoder().encode(dto)
  let decoded = try JSONDecoder().decode(ExportRecurrenceRule.self, from: data)
  #expect(decoded.rule?.anchor == .completion)

  // The default schedule anchor stays compact (omitted) and reconstructs.
  let schedule = ExportRecurrenceRule(from: TaskRecurrenceRule(freq: .weekly, byDay: ["MO"]))
  #expect(schedule.anchor == nil)
  #expect(schedule.rule?.anchor == .schedule)
}

// MARK: - JSON round-trip

@Test
func exportJSONContainsTaskFields() throws {
  let payload = LorvexDataExportPayload(tasks: [makeExportTask()])
  let json = try LorvexDataExporter.render(payload: payload, format: .json)
  #expect(json.contains("\"id\""))
  #expect(json.contains("\"task-1\""))
  #expect(json.contains("\"Buy milk\""))
  #expect(json.contains("\"P2\""))
  #expect(json.contains("\"open\""))
  #expect(json.contains("\"rawInput\""))
  #expect(json.contains("\"plannedDate\""))
  #expect(json.contains("\"availableFrom\""))
  #expect(json.contains("\"archivedAt\""))
  #expect(json.contains("\"checklist\""))
  #expect(json.contains("\"44444444-4444-4444-8444-444444444444\""))
  #expect(json.contains("\"completedAt\""))
  #expect(json.contains("\"reminders\""))
  #expect(json.contains("\"55555555-5555-4555-8555-555555555555\""))
  #expect(json.contains("\"originalTz\""))
}

@Test
func exportJSONContainsListFields() throws {
  let payload = LorvexDataExportPayload(lists: [makeExportList()])
  let json = try LorvexDataExporter.render(payload: payload, format: .json)
  #expect(json.contains("\"list-1\""))
  #expect(json.contains("\"Inbox\""))
  #expect(json.contains("\"archivedAt\""))
  #expect(json.contains("\"position\""))
}

@Test
func exportJSONContainsTagFields() throws {
  let payload = LorvexDataExportPayload(tags: [makeExportTag()])
  let json = try LorvexDataExporter.render(payload: payload, format: .json)
  #expect(json.contains("\"tags\""))
  #expect(json.contains("\"tag-1\""))
  #expect(json.contains("\"Focus\""))
  #expect(json.contains("\"color\""))
  #expect(json.contains("\"createdAt\""))
}

@Test
func exportJSONContainsHabitFields() throws {
  let payload = LorvexDataExportPayload(habits: [makeExportHabit()])
  let json = try LorvexDataExporter.render(payload: payload, format: .json)
  #expect(json.contains("\"habit-1\""))
  #expect(json.contains("\"Morning run\""))
  #expect(json.contains("\"icon\""))
  #expect(json.contains("\"color\""))
  #expect(json.contains("\"archived\""))
  #expect(json.contains("\"position\""))
  #expect(json.contains("\"completions\""))
  #expect(json.contains("\"2026-06-01\""))
  #expect(json.contains("\"reminderPolicies\""))
  #expect(json.contains("\"07:30\""))
}

@Test
func exportJSONContainsCalendarEventFields() throws {
  let payload = LorvexDataExportPayload(calendarEvents: [makeExportEvent()])
  let json = try LorvexDataExporter.render(payload: payload, format: .json)
  #expect(json.contains("\"event-1\""))
  #expect(json.contains("\"Team sync\""))
  #expect(json.contains("\"notes\""))
  #expect(json.contains("\"recurrence\""))
  #expect(json.contains("\"recurrenceGeneration\""))
  #expect(!json.contains("recurrenceTopologyVersion"))
  #expect(!json.contains("contentVersion"))
  #expect(json.contains("team@example.com"))
}

@Test
func exportJSONCalendarRecurrenceIsStructuredObject() throws {
  // A calendar event's recurrence exports as a structured camelCase object with
  // canonical token values — not the escaped uppercase-keyed JSON string it is
  // stored as.
  let event = ExportCalendarEvent(
    id: "event-2", title: "Weekly sync", startDate: "2026-06-03",
    startTime: "09:00", endDate: "2026-06-03", endTime: "10:00", allDay: false,
    recurrence: ExportCalendarRecurrenceRule(freq: "WEEKLY", interval: 2, byDay: ["MO", "WE"]))
  let payload = LorvexDataExportPayload(calendarEvents: [event])
  let json = try LorvexDataExporter.render(payload: payload, format: .json)

  // camelCase keys and canonical values are present; the uppercase-keyed opaque
  // string form is absent (`FREQ` appears nowhere).
  #expect(json.contains("\"freq\""))
  #expect(json.contains("\"WEEKLY\""))
  #expect(json.contains("\"byDay\""))
  #expect(json.contains("\"interval\""))
  #expect(!json.contains("FREQ"))

  // Decodes back into the structured type unchanged.
  let decoded = try JSONDecoder().decode(LorvexDataExportPayload.self, from: Data(json.utf8))
  let decodedEvent = decoded.calendarEvents?.first { $0.id == "event-2" }
  #expect(
    decodedEvent?.recurrence
      == ExportCalendarRecurrenceRule(freq: "WEEKLY", interval: 2, byDay: ["MO", "WE"]))
}

@Test
func exportJSONContainsDailyReviewFields() throws {
  let payload = LorvexDataExportPayload(dailyReviews: [makeExportReview()])
  let json = try LorvexDataExporter.render(payload: payload, format: .json)
  #expect(json.contains("\"2024-01-01\""))
  #expect(json.contains("\"Productive day\""))
  #expect(json.contains("\"timezone\""))
  #expect(json.contains("\"linkedTaskIDs\""))
  #expect(json.contains("\"task-1\""))
}

@Test
func exportJSONContainsFocusFields() throws {
  let payload = LorvexDataExportPayload(
    currentFocus: [
      ExportCurrentFocus(
        date: "2026-06-02",
        briefing: "Protect morning",
        timezone: "America/Los_Angeles",
        taskIDs: ["task-1"],
        createdAt: "2026-06-02T08:00:00Z",
        updatedAt: "2026-06-02T09:00:00Z")
    ],
    focusSchedules: [
      ExportFocusSchedule(
        date: "2026-06-02",
        rationale: "Energy first",
        timezone: "America/Los_Angeles",
        blocks: [
          ExportFocusScheduleBlock(
            position: 0, blockType: "task", startMinutes: 540, endMinutes: 600,
            taskID: "task-1")
        ],
        createdAt: "2026-06-02T08:00:00Z",
        updatedAt: "2026-06-02T09:00:00Z")
    ])
  let json = try LorvexDataExporter.render(payload: payload, format: .json)
  #expect(json.contains("\"currentFocus\""))
  #expect(json.contains("\"focusSchedules\""))
  #expect(json.contains("\"Protect morning\""))
  #expect(json.contains("\"startMinutes\""))
  #expect(json.contains("\"task-1\""))
}

@Test
func exportJSONContainsTaskCalendarEventLinkFields() throws {
  let payload = LorvexDataExportPayload(taskCalendarEventLinks: [makeExportTaskCalendarEventLink()])
  let json = try LorvexDataExporter.render(payload: payload, format: .json)
  #expect(json.contains("\"taskCalendarEventLinks\""))
  #expect(json.contains("\"task-1\""))
  #expect(json.contains("\"event-1\""))
  #expect(!json.contains("\"version\""))
  #expect(json.contains("\"createdAt\""))
  #expect(json.contains("\"updatedAt\""))
}

@Test
func exportJSONContainsMemoryFields() throws {
  let payload = LorvexDataExportPayload(memory: [makeExportMemory()])
  let json = try LorvexDataExporter.render(payload: payload, format: .json)
  #expect(json.contains("\"memory-1\""))
  #expect(json.contains("\"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb\""))
  #expect(json.contains("\"Preserve this\""))
  #expect(json.contains("\"updatedAt\""))
}

@Test
func exportJSONOmitsAbsentEntities() throws {
  let payload = LorvexDataExportPayload(tasks: [makeExportTask()])
  let json = try LorvexDataExporter.render(payload: payload, format: .json)
  #expect(!json.contains("\"lists\""))
  #expect(!json.contains("\"habits\""))
}

// MARK: - No silent partial/empty output

/// render is `throws`, so a serialization failure surfaces instead of being
/// swallowed into the `{}` sentinel; a valid payload round-trips to real JSON.
@Test
func exportJSONNeverSilentlyEmptyForValidPayload() throws {
  let payload = LorvexDataExportPayload(tasks: [makeExportTask()])
  let json = try LorvexDataExporter.render(payload: payload, format: .json)
  #expect(json != "{}")
  #expect(json.contains("\"tasks\""))
}

// MARK: - CSV format

@Test
func exportCSVContainsTaskSectionHeader() throws {
  let payload = LorvexDataExportPayload(tasks: [makeExportTask()])
  let csv = try LorvexDataExporter.render(payload: payload, format: .csv)
  #expect(csv.contains("## tasks"))
  #expect(csv.contains("id,title,notes,priority,status"))
  #expect(csv.contains("task-1"))
}

@Test
func exportCSVOmitsAbsentEntities() throws {
  let payload = LorvexDataExportPayload(lists: [makeExportList()])
  let csv = try LorvexDataExporter.render(payload: payload, format: .csv)
  #expect(csv.contains("## lists"))
  #expect(!csv.contains("## tasks"))
  #expect(!csv.contains("## habits"))
}

// MARK: - RFC 4180 CSV escaping

@Test
func csvEscapePassesThroughPlainField() {
  #expect(LorvexDataExporter.csvEscape("hello") == "hello")
}

@Test
func csvEscapeQuotesFieldWithComma() {
  #expect(LorvexDataExporter.csvEscape("a,b") == "\"a,b\"")
}

@Test
func csvEscapeDoublesInternalQuotes() {
  #expect(LorvexDataExporter.csvEscape("say \"hi\"") == "\"say \"\"hi\"\"\"")
}

@Test
func csvEscapeQuotesFieldWithNewline() {
  #expect(LorvexDataExporter.csvEscape("line1\nline2") == "\"line1\nline2\"")
}

@Test
func exportCSVEscapesTaskTitleWithComma() throws {
  let task = makeExportTask(title: "Buy milk, eggs")
  let payload = LorvexDataExportPayload(tasks: [task])
  let csv = try LorvexDataExporter.render(payload: payload, format: .csv)
  #expect(csv.contains("\"Buy milk, eggs\""))
}

@Test
func exportCSVContainsCalendarEventFullHeader() throws {
  let payload = LorvexDataExportPayload(calendarEvents: [makeExportEvent()])
  let csv = try LorvexDataExporter.render(payload: payload, format: .csv)
  #expect(csv.contains("id,title,startDate,startTime,endDate,endTime,allDay,location"))
  #expect(csv.contains("notes,url,color,eventType,personName,attendees,timezone"))
  #expect(csv.contains("recurrence,seriesId,recurrenceInstanceDate,occurrenceState"))
  #expect(csv.contains("recurrenceGeneration"))
  #expect(!csv.contains("recurrenceTopologyVersion"))
  #expect(!csv.contains("contentVersion"))
}

@Test
func exportCSVContainsTaskCalendarEventLinkSection() throws {
  let payload = LorvexDataExportPayload(taskCalendarEventLinks: [makeExportTaskCalendarEventLink()])
  let csv = try LorvexDataExporter.render(payload: payload, format: .csv)
  #expect(csv.contains("## task_calendar_event_links"))
  #expect(csv.contains("taskID,calendarEventID,createdAt,updatedAt"))
  #expect(csv.contains("task-1,event-1"))
}

@Test
func exportCSVContainsTagSection() throws {
  let payload = LorvexDataExportPayload(tags: [makeExportTag()])
  let csv = try LorvexDataExporter.render(payload: payload, format: .csv)
  #expect(csv.contains("## tags"))
  #expect(csv.contains("id,displayName,color,createdAt,updatedAt"))
  #expect(csv.contains("tag-1,Focus"))
}

@Test
func currentCalendarEventJSONRejectsMissingRequiredWireFields() throws {
  let data = Data(
    """
    {"id":"legacy-event","title":"Legacy","startDate":"2026-06-01","allDay":true}
    """.utf8)
  #expect(throws: DecodingError.self) {
    try JSONDecoder().decode(ExportCalendarEvent.self, from: data)
  }
}

@Test
func currentHabitJSONRejectsMissingRequiredWireFields() throws {
  let data = Data(
    """
    {"id":"legacy-habit","name":"Legacy","cue":"","frequencyType":"daily","targetCount":1}
    """.utf8)
  #expect(throws: DecodingError.self) {
    try JSONDecoder().decode(ExportHabit.self, from: data)
  }
}

@Test
func taskJSONAllowsOmittedOptionalMetadata() throws {
  let data = Data(
    """
    {"id":"legacy-task","title":"Legacy","priority":"P2","status":"open"}
    """.utf8)
  let task = try JSONDecoder().decode(ExportTask.self, from: data)
  #expect(task.id == "legacy-task")
  #expect(task.notes == nil)
  #expect(task.tags == nil)
  #expect(task.plannedDate == nil)
  #expect(task.availableFrom == nil)
  #expect(task.archivedAt == nil)
  #expect(task.deferCount == nil)
  #expect(task.reminders == nil)
}

@Test
func currentDailyReviewJSONRejectsMissingRequiredLinkArrays() throws {
  let data = Data(
    """
    {"date":"2026-06-01","summary":"Legacy","wins":"","blockers":"","learnings":""}
    """.utf8)
  #expect(throws: DecodingError.self) {
    try JSONDecoder().decode(ExportDailyReview.self, from: data)
  }
}

// MARK: - Fixtures

private func makeExportTask(title: String = "Buy milk") -> ExportTask {
  ExportTask(
    from: LorvexTask(
      id: "task-1",
      title: title,
      notes: "",
      rawInput: "buy milk raw",
      priority: .p2,
      status: .open,
      dueDate: nil,
      plannedDate: LorvexDateFormatters.iso8601.date(from: "2026-06-02T00:00:00Z"),
      availableFrom: LorvexDateFormatters.iso8601.date(from: "2026-06-01T00:00:00Z"),
      estimatedMinutes: nil,
      tags: [],
      checklistItems: [
        TaskChecklistItem(
          id: "44444444-4444-4444-8444-444444444444",
          taskID: "task-1",
          position: 0,
          text: "Pack bag",
          completedAt: "2026-06-01T08:00:00Z",
          createdAt: "2026-05-31T08:00:00Z",
          updatedAt: "2026-06-01T08:00:00Z")
      ],
      reminders: [
        TaskReminder(
          id: "55555555-5555-4555-8555-555555555555",
          reminderAt: "2026-06-01T09:00:00Z",
          status: nil,
          createdAt: "2026-05-31T09:00:00Z",
          originalLocalTime: "09:00",
          originalTz: "America/Los_Angeles")
      ],
      deferCount: 2,
      lastDeferReason: "low_energy",
      lastDeferredAt: "2026-06-01T10:00:00Z",
      createdAt: "2026-05-30T10:00:00Z",
      updatedAt: "2026-06-01T11:00:00Z",
      archivedAt: "2026-06-03T12:00:00Z"
    )
  )
}

private func makeExportList() -> ExportList {
  ExportList(
    from: LorvexList(
      id: "list-1",
      name: "Inbox",
      color: nil,
      icon: nil,
      description: nil,
      openCount: 0,
      totalCount: 0,
      updatedAt: "2024-01-01T00:00:00Z",
      archivedAt: "2024-01-02T00:00:00Z",
      position: 4
    )
  )
}

private func makeExportTag() -> ExportTag {
  ExportTag(
    id: "tag-1",
    displayName: "Focus",
    color: "#0EA5E9",
    createdAt: "2026-06-01T08:00:00Z",
    updatedAt: "2026-06-01T09:00:00Z")
}

private func makeExportHabit() -> ExportHabit {
  ExportHabit(
    from: LorvexHabit(
      id: "habit-1",
      name: "Morning run",
      icon: "figure.run",
      color: "#22C55E",
      cue: nil,
      frequencyType: "daily",
      targetCount: 1,
      completionsToday: 0,
      totalCompletions: 10,
      completionRate30d: 0.9,
      archived: true,
      position: 7
    ),
    completions: [
      ExportHabitCompletion(
        completedDate: "2026-06-01",
        value: 1,
        note: "good run",
        createdAt: "2026-06-01T08:00:00Z",
        updatedAt: "2026-06-01T08:01:00Z")
    ],
    reminderPolicies: [
      ExportHabitReminderPolicy(
        id: "policy-1",
        reminderTime: "07:30",
        enabled: false,
        createdAt: "2026-05-31T07:00:00Z",
        updatedAt: "2026-06-01T07:00:00Z")
    ]
  )
}

private func makeExportEvent() -> ExportCalendarEvent {
  var event = ExportCalendarEvent(
    from: CalendarTimelineEvent(
      id: "event-1",
      title: "Team sync",
      source: "lorvex",
      editable: true,
      startDate: "2024-01-01",
      startTime: "10:00",
      endDate: "2024-01-01",
      endTime: "11:00",
      allDay: false,
      location: "HQ",
      notes: "Discuss launch",
      url: "https://example.com/agenda",
      color: "#2563EB",
      eventType: "event",
      personName: "Ava",
      attendees: [
        CalendarEventAttendee(email: "team@example.com", name: "Team")
      ],
      timezone: "America/Los_Angeles",
      isRecurring: true,
      recurrenceRule: #"{"FREQ":"WEEKLY"}"#
    )
  )
  event.recurrenceGeneration = "1704067200000_0000_1111111111111111"
  return event
}

private func makeExportTaskCalendarEventLink() -> ExportTaskCalendarEventLink {
  ExportTaskCalendarEventLink(
    taskID: "task-1",
    calendarEventID: "event-1",
    createdAt: "2026-06-01T08:00:00Z",
    updatedAt: "2026-06-01T09:00:00Z")
}

private func makeExportReview() -> ExportDailyReview {
  ExportDailyReview(
    from: DailyReviewEntry(
      date: "2024-01-01",
      summary: "Productive day",
      mood: 4,
      energyLevel: 3,
      wins: "Shipped feature",
      blockers: nil,
      learnings: nil,
      timezone: "America/Los_Angeles",
      updatedAt: "2024-01-01T23:59:00Z",
      linkedTaskIDs: ["task-1"],
      linkedListIDs: ["list-1"]
    )
  )
}

private func makeExportMemory() -> ExportMemoryEntry {
  ExportMemoryEntry(
    id: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
    key: "memory-1",
    content: "Preserve this",
    updatedAt: "2024-01-02T00:00:00Z")
}

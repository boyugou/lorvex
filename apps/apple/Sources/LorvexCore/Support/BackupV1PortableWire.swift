import Foundation
import LorvexDomain

struct BackupV1ChecklistItem: Codable, Sendable, Equatable {
  var id: String
  var position: Int?
  var text: String
  var completed: Bool
  var completedAt: String?
  var createdAt: String?
  var updatedAt: String?

  init(current: ExportChecklistItem) throws {
    id = try BackupV1WireValidation.canonicalIdentity(
      current.id, field: "tasks.checklist.id")
    position = current.position
    text = current.text
    completed = current.completed
    completedAt = current.completedAt
    createdAt = current.createdAt
    updatedAt = current.updatedAt
  }

  func current() throws -> ExportChecklistItem {
    let identity = try BackupV1WireValidation.canonicalIdentity(
      id, field: "tasks.checklist.id")
    return ExportChecklistItem(
      id: identity, position: position, text: text, completed: completed,
      completedAt: completedAt, createdAt: createdAt, updatedAt: updatedAt)
  }
}

struct BackupV1TaskReminder: Codable, Sendable, Equatable {
  var id: String
  var reminderAt: String
  var dismissedAt: String?
  var cancelledAt: String?
  var createdAt: String?
  var originalLocalTime: String?
  var originalTz: String?

  init(current: ExportTaskReminder) throws {
    id = try BackupV1WireValidation.canonicalIdentity(
      current.id, field: "tasks.reminders.id")
    reminderAt = current.reminderAt
    dismissedAt = current.dismissedAt
    cancelledAt = current.cancelledAt
    createdAt = current.createdAt
    originalLocalTime = current.originalLocalTime
    originalTz = current.originalTz
  }

  func current() throws -> ExportTaskReminder {
    let identity = try BackupV1WireValidation.canonicalIdentity(
      id, field: "tasks.reminders.id")
    return ExportTaskReminder(
      id: identity, reminderAt: reminderAt, dismissedAt: dismissedAt,
      cancelledAt: cancelledAt, createdAt: createdAt,
      originalLocalTime: originalLocalTime, originalTz: originalTz)
  }
}

struct BackupV1RecurrenceRule: Codable, Sendable, Equatable {
  var freq: String
  var interval: Int?
  var byDay: [String]?
  var byMonth: [Int]?
  var byMonthDay: [Int]?
  var bySetPos: [Int]?
  var wkst: String?
  var until: String?
  var count: Int?
  var anchor: String?

  init(current: ExportRecurrenceRule) {
    freq = current.freq
    interval = current.interval
    byDay = current.byDay
    byMonth = current.byMonth
    byMonthDay = current.byMonthDay
    bySetPos = current.bySetPos
    wkst = current.wkst
    until = current.until
    count = current.count
    anchor = current.anchor
  }

  var current: ExportRecurrenceRule { ExportRecurrenceRule(v1: self) }
}

extension ExportRecurrenceRule {
  fileprivate init(v1: BackupV1RecurrenceRule) {
    freq = v1.freq
    interval = v1.interval
    byDay = v1.byDay
    byMonth = v1.byMonth
    byMonthDay = v1.byMonthDay
    bySetPos = v1.bySetPos
    wkst = v1.wkst
    until = v1.until
    count = v1.count
    anchor = v1.anchor
  }
}

struct BackupV1Task: Codable, Sendable {
  var id: String
  var title: String
  var notes: String?
  var priority: String
  var status: String
  var dueDate: String?
  var plannedDate: String?
  var availableFrom: String?
  var estimatedMinutes: Int?
  var tags: [String]?
  var rawInput: String?
  var dependsOn: [String]?
  var listID: String?
  var aiNotes: String?
  var checklist: [BackupV1ChecklistItem]?
  var reminders: [BackupV1TaskReminder]?
  var recurrence: BackupV1RecurrenceRule?
  var recurrenceExceptions: [String]?
  var deferCount: Int?
  var lastDeferReason: String?
  var lastDeferredAt: String?
  var completedAt: String?
  var createdAt: String?
  var updatedAt: String?
  var archivedAt: String?

  init(current: ExportTask) throws {
    id = current.id
    title = current.title
    notes = current.notes
    priority = current.priority
    status = current.status
    dueDate = current.dueDate
    plannedDate = current.plannedDate
    availableFrom = current.availableFrom
    estimatedMinutes = current.estimatedMinutes
    tags = current.tags
    rawInput = current.rawInput
    dependsOn = current.dependsOn
    listID = current.listID
    aiNotes = current.aiNotes
    checklist = try current.checklist?.map(BackupV1ChecklistItem.init(current:))
    reminders = try current.reminders?.map(BackupV1TaskReminder.init(current:))
    recurrence = current.recurrence.map(BackupV1RecurrenceRule.init(current:))
    recurrenceExceptions = current.recurrenceExceptions
    deferCount = current.deferCount
    lastDeferReason = current.lastDeferReason
    lastDeferredAt = current.lastDeferredAt
    completedAt = current.completedAt
    createdAt = current.createdAt
    updatedAt = current.updatedAt
    archivedAt = current.archivedAt
  }

  func current() throws -> ExportTask {
    ExportTask(
      id: id, title: title, notes: notes, priority: priority, status: status,
      dueDate: dueDate, plannedDate: plannedDate, availableFrom: availableFrom,
      estimatedMinutes: estimatedMinutes, tags: tags, rawInput: rawInput,
      dependsOn: dependsOn, listID: listID, aiNotes: aiNotes,
      checklist: try checklist?.map { try $0.current() },
      reminders: try reminders?.map { try $0.current() },
      recurrence: recurrence?.current,
      recurrenceExceptions: recurrenceExceptions, deferCount: deferCount,
      lastDeferReason: lastDeferReason, lastDeferredAt: lastDeferredAt,
      completedAt: completedAt, createdAt: createdAt, updatedAt: updatedAt,
      archivedAt: archivedAt)
  }
}

struct BackupV1List: Codable, Sendable, Equatable {
  var id: String
  var name: String
  var description: String?
  var color: String?
  var icon: String?
  var aiNotes: String?
  var archivedAt: String?
  var position: Int64

  init(current: ExportList) {
    id = current.id
    name = current.name
    description = current.description
    color = current.color
    icon = current.icon
    aiNotes = current.aiNotes
    archivedAt = current.archivedAt
    position = current.position
  }

  var current: ExportList {
    ExportList(
      id: id, name: name, description: description, color: color, icon: icon,
      aiNotes: aiNotes, archivedAt: archivedAt, position: position)
  }
}

struct BackupV1Tag: Codable, Sendable, Equatable {
  var id: String
  var displayName: String
  var color: String?
  var createdAt: String?
  var updatedAt: String?

  init(current: ExportTag) {
    id = current.id
    displayName = current.displayName
    color = current.color
    createdAt = current.createdAt
    updatedAt = current.updatedAt
  }

  var current: ExportTag {
    ExportTag(
      id: id, displayName: displayName, color: color,
      createdAt: createdAt, updatedAt: updatedAt)
  }
}

struct BackupV1HabitCompletion: Codable, Sendable, Equatable {
  var completedDate: String
  var value: Int
  var note: String?
  var createdAt: String
  var updatedAt: String

  init(current: ExportHabitCompletion) {
    completedDate = current.completedDate
    value = current.value
    note = current.note
    createdAt = current.createdAt
    updatedAt = current.updatedAt
  }

  var current: ExportHabitCompletion {
    ExportHabitCompletion(
      completedDate: completedDate, value: value, note: note,
      createdAt: createdAt, updatedAt: updatedAt)
  }
}

struct BackupV1HabitReminderPolicy: Codable, Sendable, Equatable {
  var id: String
  var reminderTime: String
  var enabled: Bool
  var createdAt: String
  var updatedAt: String

  init(current: ExportHabitReminderPolicy) {
    id = current.id
    reminderTime = current.reminderTime
    enabled = current.enabled
    createdAt = current.createdAt
    updatedAt = current.updatedAt
  }

  var current: ExportHabitReminderPolicy {
    ExportHabitReminderPolicy(
      id: id, reminderTime: reminderTime, enabled: enabled,
      createdAt: createdAt, updatedAt: updatedAt)
  }
}

struct BackupV1Habit: Codable, Sendable {
  var id: String
  var name: String
  var cue: String
  var frequencyType: String
  var weekdays: [Int]
  var perPeriodTarget: Int?
  var dayOfMonth: Int?
  var targetCount: Int
  var milestoneTarget: Int?
  var icon: String?
  var color: String?
  var archived: Bool
  var position: Int64
  var completions: [BackupV1HabitCompletion]
  var reminderPolicies: [BackupV1HabitReminderPolicy]

  init(current: ExportHabit) {
    id = current.id
    name = current.name
    cue = current.cue
    frequencyType = current.frequencyType
    weekdays = current.weekdays
    perPeriodTarget = current.perPeriodTarget
    dayOfMonth = current.dayOfMonth
    targetCount = current.targetCount
    milestoneTarget = current.milestoneTarget
    icon = current.icon
    color = current.color
    archived = current.archived
    position = current.position
    completions = current.completions.map(BackupV1HabitCompletion.init(current:))
    reminderPolicies = current.reminderPolicies.map(BackupV1HabitReminderPolicy.init(current:))
  }

  var current: ExportHabit {
    ExportHabit(
      id: id, name: name, cue: cue, icon: icon, color: color,
      frequencyType: frequencyType, weekdays: weekdays,
      perPeriodTarget: perPeriodTarget, dayOfMonth: dayOfMonth,
      targetCount: targetCount, milestoneTarget: milestoneTarget,
      archived: archived, position: position,
      completions: completions.map(\.current),
      reminderPolicies: reminderPolicies.map(\.current))
  }
}

struct BackupV1CalendarSeriesCutover: Codable, Sendable, Equatable {
  var id: String
  var lineageRootId: String
  var cutoverDate: String
  var state: String

  init(current: ExportCalendarSeriesCutover) {
    id = current.id
    lineageRootId = current.lineageRootId
    cutoverDate = current.cutoverDate
    state = current.state
  }

  var current: ExportCalendarSeriesCutover {
    ExportCalendarSeriesCutover(
      id: id, lineageRootId: lineageRootId, cutoverDate: cutoverDate, state: state)
  }
}

struct BackupV1CalendarAttendee: Codable, Sendable, Equatable {
  var email: String
  var name: String?
  var status: String?

  init(current: CalendarEventAttendee) {
    email = current.email
    name = current.name
    status = current.status
  }

  var current: CalendarEventAttendee {
    CalendarEventAttendee(email: email, name: name, status: status)
  }
}

struct BackupV1CalendarRecurrenceRule: Codable, Sendable, Equatable {
  var freq: String
  var interval: Int?
  var byDay: [String]?
  var byMonth: [Int]?
  var byMonthDay: [Int]?
  var bySetPos: [Int]?
  var wkst: String?
  var until: String?
  var count: Int?

  init(current: ExportCalendarRecurrenceRule) {
    freq = current.freq
    interval = current.interval
    byDay = current.byDay
    byMonth = current.byMonth
    byMonthDay = current.byMonthDay
    bySetPos = current.bySetPos
    wkst = current.wkst
    until = current.until
    count = current.count
  }

  var current: ExportCalendarRecurrenceRule {
    ExportCalendarRecurrenceRule(
      freq: freq, interval: interval, byDay: byDay, byMonth: byMonth,
      byMonthDay: byMonthDay, bySetPos: bySetPos, wkst: wkst,
      until: until, count: count)
  }
}

struct BackupV1CalendarEvent: Codable, Sendable {
  var id: String
  var title: String
  var startDate: String
  var startTime: String
  var endDate: String
  var endTime: String
  var allDay: Bool
  var location: String?
  var notes: String?
  var url: String?
  var color: String?
  var eventType: String
  var personName: String?
  var attendees: [BackupV1CalendarAttendee]?
  var timezone: String?
  var recurrence: BackupV1CalendarRecurrenceRule?
  var seriesId: String?
  var recurrenceInstanceDate: String?
  var occurrenceState: String?
  var recurrenceGeneration: String?
  var seriesCutoverId: String?

  init(current: ExportCalendarEvent) {
    id = current.id
    title = current.title
    startDate = current.startDate
    startTime = current.startTime
    endDate = current.endDate
    endTime = current.endTime
    allDay = current.allDay
    location = current.location
    notes = current.notes
    url = current.url
    color = current.color
    eventType = current.eventType
    personName = current.personName
    attendees = current.attendees?.map(BackupV1CalendarAttendee.init(current:))
    timezone = current.timezone
    recurrence = current.recurrence.map(BackupV1CalendarRecurrenceRule.init(current:))
    seriesId = current.seriesId
    recurrenceInstanceDate = current.recurrenceInstanceDate
    occurrenceState = current.occurrenceState
    recurrenceGeneration = current.recurrenceGeneration
    seriesCutoverId = current.seriesCutoverId
  }

  var current: ExportCalendarEvent {
    ExportCalendarEvent(
      id: id, title: title, startDate: startDate, startTime: startTime,
      endDate: endDate, endTime: endTime, allDay: allDay, location: location,
      notes: notes, url: url, color: color, eventType: eventType,
      personName: personName, attendees: attendees?.map(\.current),
      timezone: timezone, recurrence: recurrence?.current, seriesId: seriesId,
      recurrenceInstanceDate: recurrenceInstanceDate, occurrenceState: occurrenceState,
      recurrenceGeneration: recurrenceGeneration, seriesCutoverId: seriesCutoverId)
  }
}

struct BackupV1DailyReview: Codable, Sendable, Equatable {
  var date: String
  var summary: String
  var mood: Int?
  var energyLevel: Int?
  var wins: String
  var blockers: String
  var learnings: String
  var timezone: String?
  var updatedAt: String?
  var linkedTaskIDs: [String]
  var linkedListIDs: [String]

  init(current: ExportDailyReview) {
    date = current.date
    summary = current.summary
    mood = current.mood
    energyLevel = current.energyLevel
    wins = current.wins
    blockers = current.blockers
    learnings = current.learnings
    timezone = current.timezone
    updatedAt = current.updatedAt
    linkedTaskIDs = current.linkedTaskIDs
    linkedListIDs = current.linkedListIDs
  }

  var current: ExportDailyReview {
    ExportDailyReview(
      date: date, summary: summary, mood: mood, energyLevel: energyLevel,
      wins: wins, blockers: blockers, learnings: learnings,
      timezone: timezone, updatedAt: updatedAt,
      linkedTaskIDs: linkedTaskIDs, linkedListIDs: linkedListIDs)
  }
}

struct BackupV1CurrentFocus: Codable, Sendable, Equatable {
  var date: String
  var briefing: String?
  var timezone: String?
  var taskIDs: [String]
  var createdAt: String?
  var updatedAt: String?

  init(current: ExportCurrentFocus) {
    date = current.date
    briefing = current.briefing
    timezone = current.timezone
    taskIDs = current.taskIDs
    createdAt = current.createdAt
    updatedAt = current.updatedAt
  }

  var current: ExportCurrentFocus {
    ExportCurrentFocus(
      date: date, briefing: briefing, timezone: timezone, taskIDs: taskIDs,
      createdAt: createdAt, updatedAt: updatedAt)
  }
}

struct BackupV1FocusScheduleBlock: Codable, Sendable, Equatable {
  var position: Int
  var blockType: String
  var startMinutes: Int
  var endMinutes: Int
  var taskID: String?
  var calendarEventID: String?
  var eventSource: String?
  var title: String?

  init(current: ExportFocusScheduleBlock) {
    position = current.position
    blockType = current.blockType
    startMinutes = current.startMinutes
    endMinutes = current.endMinutes
    taskID = current.taskID
    calendarEventID = current.calendarEventID
    eventSource = current.eventSource?.rawValue
    title = current.title
  }

  func current() throws -> ExportFocusScheduleBlock {
    let source: FocusScheduleEventSource?
    if let eventSource {
      guard let parsed = FocusScheduleEventSource(rawValue: eventSource) else {
        throw BackupV1WireError.invalidFocusEventSource(eventSource)
      }
      source = parsed
    } else {
      source = nil
    }
    return ExportFocusScheduleBlock(
      position: position, blockType: blockType, startMinutes: startMinutes,
      endMinutes: endMinutes, taskID: taskID, calendarEventID: calendarEventID,
      eventSource: source, title: title)
  }
}

struct BackupV1FocusSchedule: Codable, Sendable {
  var date: String
  var rationale: String?
  var timezone: String?
  var blocks: [BackupV1FocusScheduleBlock]
  var createdAt: String?
  var updatedAt: String?

  init(current: ExportFocusSchedule) {
    date = current.date
    rationale = current.rationale
    timezone = current.timezone
    blocks = current.blocks.map(BackupV1FocusScheduleBlock.init(current:))
    createdAt = current.createdAt
    updatedAt = current.updatedAt
  }

  func current() throws -> ExportFocusSchedule {
    ExportFocusSchedule(
      date: date, rationale: rationale, timezone: timezone,
      blocks: try blocks.map { try $0.current() },
      createdAt: createdAt, updatedAt: updatedAt)
  }
}

struct BackupV1TaskCalendarEventLink: Codable, Sendable, Equatable {
  var taskID: String
  var calendarEventID: String
  var createdAt: String?
  var updatedAt: String?

  init(current: ExportTaskCalendarEventLink) {
    taskID = current.taskID
    calendarEventID = current.calendarEventID
    createdAt = current.createdAt
    updatedAt = current.updatedAt
  }

  var current: ExportTaskCalendarEventLink {
    ExportTaskCalendarEventLink(
      taskID: taskID, calendarEventID: calendarEventID,
      createdAt: createdAt, updatedAt: updatedAt)
  }
}

struct BackupV1MemoryEntry: Codable, Sendable, Equatable {
  var id: String
  var key: String
  var content: String
  var updatedAt: String

  init(current: ExportMemoryEntry) throws {
    id = try BackupV1WireValidation.canonicalIdentity(current.id, field: "memory.id")
    key = current.key
    content = current.content
    updatedAt = current.updatedAt
  }

  func current() throws -> ExportMemoryEntry {
    ExportMemoryEntry(
      id: try BackupV1WireValidation.canonicalIdentity(id, field: "memory.id"),
      key: key, content: content, updatedAt: updatedAt)
  }
}

struct BackupV1Preference: Codable, Sendable, Equatable {
  var key: String
  var value: String

  init(current: ExportPreference) {
    key = current.key
    value = current.value
  }

  var current: ExportPreference { ExportPreference(key: key, value: value) }
}

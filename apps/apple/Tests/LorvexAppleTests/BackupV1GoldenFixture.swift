import Foundation

/// Production-shaped, immutable public-v1 wire fixture. It deliberately covers
/// every top-level category, nested task/habit/calendar/focus shapes, calendar
/// cutovers, and the native task-graph member. The compatibility test pins
/// the exact UTF-8 SHA-256; edits require an explicit contract decision.
enum BackupV1GoldenFixture {
  static let singleFileJSON = #"""
    {
      "formatVersion":"1",
      "manifest":{
        "formatVersion":"1","schemaVersion":"1","generatedAt":"2026-07-17T12:00:00.000Z",
        "source":{"platform":"apple","appVersion":"1.0.0","deviceID":"fixture-device"},
        "entityCounts":{"tasks":1,"lists":1,"tags":1,"habits":1,"calendar_events":1,"daily_reviews":1,"current_focus":1,"focus_schedules":1,"task_calendar_event_links":1,"memory":1,"preferences":1}
      },
      "lists":[{"id":"11111111-1111-4111-8111-111111111111","name":"Public v1 list","description":"Frozen backup root","color":"#5E5CE6","icon":"archivebox","aiNotes":"stable","position":7}],
      "tags":[{"id":"22222222-2222-4222-8222-222222222222","displayName":"Compatibility","color":"#0EA5E9","createdAt":"2026-07-17T12:00:00.000Z","updatedAt":"2026-07-17T12:00:00.000Z"}],
      "tasks":[{
        "id":"33333333-3333-4333-8333-333333333333","title":"Decode every v1 shape","notes":"Portable task","priority":"P2","status":"open","dueDate":"2026-07-18T00:00:00.000Z","listID":"11111111-1111-4111-8111-111111111111","tags":["Compatibility"],"rawInput":"fixture capture","dependsOn":[],"aiNotes":"golden",
        "checklist":[{"id":"44444444-4444-4444-8444-444444444444","position":0,"text":"Decode","completed":false,"createdAt":"2026-07-17T12:00:00.000Z","updatedAt":"2026-07-17T12:00:00.000Z"}],
        "reminders":[{"id":"55555555-5555-4555-8555-555555555555","reminderAt":"2026-07-18T16:30:00.000Z","createdAt":"2026-07-17T12:00:00.000Z","originalLocalTime":"09:30","originalTz":"America/Los_Angeles"}],
        "recurrence":{"freq":"WEEKLY","interval":1,"byDay":["FR"],"wkst":"MO"},"recurrenceExceptions":["2026-07-25"],"deferCount":1,"lastDeferReason":"needs_info","lastDeferredAt":"2026-07-16T12:00:00.000Z","createdAt":"2026-07-17T12:00:00.000Z","updatedAt":"2026-07-17T12:00:00.000Z"
      }],
      "nativeTaskGraph":{
        "schemaVersion":"1",
        "tasks":[{"id":"33333333-3333-4333-8333-333333333333","title":"Decode every v1 shape","body":"Portable task","rawInput":"fixture capture","aiNotes":"golden","status":"open","listID":"11111111-1111-4111-8111-111111111111","priority":2,"dueDate":"2026-07-18","recurrence":"{\"BYDAY\":[\"FR\"],\"FREQ\":\"WEEKLY\",\"INTERVAL\":1,\"WKST\":\"MO\"}","recurrenceGroupID":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","canonicalOccurrenceDate":"2026-07-18","contentVersion":"1700000000000_0000_1111111111111111","scheduleVersion":"1700000000000_0000_1111111111111111","lifecycleVersion":"1700000000000_0000_1111111111111111","archiveVersion":"1700000000000_0000_1111111111111111","recurrenceRolloverState":"none","version":"1700000000000_0000_1111111111111111","createdAt":"2026-07-17T12:00:00.000Z","updatedAt":"2026-07-17T12:00:00.000Z","lastDeferredAt":"2026-07-16T12:00:00.000Z","lastDeferReason":"needs_info","deferCount":1}],
        "recurrenceExceptions":[{"taskID":"33333333-3333-4333-8333-333333333333","exceptionDate":"2026-07-25"}],
        "tagEdges":[{"taskID":"33333333-3333-4333-8333-333333333333","tagID":"22222222-2222-4222-8222-222222222222","version":"1700000000000_0000_1111111111111111","createdAt":"2026-07-17T12:00:00.000Z"}],
        "dependencyEdges":[],
        "checklistItems":[{"id":"44444444-4444-4444-8444-444444444444","taskID":"33333333-3333-4333-8333-333333333333","position":0,"text":"Decode","version":"1700000000000_0000_1111111111111111","createdAt":"2026-07-17T12:00:00.000Z","updatedAt":"2026-07-17T12:00:00.000Z"}],
        "reminders":[{"id":"55555555-5555-4555-8555-555555555555","taskID":"33333333-3333-4333-8333-333333333333","reminderAt":"2026-07-18T16:30:00.000Z","version":"1700000000000_0000_1111111111111111","createdAt":"2026-07-17T12:00:00.000Z","originalLocalTime":"09:30","originalTimeZone":"America/Los_Angeles"}],
        "tombstones":[{"entityType":"task_reminder","entityID":"66666666-6666-4666-8666-666666666666","version":"1700000000000_0000_1111111111111111","deletedAt":"2026-07-17T12:00:00.000Z"}],
        "payloadShadows":[{"entityType":"task","entityID":"33333333-3333-4333-8333-333333333333","baseVersion":"1700000000000_0000_1111111111111111","payloadSchemaVersion":2,"rawPayloadJSON":"{\"future\":true}","sourceDeviceID":"future-peer","updatedAt":"2026-07-17T12:00:00.000Z"}]
      },
      "habits":[{"id":"77777777-7777-4777-8777-777777777777","name":"Hydrate","cue":"After waking","icon":"drop","color":"#22C55E","frequencyType":"daily","weekdays":[],"targetCount":8,"milestoneTarget":100,"archived":false,"position":2,"completions":[{"completedDate":"2026-07-17","value":3,"note":"morning","createdAt":"2026-07-17T12:00:00.000Z","updatedAt":"2026-07-17T12:00:00.000Z"}],"reminderPolicies":[{"id":"88888888-8888-4888-8888-888888888888","reminderTime":"09:30","enabled":true,"createdAt":"2026-07-17T12:00:00.000Z","updatedAt":"2026-07-17T12:00:00.000Z"}]}],
      "calendarSeriesCutovers":[{"id":"f62362b6-3f97-8822-a3f7-7de65f5e6607","lineageRootId":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","cutoverDate":"2026-08-01","state":"deleted"}],
      "calendarEvents":[{"id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","title":"Weekly sync","startDate":"2026-07-17","startTime":"10:00","endDate":"2026-07-17","endTime":"11:00","allDay":false,"location":"HQ","notes":"Discuss launch","url":"https://example.com","color":"#2563EB","eventType":"event","personName":"Ava","attendees":[{"email":"team@example.com","name":"Team","status":"accepted"}],"timezone":"America/Los_Angeles","recurrence":{"freq":"WEEKLY","interval":1,"byDay":["FR"]},"recurrenceGeneration":"1700000000000_0000_1111111111111111"}],
      "dailyReviews":[{"date":"2026-07-17","summary":"Productive day","mood":4,"energyLevel":3,"wins":"Shipped","blockers":"","learnings":"Keep fixtures","timezone":"America/Los_Angeles","updatedAt":"2026-07-17T23:00:00.000Z","linkedTaskIDs":["33333333-3333-4333-8333-333333333333"],"linkedListIDs":["11111111-1111-4111-8111-111111111111"]}],
      "currentFocus":[{"date":"2026-07-17","briefing":"Protect morning","timezone":"America/Los_Angeles","taskIDs":["33333333-3333-4333-8333-333333333333"],"createdAt":"2026-07-17T08:00:00.000Z","updatedAt":"2026-07-17T09:00:00.000Z"}],
      "focusSchedules":[{"date":"2026-07-17","rationale":"Energy first","timezone":"America/Los_Angeles","blocks":[{"position":0,"blockType":"task","startMinutes":540,"endMinutes":600,"taskID":"33333333-3333-4333-8333-333333333333"},{"position":1,"blockType":"event","startMinutes":600,"endMinutes":660,"calendarEventID":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","eventSource":"canonical","title":"Weekly sync"}],"createdAt":"2026-07-17T08:00:00.000Z","updatedAt":"2026-07-17T09:00:00.000Z"}],
      "taskCalendarEventLinks":[{"taskID":"33333333-3333-4333-8333-333333333333","calendarEventID":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","createdAt":"2026-07-17T08:00:00.000Z","updatedAt":"2026-07-17T09:00:00.000Z"}],
      "memory":[{"id":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","key":"launch-context","content":"Preserve this","updatedAt":"2026-07-17T12:00:00.000Z"}],
      "preferences":[{"key":"working_hours","value":"{\"start\":\"09:00\",\"end\":\"17:00\"}"}]
    }
    """#

  static let expectedSHA256 = "795964add8178b3ed5a6fca854bc6824b6a9e41aa100055a45920945b170827f"
  static let expectedProductionJSONSHA256 =
    "cb9ccbef39141b8106ea9ab292440a776cf6cc20405bdf612ea44bfc3759258f"
  static let expectedProductionZipSHA256 =
    "f0505ada6ef562686145cc71fb5fb3bcd357d144aefd1bff1965e894ed7956d8"
}

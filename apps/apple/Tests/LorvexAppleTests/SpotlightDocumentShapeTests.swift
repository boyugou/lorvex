import CoreSpotlight
import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

@Test
func spotlightListDocumentIndexesNameOnly() {
  let list = LorvexList(
    id: "list-abc",
    name: "Work Projects",
    color: nil,
    icon: nil,
    description: "All work-related projects",
    openCount: 3,
    totalCount: 5,
    updatedAt: "2026-05-24"
  )
  let doc = SpotlightListDocument(list: list)

  #expect(doc.identifier == "lorvex-list:list-abc")
  #expect(doc.title == "Work Projects")
  #expect(doc.deepLink == URL(string: "lorvex://list/list-abc")!)

  // The free-text description must not reach the system index.
  let attributes = doc.searchableItem.attributeSet
  #expect(attributes.title == "Work Projects")
  #expect(attributes.contentDescription == nil)
}

@Test
func spotlightHabitDocumentIndexesNameOnly() {
  let habit = LorvexHabit(
    id: "habit-run",
    name: "Morning Run",
    icon: nil,
    color: nil,
    cue: "After alarm goes off",
    frequencyType: "daily",
    targetCount: 1,
    completionsToday: 0,
    totalCompletions: 42,
    completionRate30d: 0.9,
    archived: false
  )
  let doc = SpotlightHabitDocument(habit: habit)

  #expect(doc.identifier == "lorvex-habit:habit-run")
  #expect(doc.title == "Morning Run")
  #expect(doc.deepLink == URL(string: "lorvex://habit/habit-run")!)

  // The free-text cue must not reach the system index.
  let attributes = doc.searchableItem.attributeSet
  #expect(attributes.title == "Morning Run")
  #expect(attributes.contentDescription == nil)
}

@Test
func spotlightDailyReviewDocumentIndexesDateTitleOnly() {
  let review = DailyReviewEntry(
    date: "2026-05-24",
    summary: "Productive day shipping Spotlight indexing.",
    mood: 4,
    energyLevel: 3,
    wins: nil,
    blockers: nil,
    learnings: nil,
    timezone: nil,
    updatedAt: nil,
    linkedTaskIDs: [],
    linkedListIDs: []
  )
  let doc = SpotlightDailyReviewDocument(review: review)

  #expect(doc.identifier == "lorvex-review:2026-05-24")
  #expect(doc.title == "Daily Review 2026-05-24")
  #expect(doc.deepLink == URL(string: "lorvex://review/2026-05-24")!)

  // The personal review summary must not reach the system index.
  let attributes = doc.searchableItem.attributeSet
  #expect(attributes.title == "Daily Review 2026-05-24")
  #expect(attributes.contentDescription == nil)
}

@Test
func spotlightCalendarEventDocumentIndexesTitleOnly() {
  let event = CalendarTimelineEvent(
    id: "rendered-occurrence-planning",
    eventID: "event-planning",
    title: "Planning Block",
    source: "Lorvex",
    editable: true,
    startDate: "2026-05-24",
    startTime: "09:00",
    endDate: "2026-05-24",
    endTime: "10:00",
    allDay: false,
    location: "Studio",
    color: nil,
    eventType: "focus",
    timezone: "America/Los_Angeles",
    isRecurring: false
  )
  let doc = SpotlightCalendarEventDocument(event: event)

  #expect(doc.identifier == "lorvex-calendar-event:event-planning")
  #expect(doc.title == "Planning Block")
  #expect(doc.deepLink == URL(string: "lorvex://open/calendar")!)

  // The event time, location, and source must not reach the system index.
  let attributes = doc.searchableItem.attributeSet
  #expect(attributes.title == "Planning Block")
  #expect(attributes.contentDescription == nil)
  #expect(attributes.keywords == nil)
}

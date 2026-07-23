import Foundation
import Testing

@testable import LorvexCore

/// Pins the seeded preview-core fixture: every id and display value the
/// app-layer tests and previews reference must exist in the real store after
/// the seed replay, with the store's own derived state (list counts, habit
/// stats) agreeing with the fixture's described values.
@Suite("Preview core factory — seeded fixture contract")
struct LorvexPreviewCoreFactoryTests {
  @Test("seeded tasks are loadable by id with membership, children, and recurrence")
  func seededTasks() async throws {
    let core = try await LorvexPreviewCoreFactory.makeSeeded()

    let agenda = try await core.loadTask(id: LorvexPreviewSeedID.agendaTask)
    #expect(agenda.title == "Draft the team offsite agenda")
    #expect(agenda.status == .open)
    #expect(agenda.priority == .p1)
    #expect(agenda.listID == LorvexPreviewSeedID.appleNativeList)
    #expect(agenda.tags.sorted() == ["planning", "work"])
    #expect(agenda.checklistItems.map(\.id) == [LorvexPreviewSeedID.agendaChecklistConfirm, LorvexPreviewSeedID.agendaChecklistShare])
    #expect(agenda.checklistItems.first?.completedAt != nil)
    #expect(agenda.checklistItems.last?.completedAt == nil)

    let venue = try await core.loadTask(id: LorvexPreviewSeedID.venueTask)
    #expect(venue.listID == LorvexPreviewSeedID.inboxList)
    #expect(venue.dependsOn == [LorvexPreviewSeedID.agendaTask])
    #expect(venue.reminders.map(\.id) == [LorvexPreviewSeedID.venueReminder])

    let status = try await core.loadTask(id: LorvexPreviewSeedID.statusUpdateTask)
    #expect(status.recurrence?.freq == .weekly)
    #expect(status.recurrence?.byDay == ["MO"])

    let desk = try await core.loadTask(id: LorvexPreviewSeedID.standingDeskTask)
    #expect(desk.status == .someday)
  }

  @Test("seeded lists carry the live open/total counts")
  func seededLists() async throws {
    let core = try await LorvexPreviewCoreFactory.makeSeeded()
    let catalog = try await core.loadLists()
    // The someday task also lives in the Inbox: the real schema gives every
    // task a list (`list_id` defaults to the sentinel `'inbox'`), so it counts
    // toward the total but not the open bucket.
    let inbox = try #require(catalog.lists.first { $0.id == LorvexPreviewSeedID.inboxList })
    #expect(inbox.openCount == 1)
    #expect(inbox.totalCount == 2)
    let appleNative = try #require(catalog.lists.first { $0.id == LorvexPreviewSeedID.appleNativeList })
    #expect(appleNative.openCount == 2)
    #expect(appleNative.totalCount == 2)
  }

  @Test("seeded habits reproduce the fixture's completion stats")
  func seededHabits() async throws {
    let core = try await LorvexPreviewCoreFactory.makeSeeded()
    let habits = try await core.loadHabits(date: LorvexDateFormatters.ymd.string(from: Date()))
    let review = try #require(habits.habits.first { $0.id == LorvexPreviewSeedID.dailyReviewHabit })
    #expect(review.completionsToday == 1)
    #expect(review.totalCompletions == 12)
    let walk = try #require(habits.habits.first { $0.id == LorvexPreviewSeedID.eveningWalkHabit })
    #expect(walk.completionsToday == 0)
    #expect(walk.totalCompletions == 8)
  }

  @Test("seeded calendar event renders in its timeline window")
  func seededCalendar() async throws {
    let core = try await LorvexPreviewCoreFactory.makeSeeded()
    let timeline = try await core.loadCalendarTimeline(from: "2026-05-22", to: "2026-05-29")
    let event = try #require(timeline.events.first { $0.id == LorvexPreviewSeedID.migrationReviewEvent })
    #expect(event.title == "Swift migration review")
    #expect(event.startTime == "15:00")
    #expect(event.location == "Conference Room B")
  }

  @Test("seeded memory loads both entries with their content")
  func seededMemory() async throws {
    let core = try await LorvexPreviewCoreFactory.makeSeeded()
    let memory = try await core.loadMemory()
    let notes = try #require(memory.entries.first { $0.key == "notes_for_ai" })
    #expect(notes.content.contains("framework"))
    let migration = try #require(memory.entries.first { $0.key == "swift_migration" })
    #expect(migration.content.contains("export the database"))
  }

  @Test("seeded daily review is loadable at its historical date")
  func seededReview() async throws {
    let core = try await LorvexPreviewCoreFactory.makeSeeded()
    let review = try #require(try await core.loadDailyReview(date: "2026-05-22"))
    #expect(review.summary.contains("offsite"))
    #expect(review.mood == 4)
    #expect(review.linkedTaskIDs == [LorvexPreviewSeedID.agendaTask])
    #expect(review.linkedListIDs == [LorvexPreviewSeedID.appleNativeList])
  }
}

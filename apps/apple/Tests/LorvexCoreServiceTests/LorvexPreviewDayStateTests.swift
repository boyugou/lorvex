#if DEBUG
  import Foundation
  import Testing

  @testable import LorvexCore

  /// Pins the preview day states: each moves the seeded day into the Today
  /// state its captures exist for, so a change to the seed cannot quietly turn
  /// an empty-day capture into a busy one.
  @Suite("Preview day states")
  struct LorvexPreviewDayStateTests {
    /// The preview's working day and its pinned morning clock.
    private let workingHours = (9 * 60)..<(17 * 60)
    private let morning = 11 * 60 + 20

    @Test("empty leaves nothing listed, nothing done, no meeting, and no briefing")
    func empty() async throws {
      let seededDay = try await seeded(nil)
      #expect(try await seededDay.loadToday().briefing != nil)

      let core = try await seeded(.empty)
      let page = try await page(of: core, nowMinutes: morning)
      #expect(page.facts == .empty)
      #expect(page.overbooked == nil)
      #expect(try await core.loadToday().briefing == nil)
    }

    @Test("allDone reads as done once the day's meetings are over")
    func allDone() async throws {
      let page = try await page(for: .allDone, nowMinutes: 17 * 60 + 45)
      guard case .allDone(let done) = page.facts else {
        Issue.record("expected the done facts, got \(page.facts)")
        return
      }
      #expect(done > 0)
    }

    @Test("overbooked offers to move tasks without a deadline to tomorrow")
    func overbooked() async throws {
      let page = try await page(for: .overbooked, nowMinutes: morning)
      let overbooked = try #require(page.overbooked)
      #expect(overbooked.workMinutes > overbooked.freeMinutes)
      #expect(!overbooked.candidates.isEmpty)
      for candidate in overbooked.candidates {
        #expect(candidate.dueDate == nil)
      }
    }

    /// The preview's seeded day, moved into `state` when one is given.
    private func seeded(_ state: LorvexPreviewDayState?) async throws -> SwiftLorvexCoreService {
      try await LorvexPreviewCoreFactory.makeUIPreviewSeeded(
        todaySchedule: true, plannedDay: true, dayState: state)
    }

    /// Today's page for the preview day in `state`, at `nowMinutes`.
    private func page(for state: LorvexPreviewDayState, nowMinutes: Int) async throws
      -> LorvexCalmToday
    {
      try await page(of: seeded(state), nowMinutes: nowMinutes)
    }

    /// Today's page for `core`'s day, at `nowMinutes`.
    private func page(of core: SwiftLorvexCoreService, nowMinutes: Int) async throws
      -> LorvexCalmToday
    {
      let today = try await core.loadToday()
      let day = try #require(today.logicalDay)
      return LorvexCalmToday.build(
        tasks: today.tasks,
        events: try await core.loadCalendarTimeline(from: day, to: day).events,
        doneToday: try await core.loadWidgetStatsSource().completedTodayTasks.count,
        nowMinutes: nowMinutes, logicalDay: day, workingHours: workingHours)
    }
  }
#endif

import LorvexCore
import LorvexDomain
import Testing

/// `InboundReloadScope.domains(for:)` is the conservative map from an inbound
/// sync's applied entity kinds to the reload domains their surfaces read. These
/// pin the two properties that make the selective reload safe: surface-local
/// kinds isolate to their own domain, and any signal that can't be cleanly
/// bounded returns `nil` (full-reload fallback).
@Suite("InboundReloadScope mapping")
struct InboundReloadScopeTests {

  @Test("an empty applied set is unattributable → full reload")
  func emptySetFallsBackToFull() {
    #expect(InboundReloadScope.domains(for: []) == nil)
  }

  @Test("a habit change refreshes habits and review evidence")
  func habitRefreshesHabitsAndReviews() {
    let domains = InboundReloadScope.domains(for: [.habit])
    #expect(domains == [.habits, .reviews])
    // Habit evidence remains independent of task/calendar surfaces.
    #expect(domains?.contains(.tasks) == false)
    #expect(domains?.contains(.lists) == false)
    #expect(domains?.contains(.calendar) == false)
    #expect(domains?.contains(.today) == false)
    #expect(domains?.contains(.reviews) == true)
  }

  @Test("habit completions refresh reviews; reminder policy stays habit-only")
  func habitEdgeBlastRadius() {
    #expect(InboundReloadScope.domains(for: [.habitCompletion]) == [.habits, .reviews])
    #expect(InboundReloadScope.domains(for: [.habitReminderPolicy]) == [.habits])
  }

  @Test("a calendar event refreshes linked-task and focus surfaces")
  func calendarEventReloadsRelationshipSurfaces() {
    #expect(
      InboundReloadScope.domains(for: [.calendarEvent])
        == [.calendar, .today, .tasks, .focus, .reviews])
  }

  @Test("a daily review isolates to the reviews domain")
  func dailyReviewIsolatesToReviews() {
    #expect(InboundReloadScope.domains(for: [.dailyReview]) == [.reviews])
  }

  @Test("focus kinds isolate to the focus domain")
  func focusKindsIsolateToFocus() {
    #expect(InboundReloadScope.domains(for: [.currentFocus]) == [.focus])
    #expect(InboundReloadScope.domains(for: [.focusSchedule]) == [.focus])
  }

  @Test("memory and changelog reload their distinct primary surfaces")
  func memoryAndAuditUseDistinctDomains() {
    #expect(InboundReloadScope.domains(for: [.memory]) == [.memory])
    #expect(InboundReloadScope.domains(for: [.aiChangelog]) == [.diagnostics])
  }

  @Test("a task fans out across every task-bearing surface but not habits")
  func taskFansOutBroadlyButNotHabits() throws {
    let domains = try #require(InboundReloadScope.domains(for: [.task]))
    #expect(domains.isSuperset(of: [.today, .tasks, .lists, .calendar, .focus, .reviews]))
    // Tasks and habits are independent surfaces — a task change never reloads habits.
    #expect(domains.contains(.habits) == false)
  }

  @Test("a list change also reloads review evidence; tags remain task-local")
  func listReloadsListSurfaces() throws {
    let domains = try #require(InboundReloadScope.domains(for: [.list]))
    #expect(domains == [.today, .tasks, .lists, .reviews])
    #expect(domains.contains(.habits) == false)
    #expect(domains.contains(.calendar) == false)
    #expect(InboundReloadScope.domains(for: [.tag]) == [.today, .tasks, .lists])
  }

  @Test("task children reload the selected-list detail")
  func taskChildrenReloadListDetail() {
    #expect(InboundReloadScope.domains(for: [.taskReminder]) == [.today, .tasks, .lists])
    #expect(InboundReloadScope.domains(for: [.taskChecklistItem]) == [.today, .tasks, .lists])
    #expect(InboundReloadScope.domains(for: [.taskTag]) == [.today, .tasks, .lists])
    #expect(InboundReloadScope.domains(for: [.taskDependency]) == [.today, .tasks, .lists])
    #expect(
      InboundReloadScope.domains(for: [.taskCalendarEventLink])
        == [.today, .tasks, .lists, .calendar])
  }

  @Test("a preference change is diffuse → full reload")
  func preferenceFallsBackToFull() {
    #expect(InboundReloadScope.domains(for: [.preference]) == nil)
  }

  @Test("a preference mixed with a bounded kind still forces a full reload")
  func preferenceMixedStillFull() {
    #expect(InboundReloadScope.domains(for: [.habit, .preference]) == nil)
  }

  @Test("a local-only kind arriving inbound forces a full reload")
  func localOnlyKindFallsBackToFull() {
    #expect(InboundReloadScope.domains(for: [.deviceState]) == nil)
    #expect(InboundReloadScope.domains(for: [.importSession]) == nil)
  }

  @Test("a multi-domain batch unions the affected domains")
  func multiDomainUnions() throws {
    let domains = try #require(InboundReloadScope.domains(for: [.habit, .calendarEvent, .dailyReview]))
    #expect(domains == [.habits, .calendar, .reviews, .today, .tasks, .focus])
  }

  @Test("reminders recompute only for task/habit domains")
  func remindersRecomputePredicate() {
    #expect(InboundReloadScope.recomputesReminders([.habits]))
    #expect(InboundReloadScope.recomputesReminders([.tasks]))
    #expect(InboundReloadScope.recomputesReminders([.today]))
    #expect(InboundReloadScope.recomputesReminders([.calendar]) == false)
    #expect(InboundReloadScope.recomputesReminders([.reviews]) == false)
  }

  @Test("the badge recomputes for task/today domains but not habits")
  func badgeRecomputePredicate() {
    #expect(InboundReloadScope.recomputesBadge([.tasks]))
    #expect(InboundReloadScope.recomputesBadge([.today]))
    // The badge counts due/overdue tasks only, so a habits-only change must NOT
    // recompute it — the narrower sibling of `recomputesReminders`, which does span
    // habits (asserted here so the two predicates can't silently converge).
    #expect(InboundReloadScope.recomputesBadge([.habits]) == false)
    #expect(InboundReloadScope.recomputesReminders([.habits]))
    #expect(InboundReloadScope.recomputesBadge([.calendar]) == false)
    #expect(InboundReloadScope.recomputesBadge([.reviews]) == false)
  }

  @Test("widget republishes for today/focus/habits/lists, not calendar/reviews")
  func widgetRepublishPredicate() {
    #expect(InboundReloadScope.republishesWidget([.today]))
    #expect(InboundReloadScope.republishesWidget([.habits]))
    #expect(InboundReloadScope.republishesWidget([.focus]))
    #expect(InboundReloadScope.republishesWidget([.lists]))
    #expect(InboundReloadScope.republishesWidget([.calendar]) == false)
    #expect(InboundReloadScope.republishesWidget([.reviews]) == false)
  }
}

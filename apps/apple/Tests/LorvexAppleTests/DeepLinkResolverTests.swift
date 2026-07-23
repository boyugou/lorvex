@preconcurrency import CoreSpotlight
import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

private func makeDeepLinkTestTask(
  id: String,
  title: String,
  notes: String = "",
  tags: [String] = []
) -> LorvexTask {
  LorvexTask(
    id: id,
    title: title,
    notes: notes,
    priority: .p2,
    status: .open,
    dueDate: nil,
    estimatedMinutes: nil,
    tags: tags
  )
}

// MARK: - LorvexDeepLinkRoute: URL round-trip

@Test
func deepLinkRouteURLRoundTripForEveryCase() {
  let routes: [LorvexDeepLinkRoute] = [
    .task("task-123"),
    .list("list-456"),
    .habit("habit-789"),
    .review(date: "2026-05-27"),
    .destination(.today),
    .destination(.calendar),
  ]
  for route in routes {
    let parsed = LorvexDeepLinkRoute(url: route.url)
    #expect(parsed == route)
  }
}

@Test
func sidebarSelectionMatchingAcceptsCaseVariants() {
  #expect(SidebarSelection.matching("calendar") == .calendar)
  #expect(SidebarSelection.matching("Calendar") == .calendar)
  #expect(SidebarSelection.matching("CALENDAR") == .calendar)
}

@Test
func deepLinkRouteDestinationParsingAcceptsCaseVariants() {
  #expect(
    LorvexDeepLinkRoute(url: URL(string: "lorvex://open/calendar")!)
      == .destination(.calendar))
  #expect(
    LorvexDeepLinkRoute(url: URL(string: "lorvex://open/CALENDAR")!)
      == .destination(.calendar))
}

@Test
func deepLinkRouteRejectsForeignAndMalformedURLs() {
  #expect(LorvexDeepLinkRoute(url: URL(string: "https://example.com/task/1")!) == nil)
  #expect(LorvexDeepLinkRoute(url: URL(string: "lorvex://task")!) == nil)
  #expect(LorvexDeepLinkRoute(url: URL(string: "lorvex://list/")!) == nil)
  #expect(LorvexDeepLinkRoute(url: URL(string: "lorvex://nonsense")!) == nil)
}

// MARK: - LorvexDeepLinkRoute: parameter validation
//
// Apple's guidance for custom URL schemes is to validate every parameter and
// discard malformed input rather than trust it — the scheme is an attack
// entrypoint, not a guaranteed-exclusive private channel. These exercise the
// resolver's validation directly, independent of which surface (URL / Handoff
// / Spotlight) decoded the identifier.

@Test
func deepLinkRouteRejectsImpossibleAndUnparseableReviewDates() {
  // February never has a 30th, even in a leap year.
  #expect(LorvexDeepLinkRoute(url: URL(string: "lorvex://review/2026-02-30")!) == nil)
  // Not a date at all, despite being ten characters like the canonical form.
  #expect(LorvexDeepLinkRoute(url: URL(string: "lorvex://review/not-a-date")!) == nil)
  // A well-formed date still round-trips.
  #expect(
    LorvexDeepLinkRoute(url: URL(string: "lorvex://review/2026-05-27")!)
      == .review(date: "2026-05-27"))
}

@Test
func deepLinkRouteRejectsWhitespaceOnlyAndControlCharacterIDs() {
  // Percent-encoded spaces trim to an empty id.
  #expect(LorvexDeepLinkRoute(url: URL(string: "lorvex://list/%20%20%20")!) == nil)
  // A NUL byte embedded in an otherwise-nonempty id is still rejected.
  #expect(LorvexDeepLinkRoute(url: URL(string: "lorvex://habit/task%00bad")!) == nil)
}

@Test
func deepLinkRouteRejectsOversizedIDs() {
  let hugeID = String(repeating: "a", count: 600)
  #expect(LorvexDeepLinkRoute(url: URL(string: "lorvex://habit/\(hugeID)")!) == nil)
}

// MARK: - LorvexDeepLinkRoute: NSUserActivity round-trip

@Test
func deepLinkRouteFromOpenTaskActivity() {
  let activity = makeOpenTaskActivity(taskID: "task-abc")
  #expect(LorvexDeepLinkRoute(activity: activity) == .task("task-abc"))
}

@Test
func deepLinkRouteFromOpenListActivity() {
  let activity = makeOpenListActivity(listID: "list-abc")
  #expect(LorvexDeepLinkRoute(activity: activity) == .list("list-abc"))
}

@Test
func deepLinkRouteFromOpenDestinationActivity() {
  for selection in SidebarSelection.allCases {
    let activity = makeOpenDestinationActivity(selection: selection)
    #expect(LorvexDeepLinkRoute(activity: activity) == .destination(selection))
  }
}

@Test
func deepLinkRouteFromOpenDestinationActivityAcceptsCaseVariants() {
  let activity = NSUserActivity(activityType: LorvexActivityType.openDestination)
  activity.addUserInfoEntries(from: [LorvexActivityKey.destination: "calendar"])

  #expect(LorvexDeepLinkRoute(activity: activity) == .destination(.calendar))
}

@Test
func deepLinkRouteRejectsUnknownAndEmptyActivities() {
  #expect(LorvexDeepLinkRoute(activity: NSUserActivity(activityType: "com.other.thing")) == nil)
  let emptyTask = NSUserActivity(activityType: LorvexActivityType.openTask)
  emptyTask.addUserInfoEntries(from: [LorvexActivityKey.taskID: ""])
  #expect(LorvexDeepLinkRoute(activity: emptyTask) == nil)
  let missingPayload = NSUserActivity(activityType: LorvexActivityType.openList)
  #expect(LorvexDeepLinkRoute(activity: missingPayload) == nil)
}

// MARK: - LorvexDeepLinkRoute: Spotlight identifier round-trip

@Test
func deepLinkRouteFromSpotlightIdentifiers() {
  #expect(LorvexDeepLinkRoute(spotlightIdentifier: "lorvex-task:t1") == .task("t1"))
  #expect(LorvexDeepLinkRoute(spotlightIdentifier: "lorvex-list:l1") == .list("l1"))
  #expect(LorvexDeepLinkRoute(spotlightIdentifier: "lorvex-habit:h1") == .habit("h1"))
  #expect(
    LorvexDeepLinkRoute(spotlightIdentifier: "lorvex-review:2026-05-27")
      == .review(date: "2026-05-27"))
  #expect(
    LorvexDeepLinkRoute(spotlightIdentifier: "lorvex-calendar-event:evt-1")
      == .destination(.calendar))
}

@Test
func deepLinkRouteRejectsUnknownAndEmptySpotlightIdentifiers() {
  #expect(LorvexDeepLinkRoute(spotlightIdentifier: "lorvex-task:") == nil)
  #expect(LorvexDeepLinkRoute(spotlightIdentifier: "unknown:42") == nil)
  #expect(LorvexDeepLinkRoute(spotlightIdentifier: "") == nil)
}

@Test
func spotlightDocumentIdentifierResolvesBackToItsRoute() {
  // The document builder stamps `lorvex-task:<id>`; the resolver must invert it,
  // so a tapped Spotlight result opens the indexed task.
  let task = makeDeepLinkTestTask(id: "round-trip-task", title: "Title")
  let document = SpotlightTaskDocument(task: task)
  let route = LorvexDeepLinkRoute(spotlightIdentifier: document.identifier)
  #expect(route == .task("round-trip-task"))
}

// MARK: - SpotlightTaskDocument builder

// MARK: - Spotlight reindex reads real all-tasks data

@MainActor
@Test
func spotlightReindexLoadsAllTasksFromCore() async throws {
  // The reindex narrows silently to `today.tasks` only if the bulk
  // `listTasks(status: "all")` read throws; assert the core actually serves it,
  // so the index covers every task, not just today's.
  let core = try await makeSeededInMemoryCore()
  let page = try? await core.listTasks(
    status: "all", listID: nil, priority: nil, text: nil, limit: 5000, offset: 0)
  #expect(page != nil)
  #expect((page?.tasks.count ?? 0) > 0)
}

@Test
func spotlightTaskDocumentHasStableIdentifierAndTitle() {
  let task = makeDeepLinkTestTask(
    id: "task-77",
    title: "Write the report",
    notes: "Outline first",
    tags: ["work", "urgent"]
  )
  let document = SpotlightTaskDocument(task: task)
  #expect(document.identifier == "lorvex-task:task-77")
  #expect(document.title == "Write the report")
  #expect(document.deepLink == LorvexDeepLinkRoute.task("task-77").url)

  // Notes and tags must not reach the system index.
  let attributes = document.searchableItem.attributeSet
  #expect(attributes.title == "Write the report")
  #expect(attributes.contentDescription == nil)
  #expect(attributes.keywords == nil)
}

@Test
func spotlightTaskDocumentSearchableItemCarriesIdentifierAndContentURL() {
  let task = makeDeepLinkTestTask(id: "task-88", title: "Ship it")
  let item = SpotlightTaskDocument(task: task).searchableItem
  #expect(item.uniqueIdentifier == "lorvex-task:task-88")
  #expect(item.domainIdentifier == SpotlightTaskDocument.domainIdentifier)
  #expect(item.attributeSet.contentURL == LorvexDeepLinkRoute.task("task-88").url)
}

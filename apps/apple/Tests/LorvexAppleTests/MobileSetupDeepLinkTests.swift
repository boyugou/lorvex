import Foundation
import LorvexCore
import LorvexMobile
import Testing

@Test
func mobileCaptureDraftTrimsTitleBeforeValidation() {
  #expect(!MobileCaptureDraft(title: "   ", notes: "").canSubmit)
  #expect(MobileCaptureDraft(title: " Capture native idea ", notes: "").trimmedTitle == "Capture native idea")
  #expect(MobileCaptureDraft(title: " Capture native idea ", notes: "").canSubmit)
}

@Test
func mobileSetupPreferencesPersistCompletion() {
  let suiteName = "test.MobileSetup.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suiteName)!
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let preferences = MobileSetupPreferences(defaults: defaults)

  #expect(preferences.setupCompleted == false)

  preferences.complete()

  let restored = MobileSetupPreferences(defaults: defaults)
  #expect(restored.setupCompleted == true)
}

/// Where a `lorvex://` URL lands on iPhone and iPad, through the shared parser.
private func mobileTarget(_ urlString: String) -> MobileNavigationTarget? {
  URL(string: urlString).flatMap(LorvexDeepLinkRoute.init(url:)).map(MobileNavigationTarget.init(route:))
}

@Test
func mobileDeepLinksMapAppleSystemEntrypointsToMobileNavigation() {
  // A task opens its detail over Today, whatever its id spells.
  #expect(
    mobileTarget("lorvex://task/task%20with%2Fslash")
      == MobileNavigationTarget(selectedTab: .today, path: [.task("task with/slash")]))
  #expect(
    mobileTarget("lorvex://list/list-1")
      == MobileNavigationTarget(selectedTab: .tasks, path: [.tasksScope(.list("list-1"))]))
  // Habits is not a tab: a habit opens above the Habits workspace on the
  // Tasks stack, the same stack the Tasks home's Habits row builds.
  #expect(
    mobileTarget("lorvex://habit/habit-1")
      == MobileNavigationTarget(selectedTab: .tasks, path: [.workspace(.habits), .habit("habit-1")]))
  // The day itself is an async switch the store makes after landing.
  #expect(mobileTarget("lorvex://review/2026-05-20") == MobileNavigationTarget(selectedTab: .review))
  // Capture is an action (a sheet), not a navigable destination.
  #expect(mobileTarget("lorvex://open/capture") == nil)
  #expect(mobileTarget("https://lorvex/open/today") == nil)
}

/// Every workspace destination, in both URL forms, lands on one of the four
/// tabs the bar shows. Lists is the Tasks home itself; Habits and Memory are
/// workspaces pushed onto the Tasks stack, where the Tasks home's rows lead.
@Test
func mobileDeepLinksAcceptEverySharedCoreDestination() throws {
  let expected: [SidebarSelection: MobileNavigationTarget] = [
    .today: MobileNavigationTarget(selectedTab: .today),
    .calendar: MobileNavigationTarget(selectedTab: .calendar),
    .tasks: MobileNavigationTarget(selectedTab: .tasks),
    .lists: MobileNavigationTarget(selectedTab: .tasks),
    .reviews: MobileNavigationTarget(selectedTab: .review),
    .habits: MobileNavigationTarget(selectedTab: .tasks, path: [.workspace(.habits)]),
    .memory: MobileNavigationTarget(selectedTab: .tasks, path: [.workspace(.memory)]),
  ]

  for destination in SidebarSelection.allCases {
    let target = try #require(expected[destination], "no expectation for \(destination)")
    #expect(mobileTarget("lorvex://open/\(destination.rawValue)") == target)
    #expect(mobileTarget("lorvex://\(destination.rawValue)") == target)
  }
}

@Test
func mobileIntentHandoffUsesSharedCoreKeys() {
  #expect(MobileIntentHandoff.destinationKey == LorvexIntentHandoffKeys.destination)
  #expect(MobileIntentHandoff.taskIDKey == LorvexIntentHandoffKeys.taskID)
}

@Test
func mobileIntentHandoffAcceptsCaseVariantDestinations() {
  let suiteName = "MobileIntentHandoff.caseVariants.\(UUID().uuidString)"
  defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
  LorvexIntentHandoffStore.withScopedSuiteName(suiteName) {
    MobileIntentHandoff.clear()
    defer { MobileIntentHandoff.clear() }

    MobileIntentHandoff.storeDestination("MEMORY")
    let target = MobileIntentHandoff.consumeNavigationTarget()

    // Memory opens as the workspace itself, not the Tasks home that hosts it.
    #expect(target == MobileNavigationTarget(selectedTab: .tasks, path: [.workspace(.memory)]))
  }
}

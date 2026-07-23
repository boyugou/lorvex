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

@Test
func mobileDeepLinksMapAppleSystemEntrypointsToMobileNavigation() throws {
  #expect(MobileDeepLinkRoute(url: URL(string: "lorvex://open/today")!) == .tab(.today))
  // Calendar and Habits are first-class tabs now; Reviews lives inside More.
  #expect(MobileDeepLinkRoute(url: URL(string: "lorvex://calendar")!) == .tab(.calendar))
  #expect(MobileDeepLinkRoute(url: URL(string: "lorvex://habits")!) == .tab(.habits))
  #expect(MobileDeepLinkRoute(url: URL(string: "lorvex://reviews")!) == .tab(.more))
  // Capture is an action (a sheet), not a navigable destination.
  #expect(MobileDeepLinkRoute(url: URL(string: "lorvex://open/capture")!) == nil)
  #expect(MobileDeepLinkRoute(url: URL(string: "https://lorvex/open/today")!) == nil)

  let taskRoute = try #require(
    MobileDeepLinkRoute(url: URL(string: "lorvex://task/task%20with%2Fslash")!)
  )

  #expect(taskRoute == .task("task with/slash"))
  #expect(taskRoute.navigationTarget == MobileNavigationTarget(
    selectedTab: .today,
    route: .task("task with/slash")
  ))
  #expect(MobileDeepLinkRoute.tab(.today).url.absoluteString == "lorvex://open/today")
  #expect(MobileDeepLinkRoute.tab(.tasks).url.absoluteString == "lorvex://open/tasks")
  #expect(MobileDeepLinkRoute.tab(.calendar).url.absoluteString == "lorvex://open/calendar")
  #expect(
    MobileDeepLinkRoute.task("task with/slash").url.absoluteString
      == "lorvex://task/task%20with%2Fslash")
}

@Test
func mobileDeepLinksAcceptEverySharedCoreDestination() {
  // Primary surfaces (tasks / calendar / habits) deep-link to their own tab; every
  // secondary workspace resolves into the More tab. Mirrors `tab(for:)` in
  // MobileDeepLinkRouting after the information-architecture restructure.
  let expectedTabs: [SidebarSelection: MobileTab] = [
    .today: .today,
    .tasks: .tasks,
    .lists: .more,
    .calendar: .calendar,
    .habits: .habits,
    .reviews: .more,
    .memory: .more,
  ]

  for destination in SidebarSelection.allCases {
    #expect(
      MobileDeepLinkRoute(url: URL(string: "lorvex://open/\(destination.rawValue)")!)
        == .tab(expectedTabs[destination]!)
    )
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

    #expect(target?.selectedTab == .more)
    #expect(target?.moreDestination == .memory)
  }
}

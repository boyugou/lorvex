import Foundation
import LorvexCore
import Testing

@testable import LorvexApple
@testable import LorvexMobile

// MARK: - Catalog parity: macOS vs iOS

@Test
func mobileActivityTypeMirrorsLorvexActivityType() {
  #expect(MobileActivityType.openTask == LorvexActivityType.openTask)
  #expect(MobileActivityType.openDestination == LorvexActivityType.openDestination)
  #expect(MobileActivityType.openList == LorvexActivityType.openList)
}

// MARK: - Eligibility flags

@Test
func openTaskActivityEligibilityFlags() {
  let activity = makeOpenTaskActivity(taskID: "t1", title: "My Task")
  #expect(activity.isEligibleForHandoff)
  #expect(activity.isEligibleForSearch)
  #expect(activity.title == "Continue task: My Task")
}

@Test
func openListActivityEligibilityFlags() {
  let activity = makeOpenListActivity(listID: "l1", title: "My List")
  #expect(activity.isEligibleForHandoff)
  #expect(activity.isEligibleForSearch)
  #expect(activity.title == "Open list: My List")
}

// MARK: - Deep-link contract: userInfo carries the canonical deep-link URL string

/// `webpageURL` requires HTTPS so is not set. Instead, callers use the destination
/// URL via `LorvexDeepLinkContract` for routing; the activity userInfo carries the ID.
@Test
func openTaskActivityUserInfoCarriesTaskID() {
  let taskID = "task-deep-1"
  let activity = makeOpenTaskActivity(taskID: taskID)
  #expect(activity.userInfo?[LorvexActivityKey.taskID] as? String == taskID)
  // Deep-link URL is accessible via LorvexDeepLinkContract, not webpageURL.
  #expect(activity.webpageURL == nil)
}

@Test
func openListActivityUserInfoCarriesListID() {
  let listID = "list-deep-1"
  let activity = makeOpenListActivity(listID: listID)
  #expect(activity.userInfo?[LorvexActivityKey.listID] as? String == listID)
}

@Test
func openDestinationActivityUserInfoCarriesDestinationRawValue() {
  for selection in SidebarSelection.allCases {
    let activity = makeOpenDestinationActivity(selection: selection)
    #expect(activity.userInfo?[LorvexActivityKey.destination] as? String == selection.rawValue)
  }
}

// MARK: - Task activity round-trip via builder

@Test
func openTaskActivityBuilderRoundTrip() {
  // Verify the open-task activity builder + parser pair is symmetric.
  let activity = makeOpenTaskActivity(taskID: "watch-task-1", title: "Watch Focus Task")
  let parsed = parseOpenTaskActivity(activity)
  #expect(parsed == "watch-task-1")
  #expect(activity.title == "Continue task: Watch Focus Task")
}

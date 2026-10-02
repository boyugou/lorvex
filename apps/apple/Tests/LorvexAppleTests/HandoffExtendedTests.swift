import CoreSpotlight
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

/// A titled entity activity shows the entity's own name in Spotlight, in any
/// language, and names the entity's indexed item so Spotlight lists it once.
@Test
func openTaskActivityEligibilityFlags() {
  let activity = makeOpenTaskActivity(taskID: "t1", title: "My Task")
  #expect(activity.isEligibleForHandoff)
  #expect(activity.isEligibleForSearch)
  #expect(activity.title == "My Task")
  #expect(activity.contentAttributeSet?.relatedUniqueIdentifier == "lorvex-task:t1")
}

@Test
func openListActivityEligibilityFlags() {
  let activity = makeOpenListActivity(listID: "l1", title: "My List")
  #expect(activity.isEligibleForHandoff)
  #expect(activity.isEligibleForSearch)
  #expect(activity.title == "My List")
  #expect(activity.contentAttributeSet?.relatedUniqueIdentifier == "lorvex-list:l1")
}

/// Without a title there is nothing for Spotlight to show, so the activity is
/// offered to Handoff only.
@Test
func untitledActivityIsHandoffOnly() {
  for activity in [
    makeOpenTaskActivity(taskID: "t1"), makeOpenListActivity(listID: "l1", title: ""),
    makeOpenDestinationActivity(selection: .today),
  ] {
    #expect(activity.isEligibleForHandoff)
    #expect(!activity.isEligibleForSearch)
    #expect(activity.title == nil)
  }
}

/// A destination is not an indexed entity: its activity carries the name the
/// caller's sidebar shows and links to no Spotlight item.
@Test
func openDestinationActivityUsesCallerTitle() {
  let activity = makeOpenDestinationActivity(selection: .calendar, title: "日历")
  #expect(activity.title == "日历")
  #expect(activity.isEligibleForSearch)
  #expect(activity.contentAttributeSet == nil)
}

/// The identifier an activity links to is the one the Spotlight indexer gives
/// the entity's item, and it routes back to the same entity.
@Test
func spotlightIdentifiersAgreeWithIndexedItems() {
  let pairs: [(LorvexDeepLinkRoute, String)] = [
    (.task("t1"), SpotlightTaskDocument.identifierPrefix + "t1"),
    (.list("l1"), SpotlightListDocument.identifierPrefix + "l1"),
    (.habit("h1"), SpotlightHabitDocument.identifierPrefix + "h1"),
    (.review(date: "2026-05-24"), SpotlightDailyReviewDocument.identifierPrefix + "2026-05-24"),
  ]
  for (route, identifier) in pairs {
    #expect(route.spotlightIdentifier == identifier)
    #expect(LorvexDeepLinkRoute(spotlightIdentifier: identifier) == route)
  }
  #expect(LorvexDeepLinkRoute.destination(.today).spotlightIdentifier == nil)
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
  let activity = makeOpenTaskActivity(taskID: "watch-task-1", title: "Watch Task")
  let parsed = parseOpenTaskActivity(activity)
  #expect(parsed == "watch-task-1")
  #expect(activity.title == "Watch Task")
}

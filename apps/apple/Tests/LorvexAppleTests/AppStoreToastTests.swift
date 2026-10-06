import Foundation
import Testing

@testable import LorvexApple

@MainActor
@Test
func anUndismissedToastClearsItselfAfterTheStoreLifetime() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  store.toastLifetime = .milliseconds(20)

  store.toastMessage = "Captured 1 task to Inbox."
  let expiry = try #require(store.toastExpiry)
  #expect(store.toastMessage != nil)

  // Waiting on the expiry itself rather than on a deadline keeps the test
  // independent of how long a loaded run takes to get back to the main actor.
  await expiry.value

  #expect(store.toastMessage == nil)
}

@MainActor
@Test
func theExpiryLeavesAMessageThatReplacedTheOneItWasSetFor() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())

  store.toastMessage = "Older"
  store.toastMessage = "Newer"
  store.expireToast(ifStill: "Older")
  #expect(store.toastMessage == "Newer")

  store.expireToast(ifStill: "Newer")
  #expect(store.toastMessage == nil)
}

@MainActor
@Test
func clearingAToastCancelsItsPendingExpiry() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  store.toastMessage = "Shown"
  #expect(store.toastExpiry != nil)

  // The toast view clears the message when it auto-dismisses or is tapped.
  store.toastMessage = nil

  #expect(store.toastExpiry == nil)
}

@MainActor
@Test
func everyNewToastRestartsTheClockSoAnEarlierExpiryDoesNotCutItShort() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  store.toastMessage = "First"
  let first = try #require(store.toastExpiry)

  store.toastMessage = "Second"

  #expect(first.isCancelled)
  #expect(store.toastExpiry != nil)
  #expect(store.toastMessage == "Second")
}

@MainActor
@Test
func theQuickCaptureWriteLeavesNoToastButTheCaptureLineStillSetsOne() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.refresh()

  // Quick Capture shows its own confirmation, so the write alone sets no toast.
  let receipt = await store.commitCapture("Quick capture write")
  #expect(receipt != nil)
  #expect(store.toastMessage == nil)

  // The menu bar and the palette have no confirmation of their own.
  await store.captureLine("Menu bar write")
  #expect(store.toastMessage != nil)
}

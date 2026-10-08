import Foundation
import LorvexCore
import Observation
import Testing

@testable import LorvexApple

/// The event form's draft fields and the loaded timeline sit in separate
/// observed storage values, so a keystroke in the form does not tell the grids
/// that read the timeline to draw again, and a timeline reload does not redraw
/// the form's fields. These tests read through `withObservationTracking`, the
/// mechanism SwiftUI uses, and check which reads a change reaches.

/// Whether a tracked read was told that one of its inputs changed. The change
/// callback is `@Sendable`, so the flag is a class instead of a captured `var`.
private final class ChangeFlag: @unchecked Sendable {
  private let lock = NSLock()
  private var value = false
  var fired: Bool { lock.withLock { value } }
  func set() { lock.withLock { value = true } }
}

/// Runs `read` under observation tracking and returns the flag its change
/// callback sets on the first change to anything `read` touched.
@MainActor
private func track(_ read: () -> Void) -> ChangeFlag {
  let flag = ChangeFlag()
  withObservationTracking(read, onChange: { flag.set() })
  return flag
}

@MainActor
private func makeStore() async throws -> (store: AppStore, cleanup: () -> Void) {
  let suiteName = "lorvexCalendarDraftObservationTests.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defaults.removePersistentDomain(forName: suiteName)
  let store = AppStore(core: try await makeSeededInMemoryCore(), defaults: defaults)
  return (store, { defaults.removePersistentDomain(forName: suiteName) })
}

@MainActor
@Test
func typingInTheEventFormDoesNotReachReadersOfTheTimeline() async throws {
  let (store, cleanup) = try await makeStore()
  defer { cleanup() }
  let timelineReader = track {
    _ = store.calendarTimeline
    _ = store.calendarScheduledTasks
    _ = store.calendarUnplannedTasks
    _ = store.selectedCalendarEventID
  }

  store.draftCalendarTitle = "Dentist"
  store.draftCalendarLocation = "Clinic"
  store.draftCalendarNotes = "Bring the forms"
  store.draftCalendarTiming = CalendarEventTiming.timed(startingAt: Date())
  store.draftCalendarRecurrence = nil

  #expect(!timelineReader.fired)
}

@MainActor
@Test
func theEventFormStillSeesItsOwnDraftChanges() async throws {
  let (store, cleanup) = try await makeStore()
  defer { cleanup() }
  let titleReader = track { _ = store.draftCalendarTitle }
  let timingReader = track { _ = store.draftCalendarTiming }

  store.draftCalendarTitle = "Dentist"
  store.draftCalendarTiming = CalendarEventTiming.timed(startingAt: Date())

  #expect(titleReader.fired)
  #expect(timingReader.fired)
}

@MainActor
@Test
func aTimelineChangeStillReachesReadersOfTheTimeline() async throws {
  let (store, cleanup) = try await makeStore()
  defer { cleanup() }
  let timelineReader = track { _ = store.calendarTimeline }

  store.calendarTimeline = nil

  #expect(timelineReader.fired)
}

@MainActor
@Test
func aTimelineChangeDoesNotReachReadersOfTheEventForm() async throws {
  let (store, cleanup) = try await makeStore()
  defer { cleanup() }
  let formReader = track {
    _ = store.draftCalendarTitle
    _ = store.draftCalendarTiming
    _ = store.draftCalendarLocation
    _ = store.draftCalendarNotes
  }

  store.calendarTimeline = nil
  store.selectedCalendarEventID = "event-1"

  #expect(!formReader.fired)
}

@MainActor
@Test
func resettingTheRuntimeClearsTheEventFormDraft() async throws {
  let (store, cleanup) = try await makeStore()
  defer { cleanup() }
  store.draftCalendarTitle = "Dentist"
  store.draftCalendarLocation = "Clinic"
  store.draftCalendarNotes = "Bring the forms"
  store.draftCalendarTargetCalendarID = "calendar-1"

  store.resetRuntimeState()

  #expect(store.draftCalendarTitle == "")
  #expect(store.draftCalendarLocation == "")
  #expect(store.draftCalendarNotes == "")
  #expect(store.draftCalendarTargetCalendarID == nil)
  #expect(store.draftCalendarRecurrence == nil)
}

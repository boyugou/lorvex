import LorvexCore
import Testing

// MARK: - only-selected vs all-except: the empty-set distinction

@Test
func onlySelectedWithEmptySelectionMirrorsNothing() {
  // Privacy footgun guard: a user who switches to "only selected" and then
  // deselects every calendar must mirror NOTHING, not everything.
  let filter = EventKitCalendarFilter(
    mode: .onlySelected,
    selectedCalendarIDs: [],
    excludedCalendarIDs: []
  )

  #expect(filter.restrictsToIncluded)
  #expect(!filter.allows(calendarID: "work"))
  #expect(!filter.allows(calendarID: "personal"))
  #expect(!filter.allows(calendarID: nil))
  #expect(!filter.isDefault)
}

@Test
func onlySelectedMirrorsOnlyTheSelectedCalendars() {
  let filter = EventKitCalendarFilter(
    mode: .onlySelected,
    selectedCalendarIDs: ["work"],
    excludedCalendarIDs: []
  )

  #expect(filter.allows(calendarID: "work"))
  #expect(!filter.allows(calendarID: "personal"))
  #expect(!filter.allows(calendarID: nil))
}

@Test
func allExceptWithEmptyExclusionMirrorsEverything() {
  let filter = EventKitCalendarFilter(
    mode: .allExcept,
    selectedCalendarIDs: [],
    excludedCalendarIDs: []
  )

  #expect(!filter.restrictsToIncluded)
  #expect(filter.allows(calendarID: "work"))
  #expect(filter.allows(calendarID: "anything"))
  #expect(filter.allows(calendarID: nil))
  #expect(filter.isDefault)
}

@Test
func allExceptDeniesOnlyExcludedCalendars() {
  let filter = EventKitCalendarFilter(
    mode: .allExcept,
    selectedCalendarIDs: [],
    excludedCalendarIDs: ["personal"]
  )

  #expect(filter.allows(calendarID: "work"))
  #expect(!filter.allows(calendarID: "personal"))
  #expect(filter.allows(calendarID: nil))
  #expect(!filter.isDefault)
}

@Test
func emptyOnlySelectedIsNotEqualToTheAllFilter() {
  let none = EventKitCalendarFilter(
    mode: .onlySelected,
    selectedCalendarIDs: [],
    excludedCalendarIDs: []
  )
  #expect(none != EventKitCalendarFilter.all)
  #expect(EventKitCalendarFilter.all.allows(calendarID: "anything"))
}

@Test
func twoArgInitTreatsEmptyIncludeSetAsAllExcept() {
  // The allow-list/deny-list constructor keeps its historical meaning: an empty
  // include set is the all-except shape, never an empty only-selected one.
  let filter = EventKitCalendarFilter(includedCalendarIDs: [], excludedCalendarIDs: [])
  #expect(!filter.restrictsToIncluded)
  #expect(filter.allows(calendarID: "anything"))
}

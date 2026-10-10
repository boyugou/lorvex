import Foundation
import Testing

private func source(_ path: String) throws -> String {
  let url = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appending(path: path)
  return try String(contentsOf: url, encoding: .utf8)
}

@Test("The calendar search results cover the grid without replacing it")
func calendarSearchResultsOverlayTheGrid() throws {
  let text = try source("Sources/LorvexMobile/MobileStoreCalendarView.swift")

  // Swapping the grid for the list would rebuild the day, week, or month at
  // today when the search closed; an overlay keeps the grid's page and scroll.
  let grid = try #require(text.range(of: "switch store.calendarPresentationMode"))
  let hidden = try #require(text.range(of: ".accessibilityHidden(isSearching)"))
  let overlay = try #require(text.range(of: "MobileCalendarSearchResults(store: store"))
  #expect(grid.lowerBound < hidden.lowerBound)
  #expect(hidden.lowerBound < overlay.lowerBound)
  #expect(text.contains(".overlay {"))
  // The iPad's mode picker stays reachable beside the open field, so a mode
  // change has to leave the search.
  #expect(text.contains(".onChange(of: store.calendarPresentationMode) { searchQuery = \"\" }"))
}

@Test("The calendar grids take no search text of their own")
func calendarGridsDoNotFilterBySearchText() throws {
  for path in [
    "Sources/LorvexMobile/MobileCalendarDayView.swift",
    "Sources/LorvexMobile/MobileCalendarMonthView.swift",
    "Sources/LorvexMobile/MobileCalendarDayView+Agenda.swift",
  ] {
    #expect(!(try source(path)).contains("searchQuery"), "\(path)")
  }
}

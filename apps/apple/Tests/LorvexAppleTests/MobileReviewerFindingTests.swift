import Foundation
import Testing

@Test
func mobileReviewerFindingSourceGuards() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  func mobileSource(_ path: String) throws -> String {
    try String(
      contentsOf: root.appending(path: "Sources/LorvexMobile/\(path)"),
      encoding: .utf8
    )
  }

  let heatmap = try mobileSource("MobileHabitVisualizationSection.swift")
  #expect(heatmap.contains("@State private var cachedGrid: HabitHeatmapModel.Grid"))
  #expect(!heatmap.contains("private var grid: HabitHeatmapModel.Grid"))
  #expect(heatmap.contains(".animation(.easeInOut(duration: 0.25), value: fraction)"))
  // Every heatmap cell, in the grid and in the legend, is the one cell view
  // that draws the mark telling its state apart without color.
  #expect(heatmap.contains("MobileHabitHeatmapCell(intensity: cell.intensity, tint: tint)"))
  #expect(heatmap.contains(".overlay { cue }"))

  let suggestionRows = try mobileSource("MobileTodayScheduleSheet.swift")
  #expect(suggestionRows.contains("struct MobileTodaySuggestedTimesRows: View"))
  #expect(suggestionRows.contains("ProgressView()"))
  #expect(suggestionRows.contains("store.dismissSuggestedDayTimes()"))
  #expect(suggestionRows.contains("LorvexProposedScheduleRows("))

  // The rows the suggestion shares with the Mac write clock labels and key each
  // event by its position, since two events can carry identical values.
  let sharedProposalRows = try String(
    contentsOf: root.appending(path: "Sources/LorvexCore/Support/LorvexProposedScheduleRows.swift"),
    encoding: .utf8
  )
  #expect(sharedProposalRows.contains("lorvexClockTimeLabel(minutes: placement.time.lowerBound)"))
  #expect(sharedProposalRows.contains("proposal.events.enumerated().map { Row.event($1, index: $0) }"))

  let skeleton = try mobileSource("MobileSkeletonLoading.swift")
  #expect(skeleton.contains(".mobileSkeletonShimmer()"))
  #expect(skeleton.contains(".allowsHitTesting(false)"))
}

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
  #expect(heatmap.contains("cue(for: cell.intensity)"))

  let focusSection = try mobileSource("MobileStoreFocusScheduleSection.swift")
  #expect(focusSection.contains("ProgressView()"))
  #expect(focusSection.contains("store.discardProposedFocusSchedule()"))
  #expect(focusSection.contains("mobileClockTimeLabel(block.startTime)"))
  #expect(
    focusSection.contains(
      "ForEach(Array(displayedSchedule.blocks.enumerated()), id: \\.offset)"))

  let todayRegular = try mobileSource("MobileStoreTodayRegularView.swift")
  #expect(
    todayRegular.contains(
      "ForEach(Array(displayedSchedule.blocks.enumerated()), id: \\.offset)"))

  let skeleton = try mobileSource("MobileSkeletonLoading.swift")
  #expect(skeleton.contains(".mobileSkeletonShimmer()"))
  #expect(skeleton.contains(".allowsHitTesting(false)"))
}

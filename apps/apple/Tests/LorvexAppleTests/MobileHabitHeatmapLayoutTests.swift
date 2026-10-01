import Foundation
import Testing

@testable import LorvexMobile

@Suite("MobileHabitHeatmapLayout")
struct MobileHabitHeatmapLayoutTests {
  @Test("The layout shows the newest columns its width fits, between a season and a year")
  func shownColumnsFollowTheWidth() {
    // A 10pt cell plus 3pt spacing is 13pt per column; the last column has no
    // trailing spacing.
    #expect(MobileHabitHeatmapLayout.shownColumns(of: 52, fitting: 0) == 16)
    #expect(MobileHabitHeatmapLayout.shownColumns(of: 52, fitting: 100) == 16)
    #expect(MobileHabitHeatmapLayout.shownColumns(of: 52, fitting: 21 * 13 - 3) == 21)
    #expect(MobileHabitHeatmapLayout.shownColumns(of: 52, fitting: 21 * 13 - 4) == 20)
    #expect(MobileHabitHeatmapLayout.shownColumns(of: 52, fitting: 2000) == 52)
    #expect(MobileHabitHeatmapLayout.shownColumns(of: 12, fitting: 2000) == 12)
  }

  @Test("An unbounded width shows every column")
  func unboundedWidthShowsEverything() {
    #expect(MobileHabitHeatmapLayout.shownColumns(of: 52, fitting: nil) == 52)
    #expect(MobileHabitHeatmapLayout.shownColumns(of: 52, fitting: .infinity) == 52)
  }

  @Test("The grid is as wide as its shown columns")
  func widthFollowsTheColumns() {
    // 21 columns of 10pt with 20 gaps of 3pt.
    #expect(MobileHabitHeatmapLayout.width(ofColumns: 21) == 270)
    #expect(MobileHabitHeatmapLayout.width(ofColumns: 1) == 10)
    #expect(MobileHabitHeatmapLayout.width(ofColumns: 0) == 0)
  }
}

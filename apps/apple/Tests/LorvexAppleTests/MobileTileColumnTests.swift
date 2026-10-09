import CoreGraphics
import Foundation
import Testing

@testable import LorvexMobile

// A tile grows with the body text from its design size and stops at 48 points;
// the "New List" row's icon column takes its width from the same computation,
// so its title keeps starting where the list titles above it start.
@Test(arguments: [
  (design: CGFloat(30), scaled: CGFloat(24), side: CGFloat(30)),
  (design: CGFloat(30), scaled: CGFloat(30), side: CGFloat(30)),
  (design: CGFloat(30), scaled: CGFloat(37), side: CGFloat(37)),
  (design: CGFloat(30), scaled: CGFloat(80), side: CGFloat(48)),
  (design: CGFloat(56), scaled: CGFloat(70), side: CGFloat(56)),
])
func mobileIconTileSideTracksTheTextWithinItsBounds(design: CGFloat, scaled: CGFloat, side: CGFloat) {
  #expect(MobileIconTile.side(designSize: design, scaled: scaled) == side)
}

@Test
func theNewListRowStandsInTheTileColumns() throws {
  let sources = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appending(path: "Sources/LorvexMobile")
  let home = try String(
    contentsOf: sources.appending(path: "MobileStoreTasksHomeView.swift"), encoding: .utf8)
  let tile = try String(
    contentsOf: sources.appending(path: "MobileIconTile.swift"), encoding: .utf8)

  // A plain Label places its title by the system's own icon width, a few
  // points left of the tiled rows' titles and of the separators drawn to
  // them; the style gives the icon a tile's width and the title a tile row's
  // spacing instead.
  let newList = try #require(home.range(of: "\"lists.new\""))
  #expect(home[newList.upperBound...].prefix(400).contains(".labelStyle(MobileTileColumnLabelStyle())"))
  #expect(tile.contains(".frame(width: MobileIconTile.side(designSize: tileSize, scaled: scaledSize))"))
  #expect(tile.contains("HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.m)"))
  #expect(tile.contains("_scaledSize = ScaledMetric(wrappedValue: tileSize, relativeTo: .body)"))
}

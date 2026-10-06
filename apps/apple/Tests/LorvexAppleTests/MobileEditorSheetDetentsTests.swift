import SwiftUI
import Testing

@testable import LorvexMobile

// The detents an editor sheet offers, chosen from its kind and the text size.

@Suite("Mobile editor sheet detents")
struct MobileEditorSheetDetentsTests {
  @Test("a sheet takes medium and large by default")
  func defaultsToMediumAndLarge() {
    let detents = MobileEditorSheetDetents.detents(
      opensFullHeight: false, isAccessibilitySize: false, cardHeight: nil, textScale: 1)
    #expect(detents == [.medium, .large])
  }

  @Test("a deep editor opens at large only")
  func fullHeightOpensAtLargeOnly() {
    let detents = MobileEditorSheetDetents.detents(
      opensFullHeight: true, isAccessibilitySize: false, cardHeight: 480, textScale: 1)
    #expect(detents == [.large])
  }

  @Test("accessibility sizes open at large whatever the sheet asked for")
  func accessibilitySizesOpenAtLargeOnly() {
    let plain = MobileEditorSheetDetents.detents(
      opensFullHeight: false, isAccessibilitySize: true, cardHeight: nil, textScale: 1)
    let card = MobileEditorSheetDetents.detents(
      opensFullHeight: false, isAccessibilitySize: true, cardHeight: 480, textScale: 1)
    #expect(plain == [.large])
    #expect(card == [.large])
  }

  @Test("a card sheet replaces medium with its height, scaled by the text size")
  func cardHeightReplacesMediumAndScalesWithText() {
    let atDefault = MobileEditorSheetDetents.detents(
      opensFullHeight: false, isAccessibilitySize: false, cardHeight: 480, textScale: 1)
    let larger = MobileEditorSheetDetents.detents(
      opensFullHeight: false, isAccessibilitySize: false, cardHeight: 480, textScale: 1.25)
    #expect(atDefault == [.height(480), .large])
    #expect(larger == [.height(600), .large])
  }
}

import LorvexCore
import SwiftUI
import Testing

@testable import LorvexMobile

@Suite("Mobile detail panel inset")
struct MobileDetailPanelInsetTests {

  @Test("A phone's detail panels take the inset the Review pages use")
  func compactWidthTakesTheReviewPageInset() {
    #expect(MobileDetailPanelInset.horizontal(for: .compact) == LorvexDesign.Spacing.l)
  }

  @Test("Regular width and an unknown size class keep the split detail pane's inset")
  func regularWidthKeepsTheSplitPaneInset() {
    #expect(MobileDetailPanelInset.horizontal(for: .regular) == LorvexDesign.Spacing.xl)
    #expect(MobileDetailPanelInset.horizontal(for: nil) == LorvexDesign.Spacing.xl)
  }
}

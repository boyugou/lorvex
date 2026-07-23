import Testing

@testable import LorvexApple

// TipKit's Tip.id defaults to the type name. These tests guard against
// accidental renames that would reset user-dismissed state.
@Suite("LorvexTips")
struct LorvexTipsTests {

  @Test("MCPAssistantTip id is stable")
  func mcpAssistantTipID() {
    #expect(MCPAssistantTip().id == "MCPAssistantTip")
  }

  @Test("DailyReviewTip id is stable")
  func dailyReviewTipID() {
    #expect(DailyReviewTip().id == "DailyReviewTip")
  }

  // Title and message are non-nil (content is present).
  @Test("MCPAssistantTip has non-nil message")
  func mcpAssistantTipHasMessage() {
    #expect(MCPAssistantTip().message != nil)
  }

  @Test("DailyReviewTip has non-nil message")
  func dailyReviewTipHasMessage() {
    #expect(DailyReviewTip().message != nil)
  }
}

import Testing
@testable import LorvexMobile

@Test("Mobile list detail summary uses localized format")
func mobileListDetailSummaryUsesLocalizedFormat() {
  #expect(
    MobileListDetailFormatters.summary(totalMatching: 12, returned: 5)
      == "12 matching, 5 shown"
  )
}

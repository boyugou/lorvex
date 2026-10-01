import Testing

@testable import LorvexMobile

/// A compact week block's title shrinks only as far as its longest word needs
/// to fit the block on one line.
@Suite("Compact block title fit")
struct MobileCalendarCompactTitleFitTests {
  @Test("Short words keep the full size")
  func shortWordsKeepSize() {
    #expect(MobileCalendarCompactTitleFit.scale(title: "1:1 with Sam", size: 11, width: 40) == 1)
  }

  @Test("A word wider than the block shrinks the face to fit it")
  func longWordShrinks() {
    let scale = MobileCalendarCompactTitleFit.scale(title: "Roadmap sync", size: 11, width: 30)
    #expect(scale < 1)
    #expect(scale >= MobileCalendarCompactTitleFit.minimumScale)
  }

  @Test("The face never shrinks below the floor, and an unmeasured block keeps it whole")
  func floorAndUnmeasured() {
    #expect(
      MobileCalendarCompactTitleFit.scale(title: "Internationalization", size: 11, width: 10)
        == MobileCalendarCompactTitleFit.minimumScale)
    #expect(MobileCalendarCompactTitleFit.scale(title: "Roadmap", size: 11, width: 0) == 1)
  }
}

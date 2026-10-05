import Testing

@testable import LorvexCore

/// A compact calendar block's title shrinks only as far as its longest word
/// needs to fit the block on one line, a word that still does not fit keeps the
/// title on one line, and a lane too narrow for a few letters draws no title.
@Suite("Compact block title fit")
struct LorvexCalendarCompactTitleFitTests {
  @Test("Short words keep the full size")
  func shortWordsKeepSize() {
    #expect(LorvexCalendarCompactTitleFit.scale(title: "1:1 with Sam", size: 11, width: 40) == 1)
  }

  @Test("A word wider than the block shrinks the face to fit it")
  func longWordShrinks() {
    let scale = LorvexCalendarCompactTitleFit.scale(title: "Roadmap sync", size: 11, width: 30)
    #expect(scale < 1)
    #expect(scale >= LorvexCalendarCompactTitleFit.minimumScale)
  }

  @Test("The face never shrinks below the floor, and an unmeasured block keeps it whole")
  func floorAndUnmeasured() {
    #expect(
      LorvexCalendarCompactTitleFit.scale(title: "Internationalization", size: 11, width: 10)
        == LorvexCalendarCompactTitleFit.minimumScale)
    #expect(LorvexCalendarCompactTitleFit.scale(title: "Roadmap", size: 11, width: 0) == 1)
  }

  @Test("A word too wide even at the floor puts the title on one line instead of splitting it")
  func overlongWordTakesOneLine() {
    // "Quarterly" is about 44pt in the 11pt face and 35pt at the floor.
    #expect(
      LorvexCalendarCompactTitleFit.splitsAWord(
        title: "Quarterly planning workshop", size: 11, width: 30))
    #expect(
      !LorvexCalendarCompactTitleFit.splitsAWord(
        title: "Quarterly planning workshop", size: 11, width: 60))
  }

  @Test("Short words, an unmeasured block, and Chinese text keep wrapping")
  func otherTitlesKeepWrapping() {
    #expect(!LorvexCalendarCompactTitleFit.splitsAWord(title: "1:1 with Sam", size: 11, width: 40))
    #expect(!LorvexCalendarCompactTitleFit.splitsAWord(title: "Quarterly", size: 11, width: 0))
    #expect(!LorvexCalendarCompactTitleFit.splitsAWord(title: "季度规划研讨会议安排", size: 11, width: 30))
    // A Latin word beside Chinese still counts.
    #expect(
      LorvexCalendarCompactTitleFit.splitsAWord(title: "Quarterly 规划", size: 11, width: 30))
  }

  @Test("A Thai title is cut into dictionary words, not at its characters")
  func thaiTitleBreaksBetweenWords() {
    let title = "การประชุมวางแผนรายไตรมาส"
    let words = LorvexCalendarCompactTitleFit.words(in: title).map(\.text)
    #expect(words.count > 1)
    #expect(words.joined() == title)
    #expect(words.allSatisfy { !$0.isEmpty })
    #expect(LorvexCalendarCompactTitleFit.words(in: title).allSatisfy { !$0.wrapsBetweenCharacters })
  }

  @Test("A Thai word wider than the block keeps the title on one line instead of splitting it")
  func thaiWordTooWideTakesOneLine() {
    let title = "การประชุมวางแผนรายไตรมาส"
    #expect(LorvexCalendarCompactTitleFit.splitsAWord(title: title, size: 11, width: 30))
    #expect(!LorvexCalendarCompactTitleFit.splitsAWord(title: title, size: 11, width: 120))
    #expect(!LorvexCalendarCompactTitleFit.splitsAWord(title: title, size: 11, width: 0))
    // The face shrinks for the longest word, within the floor.
    let scale = LorvexCalendarCompactTitleFit.scale(title: title, size: 11, width: 40)
    #expect(scale < 1)
    #expect(scale >= LorvexCalendarCompactTitleFit.minimumScale)
  }

  @Test("Words keep Latin runs whole and cut only the Thai run beside them")
  func mixedTitlesCutOnlyTheUnspacedRun() {
    let words = LorvexCalendarCompactTitleFit.words(in: "Zoom ประชุมทีม Roadmap").map(\.text)
    #expect(words.first == "Zoom")
    #expect(words.last == "Roadmap")
    #expect(words.count >= 4)
  }

  @Test("A lane that an overlap has split too narrow for a few letters draws no title")
  func narrowLaneDrawsNoTitle() {
    // A phone week's day holds about 40pt of text in one lane, 16pt when two
    // blocks overlap, and 8pt when three do.
    #expect(LorvexCalendarCompactTitleFit.isLegible(width: 40, size: 11))
    #expect(!LorvexCalendarCompactTitleFit.isLegible(width: 16, size: 11))
    #expect(!LorvexCalendarCompactTitleFit.isLegible(width: 8, size: 11))
  }

  @Test("A Mac week's three overlapping blocks keep their titles until the window is very narrow")
  func macWeekLanesStayLegible() {
    // About 43pt of text per lane in a 1440pt window, about 31pt in 1100pt,
    // and about 22pt when the window is squeezed toward its minimum.
    #expect(LorvexCalendarCompactTitleFit.isLegible(width: 43, size: 11))
    #expect(LorvexCalendarCompactTitleFit.isLegible(width: 31, size: 11))
    #expect(!LorvexCalendarCompactTitleFit.isLegible(width: 22, size: 11))
  }

  @Test("The legible width grows with the face and waits for the first measurement")
  func legibleWidthScalesWithTheFace() {
    #expect(LorvexCalendarCompactTitleFit.isLegible(width: 30, size: 11))
    #expect(!LorvexCalendarCompactTitleFit.isLegible(width: 30, size: 16))
    #expect(!LorvexCalendarCompactTitleFit.isLegible(width: 0, size: 11))
  }
}

import Testing

@testable import LorvexCore

/// The serif voice cuts a string into CJK runs and everything else, so macOS can
/// set the CJK runs in Songti while digits and Latin words stay in New York.
@Test
func serifRunsSplitChineseFromDigitsAndLatin() {
  #expect(
    LorvexSerifRuns.split("你完成了 1 项任务。") == [
      .init(text: "你完成了", isCJK: true),
      .init(text: " 1 ", isCJK: false),
      .init(text: "项任务。", isCJK: true),
    ])
  #expect(
    LorvexSerifRuns.split("You finished 3 tasks.") == [
      .init(text: "You finished 3 tasks.", isCJK: false)
    ])
  #expect(LorvexSerifRuns.split("").isEmpty)
}

@Test
func serifRunsLeaveSharedPunctuationWithLatin() {
  // Curly quotes are shared with Latin text; New York sets them either way.
  #expect(
    LorvexSerifRuns.split("“周报”已推迟，稍后再说？") == [
      .init(text: "“", isCJK: false),
      .init(text: "周报", isCJK: true),
      .init(text: "”", isCJK: false),
      .init(text: "已推迟，稍后再说？", isCJK: true),
    ])
}

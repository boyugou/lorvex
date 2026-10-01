import LorvexCore
import Testing

@testable import LorvexMobile

private func summary(
  completed: Int = 0, dueOpen: Int = 0, habits: (Int, Int) = (0, 0), events: Int = 0
) -> DayReviewSummary {
  DayReviewSummary(
    date: "2026-09-22", completedCount: completed, topCompleted: [], createdCount: 0,
    dueOpenCount: dueOpen, habitsCompleted: habits.0, habitsTotal: habits.1, eventCount: events)
}

@Test("A day with nothing in it is quiet")
func reviewSentenceQuietDay() {
  #expect(LorvexReviewSentence.parts(summary()) == [.quiet])
  #expect(LorvexReviewSentence.parts(summary(events: 1)) == [.nothingFinished])
}

@Test("The sentence names what finished, what is still due, and the habits")
func reviewSentenceParts() {
  #expect(
    LorvexReviewSentence.parts(summary(completed: 3, dueOpen: 1, habits: (2, 3)))
      == [.finished(3), .stillDue(1), .habitsSome(kept: 2, total: 3)])
  #expect(LorvexReviewSentence.parts(summary(completed: 1, habits: (2, 2))) == [.finished(1), .habitsAll])
  #expect(LorvexReviewSentence.parts(summary(completed: 1, habits: (0, 2))) == [.finished(1), .habitsNone])
}

@Test
func reviewSentenceWording() {
  #expect(
    MobileReviewCalmCopy.sentence([.finished(3), .stillDue(1), .habitsSome(kept: 2, total: 3)])
      == "You finished 3 tasks. 1 due task is still open. 2\u{00A0}of\u{00A0}3 habits kept.")
  #expect(MobileReviewCalmCopy.sentence([.finished(1)]) == "You finished 1 task.")
}

@Test("Sentences join with a space in English and without one after a full-width stop")
func reviewSentencesJoinTheirLanguagesWay() {
  #expect(
    LorvexReviewSentence.join(["You finished 3 tasks.", "1 due task is still open."])
      == "You finished 3 tasks. 1 due task is still open.")
  #expect(
    LorvexReviewSentence.join(["你完成了 3 项任务。", "还有 1 项到期任务没完成。", "完成了 3 个习惯中的 2 个。"])
      == "你完成了 3 项任务。还有 1 项到期任务没完成。完成了 3 个习惯中的 2 个。")
  #expect(LorvexReviewSentence.join(["", "A quiet day."]) == "A quiet day.")
}

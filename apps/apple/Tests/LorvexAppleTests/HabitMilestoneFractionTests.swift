import LorvexCore
import Testing

/// A milestone bar sits beside the next value alone, so it fills from zero:
/// an 8-day streak aiming at 14 days is 8/14 of the way, not the 1/7 it has
/// climbed since the 7-day rung.
@Test
func habitMilestoneFractionMeasuresTheReadingFromZero() {
  let eightOfFourteen = HabitMilestoneInfo(
    metric: "streak", value: 8, currentMilestone: 7, nextMilestone: 14,
    progressToNext: 1.0 / 7.0)
  #expect(eightOfFourteen.fractionOfNext == 8.0 / 14.0)

  let noRungYet = HabitMilestoneInfo(
    metric: "streak", value: 3, currentMilestone: nil, nextMilestone: 7, progressToNext: 3.0 / 7.0)
  #expect(noRungYet.fractionOfNext == 3.0 / 7.0)

  let countTowardTarget = HabitMilestoneInfo(
    metric: "count", value: 23, currentMilestone: 10, nextMilestone: 25,
    progressToNext: 13.0 / 15.0)
  #expect(countTowardTarget.fractionOfNext == 23.0 / 25.0)
}

@Test
func habitMilestoneFractionStaysInsideTheBar() {
  let degenerate = HabitMilestoneInfo(
    metric: "streak", value: 5, currentMilestone: nil, nextMilestone: 0, progressToNext: 1)
  #expect(degenerate.fractionOfNext == 1)

  let negative = HabitMilestoneInfo(
    metric: "count", value: -2, currentMilestone: nil, nextMilestone: 10, progressToNext: 0)
  #expect(negative.fractionOfNext == 0)

  let past = HabitMilestoneInfo(
    metric: "streak", value: 20, currentMilestone: 14, nextMilestone: 14, progressToNext: 1)
  #expect(past.fractionOfNext == 1)
}

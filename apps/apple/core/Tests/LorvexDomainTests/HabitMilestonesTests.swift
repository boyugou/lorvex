import XCTest

@testable import LorvexDomain

final class HabitMilestonesTests: XCTestCase {

  // MARK: metric selection by cadence

  func testMetricIsStreakForDailyAndWeekly() {
    XCTAssertEqual(habitMilestoneMetric(for: .daily), .streak)
    XCTAssertEqual(habitMilestoneMetric(for: .weekly(days: [.mon, .wed])), .streak)
    // Weekly-every-day (nil/empty day set) is still a streak cadence.
    XCTAssertEqual(habitMilestoneMetric(for: .weekly(days: nil)), .streak)
  }

  func testMetricIsCountForTimesPerWeekAndMonthly() {
    XCTAssertEqual(habitMilestoneMetric(for: .timesPerWeek(count: 3)), .count)
    XCTAssertEqual(habitMilestoneMetric(for: .monthly(dayOfMonth: 15)), .count)
  }

  // MARK: ladder shape

  func testStreakLadderPrefixThenAnnualTail() {
    let expected = [7, 14, 30, 66, 100, 180, 365, 730, 1095, 1460, 1825]
    for (index, rung) in expected.enumerated() {
      XCTAssertEqual(habitMilestoneRung(index: index, for: .streak), rung, "streak rung \(index)")
    }
  }

  func testCountLadderDecadePattern() {
    let expected = [10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000, 25000, 50000]
    for (index, rung) in expected.enumerated() {
      XCTAssertEqual(habitMilestoneRung(index: index, for: .count), rung, "count rung \(index)")
    }
  }

  func testLaddersAreStrictlyIncreasing() {
    for metric in [HabitMilestoneMetric.streak, .count] {
      var previous = habitMilestoneRung(index: 0, for: metric)
      for index in 1..<40 {
        let rung = habitMilestoneRung(index: index, for: metric)
        XCTAssertGreaterThan(rung, previous, "\(metric) rung \(index) must exceed its predecessor")
        previous = rung
      }
    }
  }

  // MARK: standing — no target (ladder only)

  func testStandingBelowFirstRungHasNoCurrentMilestone() {
    let s = habitMilestoneStanding(value: 3, target: nil, metric: .streak)
    XCTAssertNil(s.currentMilestone)
    XCTAssertEqual(s.nextMilestone, 7)
    XCTAssertEqual(s.progressToNext, 3.0 / 7.0, accuracy: 1e-9)
  }

  func testStandingMidLadderReadsAdjacentRungs() {
    let s = habitMilestoneStanding(value: 50, target: nil, metric: .streak)
    XCTAssertEqual(s.currentMilestone, 30)
    XCTAssertEqual(s.nextMilestone, 66)
    XCTAssertEqual(s.progressToNext, Double(50 - 30) / Double(66 - 30), accuracy: 1e-9)
  }

  func testStandingExactlyOnRungIsZeroProgressToNext() {
    let s = habitMilestoneStanding(value: 100, target: nil, metric: .count)
    XCTAssertEqual(s.currentMilestone, 100)
    XCTAssertEqual(s.nextMilestone, 250)
    XCTAssertEqual(s.progressToNext, 0.0, accuracy: 1e-9)
  }

  func testStandingInAnnualTailUsesYearRungs() {
    let s = habitMilestoneStanding(value: 800, target: nil, metric: .streak)
    XCTAssertEqual(s.currentMilestone, 730)
    XCTAssertEqual(s.nextMilestone, 1095)
  }

  func testNegativeValueClampsToZero() {
    let s = habitMilestoneStanding(value: -5, target: nil, metric: .streak)
    XCTAssertNil(s.currentMilestone)
    XCTAssertEqual(s.nextMilestone, 7)
    XCTAssertEqual(s.progressToNext, 0.0, accuracy: 1e-9)
  }

  // MARK: standing — target set

  func testTargetUnreachedBecomesNextMilestone() {
    let s = habitMilestoneStanding(value: 50, target: 100, metric: .streak)
    // Ladder rung already passed is still the current milestone; the aim is the
    // user target, not the next ladder rung.
    XCTAssertEqual(s.currentMilestone, 30)
    XCTAssertEqual(s.nextMilestone, 100)
    XCTAssertEqual(s.progressToNext, Double(50 - 30) / Double(100 - 30), accuracy: 1e-9)
  }

  func testTargetReachedFoldsIntoCurrentAndLaddersOnward() {
    let s = habitMilestoneStanding(value: 120, target: 100, metric: .count)
    // value >= target: target is reached; current is the highest reached
    // milestone (ladder rung 100 == target here) and next climbs the ladder.
    XCTAssertEqual(s.currentMilestone, 100)
    XCTAssertEqual(s.nextMilestone, 250)
    XCTAssertEqual(s.progressToNext, Double(120 - 100) / Double(250 - 100), accuracy: 1e-9)
  }

  func testTargetBelowFirstRungReachedIsCurrentMilestone() {
    // target 3 is below the first streak rung (7); once value meets it, current
    // is the target and next is the first ladder rung above the value.
    let s = habitMilestoneStanding(value: 5, target: 3, metric: .streak)
    XCTAssertEqual(s.currentMilestone, 3)
    XCTAssertEqual(s.nextMilestone, 7)
    XCTAssertEqual(s.progressToNext, Double(5 - 3) / Double(7 - 3), accuracy: 1e-9)
  }

  func testNonPositiveTargetIsIgnored() {
    let withZero = habitMilestoneStanding(value: 50, target: 0, metric: .streak)
    let withNil = habitMilestoneStanding(value: 50, target: nil, metric: .streak)
    XCTAssertEqual(withZero, withNil)
  }

  // MARK: crossing detection

  func testJustReachedCrossingLadderRung() {
    XCTAssertEqual(justReachedHabitMilestone(prev: 6, new: 7, target: nil, metric: .streak), 7)
    XCTAssertEqual(justReachedHabitMilestone(prev: 13, new: 14, target: nil, metric: .streak), 14)
  }

  func testJustReachedReturnsNilWhenNoRungCrossed() {
    XCTAssertNil(justReachedHabitMilestone(prev: 7, new: 13, target: nil, metric: .streak))
  }

  func testJustReachedReturnsNilForNonIncreasingMove() {
    XCTAssertNil(justReachedHabitMilestone(prev: 30, new: 30, target: nil, metric: .streak))
    XCTAssertNil(justReachedHabitMilestone(prev: 30, new: 20, target: nil, metric: .streak))
  }

  func testJustReachedPrefersHighestWhenMultipleCrossedInOneJump() {
    // A single big jump clears 10, 25, and 50 — the highest reached is returned.
    XCTAssertEqual(justReachedHabitMilestone(prev: 0, new: 60, target: nil, metric: .count), 50)
  }

  func testJustReachedConsidersUserTarget() {
    // Target 50 sits between the crossed ladder rung (30) and `new`; the target
    // is the higher milestone reached.
    XCTAssertEqual(justReachedHabitMilestone(prev: 20, new: 55, target: 50, metric: .streak), 50)
    // Target below the crossed ladder rung (30): the rung is the higher reached.
    XCTAssertEqual(justReachedHabitMilestone(prev: 20, new: 40, target: 25, metric: .streak), 30)
  }

  func testJustReachedTargetOnlyWhenBelowFirstRung() {
    // Crossing a sub-ladder target with no ladder rung in range still fires.
    XCTAssertEqual(justReachedHabitMilestone(prev: 2, new: 5, target: 4, metric: .streak), 4)
  }
}

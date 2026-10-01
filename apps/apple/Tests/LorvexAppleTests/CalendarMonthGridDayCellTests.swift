import Testing

@testable import LorvexApple

@MainActor
@Test
func calendarMonthGridDayCellFitsAsManyChipsAsTheRowHolds() {
  // A 154pt row (a 900pt window's five-week month) stacks six chips under the
  // day number; a 40pt row still shows one, which folds into "+N".
  #expect(CalendarMonthGridDayCell.chipsFitting(in: 154) == 6)
  #expect(CalendarMonthGridDayCell.chipsFitting(in: 40) == 1)
  #expect(CalendarMonthGridDayCell.chipsFitting(in: 0) == 1)
}

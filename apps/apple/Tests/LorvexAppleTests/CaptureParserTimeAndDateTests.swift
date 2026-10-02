import LorvexCore
import Testing

// 2026-09-22 is a Tuesday: weekday 3 in the Gregorian convention.
private func parse(_ text: String, today: String? = "2026-09-22") -> LorvexCaptureParse {
  LorvexCaptureParser.parse(text, lists: [], todayWeekday: 3, today: today)
}

/// Clock times and written-out dates in a capture line, and how a time turns
/// into the created task's planned day and time.
@Suite("Capture parser times and dates")
struct CaptureParserTimeAndDateTests {
  @Test("English clock times, with or without at")
  func englishTimes() {
    let line = parse("Call the caterer at 3pm")
    #expect(line.title == "Call the caterer")
    #expect(line.startMinutes == 15 * 60)
    #expect(line.phrases.map(\.kind) == [.time])

    #expect(parse("Standup 9:30 am").startMinutes == 9 * 60 + 30)
    #expect(parse("Standup 9:30am").title == "Standup")
    #expect(parse("Dinner 7 p.m.").startMinutes == 19 * 60)
    #expect(parse("Lunch at noon").startMinutes == 12 * 60)
    #expect(parse("Lunch at noon").title == "Lunch")
    #expect(parse("Pick up 12am delivery").startMinutes == 0)
    #expect(parse("Review @ 15:30").startMinutes == 15 * 60 + 30)
  }

  @Test("A bare 1 to 6 o'clock is the afternoon; a leading zero keeps the morning")
  func bareTimes() {
    #expect(parse("Sync 3:30").startMinutes == 15 * 60 + 30)
    #expect(parse("Run 06:30").startMinutes == 6 * 60 + 30)
    #expect(parse("Gym 7:00").startMinutes == 7 * 60)
    #expect(parse("Call 18:45").startMinutes == 18 * 60 + 45)
  }

  @Test("Words that only look like times stay in the title")
  func notTimes() {
    #expect(parse("Chat about the 3 amazing ideas").startMinutes == nil)
    #expect(parse("Read 25 pages").startMinutes == nil)
    #expect(parse("Chat 3pm").title == "Chat")
    #expect(parse("快一点完成").startMinutes == nil)
    #expect(parse("第三点要改").startMinutes == nil)
  }

  @Test("Chinese clock times and parts of the day")
  func chineseTimes() {
    let line = parse("下午3点开会")
    #expect(line.title == "开会")
    #expect(line.startMinutes == 15 * 60)

    #expect(parse("晚上8点半看电影").startMinutes == 20 * 60 + 30)
    #expect(parse("上午10点面试").startMinutes == 10 * 60)
    #expect(parse("三点一刻打电话").startMinutes == 15 * 60 + 15)
    #expect(parse("9点20分出发").startMinutes == 9 * 60 + 20)
    #expect(parse("两点开会").startMinutes == 14 * 60)
    #expect(parse("中午12点吃饭").startMinutes == 12 * 60)
    #expect(parse("凌晨5点赶飞机").startMinutes == 5 * 60)
    #expect(parse("下午3:30开会").startMinutes == 15 * 60 + 30)
    #expect(parse("下午3:30开会").title == "开会")
    #expect(parse("3点钟碰头").title == "碰头")
  }

  @Test("Tonight's bare time is the evening")
  func eveningDays() {
    let line = parse("tonight 8:00 call mom")
    #expect(line.plannedDayOffset == 0)
    #expect(line.startMinutes == 20 * 60)
    #expect(parse("今晚8点开会").startMinutes == 20 * 60)
    #expect(parse("明晚9点看球").startMinutes == 21 * 60)
    #expect(parse("明晚9点看球").plannedDayOffset == 1)
    #expect(parse("tonight 8am flight check").startMinutes == 8 * 60)
  }

  @Test("The night runs past midnight: 12 o'clock and the small hours are the next day")
  func nightTimes() {
    let line = parse("晚上12点睡觉")
    #expect(line.title == "睡觉")
    #expect(line.startMinutes == 0)
    #expect(line.plannedDayOffset == 1)
    #expect(line.plannedTime == 0..<30)

    #expect(parse("今晚12点上线").plannedDayOffset == 1)
    #expect(parse("今晚12点上线").startMinutes == 0)
    #expect(parse("今晚0点上线").plannedDayOffset == 1)
    #expect(parse("明晚12点上线").plannedDayOffset == 2)
    #expect(parse("明天晚上12点上线").plannedDayOffset == 2)
    // Friday night's midnight opens Saturday.
    #expect(parse("周五晚上12点交").plannedDayOffset == 4)
    #expect(parse("晚上12点半吃宵夜").startMinutes == 30)
    #expect(parse("半夜12点抢票").plannedDayOffset == 1)
    #expect(parse("午夜12点发布").startMinutes == 0)
    #expect(parse("晚上1点改稿").startMinutes == 60)
    #expect(parse("晚上1点改稿").plannedDayOffset == 1)
    #expect(parse("今晚1点改稿").startMinutes == 60)
    #expect(parse("今晚1点改稿").plannedDayOffset == 1)
    #expect(parse("半夜3点看流星").startMinutes == 3 * 60)
    #expect(parse("半夜3点看流星").plannedDayOffset == 1)
    // The evening itself stays on the day.
    #expect(parse("晚上11点睡觉").startMinutes == 23 * 60)
    #expect(parse("晚上11点睡觉").plannedDayOffset == nil)
    #expect(parse("中午12点吃饭").plannedDayOffset == nil)
  }

  @Test("At midnight ends the day it is named with; an explicit AM stays as written")
  func englishMidnight() {
    let line = parse("Submit the report at midnight")
    #expect(line.title == "Submit the report")
    #expect(line.startMinutes == 0)
    #expect(line.plannedDayOffset == 1)
    #expect(line.phrases.map(\.kind) == [.time])

    #expect(parse("Deploy tomorrow at midnight").plannedDayOffset == 2)
    #expect(parse("tonight 12:00 launch").startMinutes == 0)
    #expect(parse("tonight 12:00 launch").plannedDayOffset == 1)
    // "Midnight" without "at" is as often a name.
    #expect(parse("Midnight snack").startMinutes == nil)
    #expect(parse("Midnight snack").title == "Midnight snack")
    #expect(parse("Pick up 12am delivery").plannedDayOffset == nil)
  }

  @Test("A time alone plans today, for the parsed length or half an hour")
  func plannedTime() {
    let line = parse("Dentist 4pm")
    #expect(line.plannedDayOffset == nil)
    #expect(line.resolvedPlannedDayOffset == 0)
    #expect(line.plannedTime == 16 * 60..<(16 * 60 + 30))

    let long = parse("Workshop tomorrow 10am 2h")
    #expect(long.resolvedPlannedDayOffset == 1)
    #expect(long.plannedTime == 10 * 60..<(12 * 60))

    #expect(parse("Late call 11:45pm 1h").plannedTime == (23 * 60)..<(24 * 60))
    #expect(parse("No time here tomorrow").plannedTime == nil)
    #expect(parse("Plain title").resolvedPlannedDayOffset == nil)
  }

  @Test("English dates written out, rolling to next year once passed")
  func englishDates() {
    let line = parse("Renew passport Oct 5")
    #expect(line.title == "Renew passport")
    #expect(line.plannedDayOffset == 13)

    #expect(parse("Party on October 5th").plannedDayOffset == 13)
    #expect(parse("Party 5 Oct").plannedDayOffset == 13)
    #expect(parse("Party 5th of October").plannedDayOffset == 13)
    #expect(parse("Taxes due Sept 30").dueDayOffset == 8)
    #expect(parse("Taxes by Sep 30").dueDayOffset == 8)
    #expect(parse("Retro Sep 22").plannedDayOffset == 0)
    // Passed this year: next year's.
    #expect(parse("Anniversary Sep 1").plannedDayOffset == 344)
    #expect(parse("Launch 2026-10-01").plannedDayOffset == 9)
    #expect(parse("Launch October 1, 2027").plannedDayOffset == 374)
    // A written year in the past and a day the month lacks stay in the title.
    #expect(parse("Notes from Oct 1, 2020").plannedDayOffset == nil)
    #expect(parse("Feb 30 party").plannedDayOffset == nil)
    #expect(parse("Feb 30 party").title == "Feb 30 party")
  }

  @Test("Chinese dates written out")
  func chineseDates() {
    let line = parse("10月5日交房租")
    #expect(line.title == "交房租")
    #expect(line.plannedDayOffset == 13)

    #expect(parse("10月5号体检").plannedDayOffset == 13)
    #expect(parse("2027年1月3日续签").plannedDayOffset == 103)
    #expect(parse("30号前交报告").dueDayOffset == 8)
    // The 5th has passed this month: next month's.
    #expect(parse("5号还信用卡").plannedDayOffset == 13)
    #expect(parse("10月5日前交房租").dueDayOffset == 13)
    #expect(parse("10月5日下午3点开会").startMinutes == 15 * 60)
    #expect(parse("10月5日下午3点开会").title == "开会")
  }

  @Test("Written-out dates need the logical today")
  func datesNeedToday() {
    let line = parse("Renew passport Oct 5", today: nil)
    #expect(line.plannedDayOffset == nil)
    #expect(line.title == "Renew passport Oct 5")
  }
}

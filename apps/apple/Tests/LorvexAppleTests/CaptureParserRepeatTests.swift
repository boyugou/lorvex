import LorvexCore
import Testing

// 2026-09-22 is a Tuesday: weekday 3 in the Gregorian convention.
private func parse(_ text: String) -> LorvexCaptureParse {
  LorvexCaptureParser.parse(text, lists: [], todayWeekday: 3, today: "2026-09-22")
}

/// Repeat phrases in a capture line, and the first occurrence a repeating
/// task is created on.
@Suite("Capture parser repeats")
struct CaptureParserRepeatTests {
  @Test("English cadences and intervals")
  func englishCadences() {
    let line = parse("Water the plants every day")
    #expect(line.title == "Water the plants")
    #expect(line.recurrence == TaskRecurrenceRule(freq: .daily))
    #expect(line.phrases.map(\.kind) == [.repeats])

    #expect(parse("Backup every week").recurrence == TaskRecurrenceRule(freq: .weekly))
    #expect(parse("Payroll every other week").recurrence == TaskRecurrenceRule(freq: .weekly, interval: 2))
    #expect(parse("Stretch every 3 days").recurrence == TaskRecurrenceRule(freq: .daily, interval: 3))
    #expect(parse("Rent every month").recurrence == TaskRecurrenceRule(freq: .monthly))
    #expect(parse("Renew domain every year").recurrence == TaskRecurrenceRule(freq: .yearly))
    #expect(parse("Water the plants daily").recurrence == TaskRecurrenceRule(freq: .daily))
    #expect(parse("Water the plants daily").title == "Water the plants")
  }

  @Test("A cadence adverb opening a title stays in it")
  func adverbTitles() {
    let line = parse("Weekly review")
    #expect(line.recurrence == nil)
    #expect(line.title == "Weekly review")
    #expect(parse("Daily standup notes").recurrence == nil)
    #expect(parse("Read everyday things").recurrence == nil)
  }

  @Test("English weekdays start on the next one, today included")
  func englishWeekdays() {
    let line = parse("Standup every Mon and Thu")
    #expect(line.title == "Standup")
    #expect(line.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "TH"]))
    #expect(line.recurrenceStartOffset == 2)
    #expect(line.resolvedDueDayOffset == 2)
    #expect(line.plannedDayOffset == nil)

    let weekdays = parse("Check email every weekday")
    #expect(weekdays.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "TU", "WE", "TH", "FR"]))
    #expect(weekdays.resolvedDueDayOffset == 0)

    let other = parse("Team lunch every other friday")
    #expect(other.recurrence == TaskRecurrenceRule(freq: .weekly, interval: 2, byDay: ["FR"]))
    #expect(other.resolvedDueDayOffset == 3)
    #expect(parse("Yoga every tuesday").resolvedDueDayOffset == 0)
  }

  @Test("Chinese cadences, intervals, and weekdays")
  func chineseCadences() {
    let line = parse("每天浇花")
    #expect(line.title == "浇花")
    #expect(line.recurrence == TaskRecurrenceRule(freq: .daily))

    #expect(parse("每隔一天跑步").recurrence == TaskRecurrenceRule(freq: .daily, interval: 2))
    #expect(parse("每3天换水").recurrence == TaskRecurrenceRule(freq: .daily, interval: 3))
    #expect(parse("每周复盘").recurrence == TaskRecurrenceRule(freq: .weekly))
    #expect(parse("每两周发工资").recurrence == TaskRecurrenceRule(freq: .weekly, interval: 2))
    #expect(parse("每年体检").recurrence == TaskRecurrenceRule(freq: .yearly))
    #expect(parse("每个月交房租").recurrence == TaskRecurrenceRule(freq: .monthly))

    let weekdays = parse("每周一三五健身")
    #expect(weekdays.title == "健身")
    #expect(weekdays.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "WE", "FR"]))
    #expect(weekdays.resolvedDueDayOffset == 1)
    #expect(weekdays.plannedDayOffset == nil)

    let sunday = parse("每周日大扫除")
    #expect(sunday.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["SU"]))
    #expect(sunday.resolvedDueDayOffset == 5)

    let workdays = parse("每个工作日写日报")
    #expect(workdays.title == "写日报")
    #expect(workdays.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "TU", "WE", "TH", "FR"]))
  }

  @Test("A monthly day starts on the coming one")
  func monthlyDay() {
    let line = parse("每月5号还信用卡")
    #expect(line.title == "还信用卡")
    #expect(line.recurrence == TaskRecurrenceRule(freq: .monthly, byMonthDay: [5]))
    #expect(line.resolvedDueDayOffset == 13)
    #expect(line.plannedDayOffset == nil)
  }

  @Test("A repeating task's due day: the named due day, else the planned day, else today")
  func dueDays() {
    #expect(parse("Water the plants every day").resolvedDueDayOffset == 0)
    #expect(parse("Report every week by friday").resolvedDueDayOffset == 3)
    #expect(parse("Report every week tomorrow").resolvedDueDayOffset == 1)
    #expect(parse("No repeat by friday").resolvedDueDayOffset == 3)
    #expect(parse("Plain title").resolvedDueDayOffset == nil)
  }

  @Test("A repeating time is planned on the first occurrence")
  func repeatingTime() {
    let line = parse("Standup every monday 9:30am")
    #expect(line.startMinutes == 9 * 60 + 30)
    #expect(line.resolvedPlannedDayOffset == 6)
    #expect(line.resolvedDueDayOffset == 6)
    #expect(parse("每天早上8点吃药").resolvedPlannedDayOffset == 0)
  }

  @Test("A repeat at midnight moves the days it names along with the time")
  func midnightRepeats() {
    let weekly = parse("每周五晚上12点倒垃圾")
    #expect(weekly.title == "倒垃圾")
    #expect(weekly.startMinutes == 0)
    #expect(weekly.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["SA"]))
    #expect(weekly.recurrenceStartOffset == 4)
    #expect(weekly.resolvedPlannedDayOffset == 4)

    let daily = parse("每天晚上12点备份")
    #expect(daily.recurrence == TaskRecurrenceRule(freq: .daily))
    #expect(daily.resolvedPlannedDayOffset == 1)
    #expect(daily.resolvedDueDayOffset == 1)

    #expect(
      parse("每月5号晚上12点对账").recurrence == TaskRecurrenceRule(freq: .monthly, byMonthDay: [6]))
    #expect(
      parse("每月31号晚上12点结账").recurrence == TaskRecurrenceRule(freq: .monthly, byMonthDay: [1]))
  }
}

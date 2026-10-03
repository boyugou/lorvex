import LorvexCore
import Testing

// 2026-09-22 is a Tuesday: weekday 3 in the Gregorian convention.
private func parse(_ text: String, todayWeekday: Int = 3) -> LorvexCaptureParse {
  LorvexCaptureParser.parse(text, lists: [], todayWeekday: todayWeekday, languages: ["en"])
}

/// The capture vocabulary beyond the basics: Chinese written without spaces,
/// the guards that keep ordinary English words in the title, and the longer
/// day, length, and priority phrases.
@Suite("Capture parser vocabulary")
struct CaptureParserVocabularyTests {
  @Test("Chinese days, lengths, and priority need no spaces around them")
  func chineseWithoutSpaces() {
    let line = parse("明天开会30分钟")
    #expect(line.title == "开会")
    #expect(line.plannedDayOffset == 1)
    #expect(line.estimatedMinutes == 30)

    #expect(parse("后天交报告").plannedDayOffset == 2)
    #expect(parse("大后天交报告").plannedDayOffset == 3)
    #expect(parse("大后天交报告").title == "交报告")
    #expect(parse("紧急修复登录").priority == .p1)
    #expect(parse("紧急修复登录").title == "修复登录")
    #expect(parse("这件事不紧急").priority == nil)
    #expect(parse("整理报销半小时").estimatedMinutes == 30)
    #expect(parse("写周报一个半小时").estimatedMinutes == 90)
    #expect(parse("复盘2个小时").estimatedMinutes == 120)
  }

  @Test("Chinese weekdays: the next one, this week's, and next week's")
  func chineseWeekdays() {
    // Today is Tuesday.
    #expect(parse("周三开会").plannedDayOffset == 1)
    #expect(parse("星期五交周报").plannedDayOffset == 3)
    #expect(parse("礼拜天去爬山").plannedDayOffset == 5)
    #expect(parse("周二例会").plannedDayOffset == 7)
    #expect(parse("这周二例会").plannedDayOffset == 0)
    #expect(parse("下周三开会").plannedDayOffset == 8)
    #expect(parse("下周一交方案").plannedDayOffset == 6)
    #expect(parse("下周整理书架").plannedDayOffset == 7)
    #expect(parse("周末大扫除").plannedDayOffset == 4)
    #expect(parse("3天后复查").plannedDayOffset == 3)
    #expect(parse("每周一次复盘").plannedDayOffset == nil)
    // The first day named counts; a later one stays in the title.
    #expect(parse("明天准备周五的汇报").plannedDayOffset == 1)
    #expect(parse("明天准备周五的汇报").title == "准备周五的汇报")
  }

  @Test("Traditional Chinese reads like Simplified, and the line keeps its characters")
  func traditionalChinese() {
    let line = parse("後天下午三點開會兩個鐘頭")
    #expect(line.title == "開會")
    #expect(line.plannedDayOffset == 2)
    #expect(line.startMinutes == 15 * 60)
    #expect(line.estimatedMinutes == 120)
    #expect(line.phrases.map(\.text) == ["後天", "下午三點", "兩個鐘頭"])

    // Today is Tuesday.
    #expect(parse("大後天交報告").plannedDayOffset == 3)
    #expect(parse("下週三開會").plannedDayOffset == 8)
    #expect(parse("這週二例會").plannedDayOffset == 0)
    #expect(parse("禮拜天去爬山").plannedDayOffset == 5)
    #expect(parse("週末大掃除").plannedDayOffset == 4)
    let later = parse("3天後複查")
    #expect(later.plannedDayOffset == 3)
    #expect(later.title == "複查")
    #expect(parse("緊急修復登入").priority == .p1)
    #expect(parse("整理報銷30分鐘").estimatedMinutes == 30)
    let report = parse("寫週報一個半小時")
    #expect(report.estimatedMinutes == 90)
    #expect(report.title == "寫週報")

    let due = parse("週五前提交報銷")
    #expect(due.dueDayOffset == 3)
    #expect(due.title == "提交報銷")

    #expect(parse("每週一三五晨跑").recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "WE", "FR"]))
    #expect(
      parse("每個工作日站會").recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "TU", "WE", "TH", "FR"]))
    #expect(parse("每兩週回顧").recurrence == TaskRecurrenceRule(freq: .weekly, interval: 2))

    // A tag is the word as typed.
    let tagged = parse("#時間管理 明天整理")
    #expect(tagged.tags == ["時間管理"])
    #expect(tagged.plannedDayOffset == 1)
    #expect(tagged.title == "整理")
  }

  @Test("钟头 counts hours in either script")
  func zhongtouLengths() {
    #expect(parse("复盘2个钟头").estimatedMinutes == 120)
    #expect(parse("复盘两个钟头").estimatedMinutes == 120)
    #expect(parse("复盘一个半钟头").estimatedMinutes == 90)
    #expect(parse("散步半个钟头").estimatedMinutes == 30)
    #expect(parse("散步半个钟头").title == "散步")
    #expect(parse("複盤一個鐘頭").estimatedMinutes == 60)
  }

  @Test("A Chinese day before 前 is the due day")
  func chineseDue() {
    let line = parse("周五前提交报销")
    #expect(line.dueDayOffset == 3)
    #expect(line.plannedDayOffset == nil)
    #expect(line.title == "提交报销")
  }

  @Test("English words that only look like details stay in the title")
  func englishGuards() {
    let sat = parse("Fix the chair I sat on")
    #expect(sat.title == "Fix the chair I sat on")
    #expect(sat.plannedDayOffset == nil)
    #expect(parse("Buy sun cream").plannedDayOffset == nil)
    #expect(parse("Book urgent care visit").priority == nil)
    #expect(parse("Book urgent care visit").title == "Book urgent care visit")
    let standup = parse("Prep today's standup")
    #expect(standup.title == "Prep today's standup")
    #expect(standup.plannedDayOffset == nil)
    #expect(parse("Standup notes on Sat").plannedDayOffset == 4)
    #expect(parse("Standup notes Sat").plannedDayOffset == 4)
  }

  @Test("A capitalized weekday ending the words still counts when details follow it")
  func capitalizedWeekdayBeforeDetails() {
    let line = parse("Call the bank Friday 20m #errands")
    #expect(line.plannedDayOffset == 3)
    #expect(line.estimatedMinutes == 20)
    #expect(line.title == "Call the bank")
  }

  @Test("This and next weekdays, weekends, and in N days")
  func englishDayPhrases() {
    #expect(parse("Review this Tuesday").plannedDayOffset == 0)
    #expect(parse("Review this friday").plannedDayOffset == 3)
    #expect(parse("Clean the garage this weekend").plannedDayOffset == 4)
    #expect(parse("Clean the garage this weekend").title == "Clean the garage")
    #expect(parse("Clean the garage weekend", todayWeekday: 1).plannedDayOffset == 0)
    #expect(parse("Follow up in 3 days").plannedDayOffset == 3)
    #expect(parse("Follow up in 3 days").title == "Follow up")
  }

  @Test("Lengths in hours and minutes together, and half an hour")
  func englishLengths() {
    #expect(parse("Write the brief 1h30m").estimatedMinutes == 90)
    #expect(parse("Write the brief 1h 30min").estimatedMinutes == 90)
    #expect(parse("Stretch for half an hour").estimatedMinutes == 30)
    #expect(parse("Stretch for half an hour").title == "Stretch")
  }

  @Test("Priority codes and an opening urgent")
  func englishPriority() {
    #expect(parse("Fix the crash p1").priority == .p1)
    #expect(parse("Fix the crash P2").priority == .p2)
    #expect(parse("Tidy the docs p3").priority == .p3)
    #expect(parse("Tidy the docs p3").title == "Tidy the docs")
    let opening = parse("Urgent: renew the domain")
    #expect(opening.priority == .p1)
    #expect(opening.title == "renew the domain")
    #expect(parse("Buy an MP3 player").priority == nil)
  }
}

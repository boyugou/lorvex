import LorvexCore
import Testing

// 2026-09-22 is a Tuesday: weekday 3 in the Gregorian convention.
private func parse(_ text: String, languages: [String] = ["ko-KR"]) -> LorvexCaptureParse {
  LorvexCaptureParser.parse(text, lists: [], todayWeekday: 3, today: "2026-09-22", languages: languages)
}

/// Korean capture lines, read for a user whose languages include Korean.
@Suite("Capture parser Korean")
struct CaptureParserKoreanTests {
  @Test("A day stands as its own word and takes its particle with it")
  func days() {
    let line = parse("내일 치과 예약")
    #expect(line.plannedDayOffset == 1)
    #expect(line.title == "치과 예약")
    #expect(line.phrases.map(\.text) == ["내일"])

    #expect(parse("오늘은 장보기").plannedDayOffset == 0)
    #expect(parse("오늘은 장보기").title == "장보기")
    #expect(parse("모레 이사").plannedDayOffset == 2)
    #expect(parse("내일모레 출발").plannedDayOffset == 2)
    #expect(parse("글피 여행").plannedDayOffset == 3)
    #expect(parse("다음 주에 출장").plannedDayOffset == 7)
    #expect(parse("다음 주에 출장").title == "출장")
    #expect(parse("주말에 대청소").plannedDayOffset == 4)
    #expect(parse("다음 주말 캠핑").plannedDayOffset == 11)
    #expect(parse("3일 후 재검사").plannedDayOffset == 3)
    #expect(parse("3일 후 재검사").title == "재검사")
    #expect(parse("10월 5일 제출").plannedDayOffset == 13)

    // 오늘날 ("nowadays") is one word.
    let nowadays = parse("오늘날의 트렌드 정리")
    #expect(nowadays.plannedDayOffset == nil)
    #expect(nowadays.title == "오늘날의 트렌드 정리")
  }

  @Test("Weekdays: the next one, this week's, and next week's")
  func weekdays() {
    let friday = parse("금요일에 회의")
    #expect(friday.plannedDayOffset == 3)
    #expect(friday.title == "회의")
    // Today is Tuesday, so Tuesday alone is a week ahead.
    #expect(parse("화요일 정기 회의").plannedDayOffset == 7)
    #expect(parse("이번 주 금요일 발표").plannedDayOffset == 3)
    #expect(parse("이번 주 금요일 발표").title == "발표")
    #expect(parse("다음 주 수요일 면접").plannedDayOffset == 8)
    #expect(parse("다음 주 월요일 면접").plannedDayOffset == 6)
    #expect(parse("다다음 주 금요일 발표").plannedDayOffset == 17)
    #expect(parse("금요일엔 회의").plannedDayOffset == 3)
    #expect(parse("금요일엔 회의").title == "회의")
    #expect(parse("내일도 운동").plannedDayOffset == 1)
    #expect(parse("내일도 운동").title == "운동")
  }

  @Test("Date ranges: the first day is planned and the last is due")
  func dateRanges() {
    expectDateRanges(
      [
        ("출장", "5월 3일부터 5일까지", "2027-05-03", "2027-05-05"),
        ("출장", "5월 3일부터 5월 5일까지", "2027-05-03", "2027-05-05"),
        ("출장", "5월 3일~5일", "2027-05-03", "2027-05-05"),
        ("출장", "5월 3일 ~ 5일", "2027-05-03", "2027-05-05"),
        ("출장", "5월 3일~5월 5일", "2027-05-03", "2027-05-05"),
        ("출장", "5월 3일-5일", "2027-05-03", "2027-05-05"),
        ("출장", "5월 3일부터 5일", "2027-05-03", "2027-05-05"),
        ("출장", "5월 3일 부터 5일 까지", "2027-05-03", "2027-05-05"),
        ("출장", "5/3~5/5", "2027-05-03", "2027-05-05"),
        ("출장", "５월 ３일부터 ５일까지", "2027-05-03", "2027-05-05"),
        ("출장", "5월 3일부터 5일까지에", "2027-05-03", "2027-05-05"),
        ("출장", "5월 30일부터 6월 2일까지", "2027-05-30", "2027-06-02"),
        ("출장", "12월 30일부터 1월 2일까지", "2026-12-30", "2027-01-02"),
        ("출장", "10월 3일부터 5일까지", "2026-10-03", "2026-10-05"),
      ], languages: ["ko-KR"])

    // The range may open the line, and its particle leaves with it.
    let leading = parse("5월 3일부터 5일까지 출장")
    #expect(leading.title == "출장")
    #expect(leading.phrases.map(\.text) == ["5월 3일부터 5일까지"])
    let particle = parse("출장 5월 3일부터 5일까지에 제출")
    #expect(particle.title == "출장 제출")
    #expect(particle.dueDayOffset == captureDayOffset("2027-05-05"))
  }

  @Test("A range whose end is not after its start stays in the title whole")
  func declinedDateRanges() {
    expectLinesUnread(
      ["출장 5월 5일부터 3일까지", "출장 5월 5일부터 5월 3일까지", "출장 5월 3일부터 5월 3일까지"],
      languages: ["ko-KR"])
  }

  @Test("Weekday and time ranges, counts of days, and days with no month are not date ranges")
  func nonDateRanges() {
    // A weekday range is a planned weekday and a due weekday.
    let weekdays = parse("회의 월요일부터 금요일까지")
    #expect(weekdays.phrases.map(\.kind) == [.when, .due])

    let time = parse("회의 3시부터 5시까지")
    #expect(time.startMinutes == 15 * 60)
    #expect(time.estimatedMinutes == 120)
    #expect(time.dueDayOffset == nil)

    // 5일 후 counts days from today, so "5일 후부터 7일 후까지" is two such days.
    let relative = parse("여행 5일 후부터 7일 후까지")
    #expect(relative.plannedDayOffset == 5)
    #expect(relative.dueDayOffset == 7)

    // 5일간 counts days, so it is no end: only the first date is read.
    let span = parse("여행 5월 3일부터 5일간")
    #expect(span.plannedDayOffset == captureDayOffset("2027-05-03"))
    #expect(span.dueDayOffset == nil)
    #expect(span.title == "여행 5일간")

    // A lone day of the month is not a date here.
    expectLinesUnread(["여행 3일부터 5일까지"], languages: ["ko-KR"])
  }

  @Test("Clock times, with a part of the day or without")
  func times() {
    let line = parse("오후 3시 회의")
    #expect(line.startMinutes == 15 * 60)
    #expect(line.title == "회의")
    #expect(parse("3시 반에 전화").startMinutes == 15 * 60 + 30)
    #expect(parse("3시 반에 전화").title == "전화")
    #expect(parse("3시쯤 전화").startMinutes == 15 * 60)
    #expect(parse("오전 10시 회의").startMinutes == 10 * 60)
    #expect(parse("저녁 7시 운동").startMinutes == 19 * 60)
    #expect(parse("새벽 5시 기상").startMinutes == 5 * 60)
    #expect(parse("오후 세 시 미팅").startMinutes == 15 * 60)
    #expect(parse("오후 세 시 미팅").title == "미팅")
    #expect(parse("오후 3:30 치과").startMinutes == 15 * 60 + 30)
    #expect(parse("오후 3:30 치과").title == "치과")
    #expect(parse("정오에 점심").startMinutes == 12 * 60)
    #expect(parse("정오에 점심").title == "점심")

    // The minutes of a clock time are not a length.
    let minutes = parse("9시 20분 집합")
    #expect(minutes.startMinutes == 9 * 60 + 20)
    #expect(minutes.estimatedMinutes == nil)
    #expect(minutes.title == "집합")

    // An hour in digits may touch the day before it.
    let attached = parse("내일3시 회의")
    #expect(attached.plannedDayOffset == 1)
    #expect(attached.startMinutes == 15 * 60)
    #expect(attached.title == "회의")
  }

  @Test("The night runs past midnight, and 오늘 밤 is an evening")
  func nights() {
    let midnight = parse("밤 12시 취침")
    #expect(midnight.startMinutes == 0)
    #expect(midnight.plannedDayOffset == 1)
    #expect(parse("자정에 백업").plannedDayOffset == 1)
    let tonight = parse("오늘 밤 8시 통화")
    #expect(tonight.startMinutes == 20 * 60)
    #expect(tonight.plannedDayOffset == 0)
    #expect(tonight.title == "통화")
    #expect(parse("오늘밤 8시 통화").startMinutes == 20 * 60)
  }

  @Test("Lengths")
  func lengths() {
    #expect(parse("보고서 작성 30분").estimatedMinutes == 30)
    #expect(parse("보고서 작성 30분").title == "보고서 작성")
    #expect(parse("공부 2시간").estimatedMinutes == 120)
    #expect(parse("1시간 반 조깅").estimatedMinutes == 90)
    #expect(parse("1시간 30분 회의").estimatedMinutes == 90)
    #expect(parse("한 시간 독서").estimatedMinutes == 60)
    #expect(parse("반 시간 산책").estimatedMinutes == 30)
    #expect(parse("30분 동안 명상").estimatedMinutes == 30)
    #expect(parse("30분 동안 명상").title == "명상")
    #expect(parse("회의30분").estimatedMinutes == 30)
    #expect(parse("회의30분").title == "회의")
  }

  @Test("A day, a time, and a length in one line")
  func everything() {
    let line = parse("내일 오후 3시 1시간 회의")
    #expect(line.plannedDayOffset == 1)
    #expect(line.startMinutes == 15 * 60)
    #expect(line.estimatedMinutes == 60)
    #expect(line.title == "회의")
    #expect(line.phrases.map(\.text) == ["내일", "오후 3시", "1시간"])
  }

  @Test("Repeats")
  func repeats() {
    let line = parse("매일 일기")
    #expect(line.recurrence == TaskRecurrenceRule(freq: .daily))
    #expect(line.title == "일기")
    #expect(parse("매주 월요일 분리수거").recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["MO"]))
    #expect(parse("매주 월, 수, 금 헬스").recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "WE", "FR"]))
    #expect(parse("매주 월수금 수영").recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "WE", "FR"]))
    #expect(parse("매주 월수금 수영").title == "수영")
    #expect(parse("월요일마다 회의").recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["MO"]))
    #expect(parse("격주 수요일 회의").recurrence == TaskRecurrenceRule(freq: .weekly, interval: 2, byDay: ["WE"]))
    #expect(parse("매달 5일 월세").recurrence == TaskRecurrenceRule(freq: .monthly, byMonthDay: [5]))
    #expect(parse("매년 건강검진").recurrence == TaskRecurrenceRule(freq: .yearly))
    #expect(parse("격일 운동").recurrence == TaskRecurrenceRule(freq: .daily, interval: 2))
    #expect(parse("3일마다 물 주기").recurrence == TaskRecurrenceRule(freq: .daily, interval: 3))
    #expect(parse("2주마다 회고").recurrence == TaskRecurrenceRule(freq: .weekly, interval: 2))
    #expect(parse("2주마다 회고").title == "회고")
    #expect(parse("3개월마다 점검").recurrence == TaskRecurrenceRule(freq: .monthly, interval: 3))
    #expect(parse("3달마다 점검").title == "점검")
    #expect(parse("주마다 정리").recurrence == TaskRecurrenceRule(freq: .weekly))
    #expect(
      parse("평일마다 조회").recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "TU", "WE", "TH", "FR"]))

    // A repeat starts on the first day it names: today is Tuesday.
    #expect(parse("매주 금요일 회고").recurrenceStartOffset == 3)
    // 일 opening the next word is not Sunday.
    let work = parse("매주 일하기")
    #expect(work.recurrence == TaskRecurrenceRule(freq: .weekly))
    #expect(work.title == "일하기")
  }

  @Test("Due days and priority")
  func dueAndPriority() {
    let line = parse("금요일까지 보고서")
    #expect(line.dueDayOffset == 3)
    #expect(line.plannedDayOffset == nil)
    #expect(line.title == "보고서")
    #expect(parse("내일까지 제출").dueDayOffset == 1)
    #expect(parse("10월 5일 마감 원고").dueDayOffset == 13)
    #expect(parse("10월 5일 마감 원고").title == "원고")

    #expect(parse("긴급 서버 점검").priority == .p1)
    #expect(parse("긴급 서버 점검").title == "서버 점검")
    // 긴급회의 ("emergency meeting") is one word.
    #expect(parse("긴급회의 준비").priority == nil)
    #expect(parse("긴급회의 준비").title == "긴급회의 준비")
  }

  @Test("Korean words are read only for a user who reads Korean")
  func languageGate() {
    let line = parse("내일 치과", languages: ["en-US"])
    #expect(line.plannedDayOffset == nil)
    #expect(line.title == "내일 치과")
    #expect(parse("내일 치과", languages: ["ko"]).plannedDayOffset == 1)
  }
}

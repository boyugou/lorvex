import LorvexCore
import Testing

// 2026-09-22 is a Tuesday: weekday 3 in the Gregorian convention.
private func parse(_ text: String, languages: [String] = ["en"]) -> LorvexCaptureParse {
  LorvexCaptureParser.parse(text, lists: [], todayWeekday: 3, today: "2026-09-22", languages: languages)
}

/// Time ranges in a capture line: the start is the task's time and the span
/// its length.
@Suite("Capture parser time ranges")
struct CaptureParserTimeRangeTests {
  @Test("English ranges take AM or PM from the side that has it")
  func english() {
    let line = parse("Team sync 3-4pm")
    #expect(line.title == "Team sync")
    #expect(line.startMinutes == 15 * 60)
    #expect(line.estimatedMinutes == 60)
    #expect(line.phrases.map(\.text) == ["3-4pm"])
    #expect(line.plannedTime == (15 * 60)..<(16 * 60))

    #expect(parse("Lunch 11am-1pm").startMinutes == 11 * 60)
    #expect(parse("Lunch 11am-1pm").estimatedMinutes == 120)
    #expect(parse("Call 11-1pm").startMinutes == 11 * 60)
    #expect(parse("Review 12-1pm").startMinutes == 12 * 60)
    #expect(parse("Review 12-1pm").estimatedMinutes == 60)
    #expect(parse("Workshop 2pm to 4:30pm").estimatedMinutes == 150)
    #expect(parse("Workshop 2pm-4").estimatedMinutes == 120)
    #expect(parse("Focus from 9am until noon").startMinutes == 9 * 60)
    #expect(parse("Focus from 9am until noon").estimatedMinutes == 180)
    #expect(parse("Focus from 9am until noon").title == "Focus")
    #expect(parse("Deploy 15:00–16:30").startMinutes == 15 * 60)
    #expect(parse("Deploy 15:00–16:30").estimatedMinutes == 90)
    #expect(parse("Standup 9:30-10").estimatedMinutes == 30)
    #expect(parse("Party 10pm-midnight").estimatedMinutes == 120)
    #expect(parse("Night shift 11pm-1am").startMinutes == 23 * 60)
    #expect(parse("Night shift 11pm-1am").estimatedMinutes == 120)
  }

  @Test("A count or a phone number is not a range")
  func notRanges() {
    #expect(parse("Room 3-4").startMinutes == nil)
    #expect(parse("Room 3-4").title == "Room 3-4")
    #expect(parse("Call 555-1234").startMinutes == nil)
    #expect(parse("Read pages 10-12").title == "Read pages 10-12")
  }

  @Test("A written length wins over the span, and tonight moves a bare range to the evening")
  func lengthAndEvening() {
    let talk = parse("Talk 3-4pm 30 min")
    #expect(talk.startMinutes == 15 * 60)
    #expect(talk.estimatedMinutes == 30)
    let tonight = parse("Movie tonight 8:00-10:00")
    #expect(tonight.startMinutes == 20 * 60)
    #expect(tonight.estimatedMinutes == 120)
    #expect(tonight.plannedDayOffset == 0)
  }

  @Test("Chinese ranges, in either script")
  func chinese() {
    let line = parse("下午3点到5点开会")
    #expect(line.title == "开会")
    #expect(line.startMinutes == 15 * 60)
    #expect(line.estimatedMinutes == 120)
    #expect(line.phrases.map(\.text) == ["下午3点到5点"])

    #expect(parse("下午3点-4点半 评审").estimatedMinutes == 90)
    #expect(parse("下午3-5点 写报告").startMinutes == 15 * 60)
    #expect(parse("下午3-5点 写报告").estimatedMinutes == 120)
    #expect(parse("上午9点到12点 上课").startMinutes == 9 * 60)
    #expect(parse("上午9点到12点 上课").estimatedMinutes == 180)
    #expect(parse("3点到4点 开会").startMinutes == 15 * 60)
    #expect(parse("一点到两点 午休").startMinutes == 13 * 60)
    #expect(parse("一点到两点 午休").estimatedMinutes == 60)
    #expect(parse("下午3:00-4:00 面试").estimatedMinutes == 60)
    #expect(parse("晚上11点到1点 加班").startMinutes == 23 * 60)
    #expect(parse("晚上11点到1点 加班").estimatedMinutes == 120)
    let midnight = parse("晚上12点到1点 值班")
    #expect(midnight.startMinutes == 0)
    #expect(midnight.estimatedMinutes == 60)
    #expect(midnight.plannedDayOffset == 1)
    let traditional = parse("下午3點到5點開會")
    #expect(traditional.title == "開會")
    #expect(traditional.estimatedMinutes == 120)
    // A PM after the end belongs to the English reading of the range.
    #expect(parse("复盘 3:00-4:00pm").startMinutes == 15 * 60)
    #expect(parse("复盘 3:00-4:00pm").title == "复盘")
  }

  @Test("Japanese ranges")
  func japanese() {
    func ja(_ text: String) -> LorvexCaptureParse { parse(text, languages: ["ja"]) }
    let line = ja("15時から16時まで会議")
    #expect(line.title == "会議")
    #expect(line.startMinutes == 15 * 60)
    #expect(line.estimatedMinutes == 60)
    #expect(ja("午後3時〜5時 打ち合わせ").estimatedMinutes == 120)
    #expect(ja("3〜5時 作業").startMinutes == 15 * 60)
    #expect(ja("3〜5時 作業").estimatedMinutes == 120)
    #expect(ja("10:00〜11:30 面接").startMinutes == 10 * 60)
    #expect(ja("10:00〜11:30 面接").estimatedMinutes == 90)
    #expect(ja("夜10時から12時まで 勉強").startMinutes == 22 * 60)
    #expect(ja("夜10時から12時まで 勉強").estimatedMinutes == 120)
    #expect(ja("一時から二時まで 昼休み").startMinutes == 13 * 60)
    #expect(ja("一時から二時まで 昼休み").title == "昼休み")
  }

  @Test("Korean ranges")
  func korean() {
    func ko(_ text: String) -> LorvexCaptureParse { parse(text, languages: ["ko"]) }
    let line = ko("3시부터 4시까지 회의")
    #expect(line.title == "회의")
    #expect(line.startMinutes == 15 * 60)
    #expect(line.estimatedMinutes == 60)
    #expect(ko("오후 3시~5시 미팅").estimatedMinutes == 120)
    #expect(ko("3~5시 작업").startMinutes == 15 * 60)
    #expect(ko("3~5시 작업").estimatedMinutes == 120)
    #expect(ko("10:00~11:30 면접").estimatedMinutes == 90)
    #expect(ko("오전 9시부터 12시까지 수업").startMinutes == 9 * 60)
    #expect(ko("오전 9시부터 12시까지 수업").estimatedMinutes == 180)
    #expect(ko("밤 11시부터 1시까지 야근").startMinutes == 23 * 60)
    #expect(ko("밤 11시부터 1시까지 야근").estimatedMinutes == 120)
  }
}

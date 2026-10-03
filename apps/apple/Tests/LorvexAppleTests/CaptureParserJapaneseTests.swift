import LorvexCore
import Testing

// 2026-09-22 is a Tuesday: weekday 3 in the Gregorian convention.
private func parse(_ text: String, languages: [String] = ["ja-JP"]) -> LorvexCaptureParse {
  LorvexCaptureParser.parse(text, lists: [], todayWeekday: 3, today: "2026-09-22", languages: languages)
}

/// Japanese capture lines, read for a user whose languages include Japanese.
@Suite("Capture parser Japanese")
struct CaptureParserJapaneseTests {
  @Test("A day takes its particle with it")
  func days() {
    let line = parse("明日は歯医者")
    #expect(line.plannedDayOffset == 1)
    #expect(line.title == "歯医者")
    #expect(line.phrases.map(\.text) == ["明日は"])

    let friday = parse("金曜日に資料を送る")
    #expect(friday.plannedDayOffset == 3)
    #expect(friday.title == "資料を送る")
    #expect(parse("明後日に連絡").plannedDayOffset == 2)
    #expect(parse("あさって 連絡").plannedDayOffset == 2)
    #expect(parse("本日 提出").plannedDayOffset == 0)
    #expect(parse("再来週 出張").plannedDayOffset == 14)
    #expect(parse("週末に掃除").plannedDayOffset == 4)
    #expect(parse("週末に掃除").title == "掃除")
    #expect(parse("3日後に再検査").plannedDayOffset == 3)
    #expect(parse("3日後に再検査").title == "再検査")
  }

  @Test("Weekdays: the next one, this week's, and next week's")
  func weekdays() {
    // Today is Tuesday, so Tuesday alone is a week ahead.
    #expect(parse("火曜 定例").plannedDayOffset == 7)
    #expect(parse("火曜 定例").title == "定例")
    #expect(parse("今週の金曜に提出").plannedDayOffset == 3)
    #expect(parse("今週の金曜に提出").title == "提出")
    #expect(parse("来週の水曜に面談").plannedDayOffset == 8)
    #expect(parse("来週月曜 面談").plannedDayOffset == 6)
    #expect(parse("次の金曜 飲み会").plannedDayOffset == 3)
    #expect(parse("再来週の金曜 発表").plannedDayOffset == 17)
    #expect(parse("再来週の金曜 発表").title == "発表")
    #expect(parse("来週末 キャンプ").plannedDayOffset == 11)
    #expect(parse("明日も練習").plannedDayOffset == 1)
    #expect(parse("明日も練習").title == "練習")
    let nextWeek = parse("来週の会議")
    #expect(nextWeek.plannedDayOffset == 7)
    #expect(nextWeek.title == "会議")
  }

  @Test("Dates, with or without their weekday in brackets")
  func dates() {
    let line = parse("10月5日に提出")
    #expect(line.plannedDayOffset == 13)
    #expect(line.title == "提出")
    #expect(parse("10/5(月) 打ち合わせ").plannedDayOffset == 13)
    #expect(parse("10/5(月) 打ち合わせ").title == "打ち合わせ")
    #expect(parse("１０月５日 面接").plannedDayOffset == 13)
    // Without the logical today, written-out dates are not read.
    #expect(
      LorvexCaptureParser.parse("10月5日に提出", lists: [], todayWeekday: 3, languages: ["ja"]).plannedDayOffset == nil)
  }

  @Test("Date ranges: the first day is planned and the last is due")
  func dateRanges() {
    expectDateRanges(
      [
        ("出張", "5月3日から5日まで", "2027-05-03", "2027-05-05"),
        ("出張", "5月3日から5月5日まで", "2027-05-03", "2027-05-05"),
        ("出張", "5月3日〜5日", "2027-05-03", "2027-05-05"),
        ("出張", "5月3日～5日", "2027-05-03", "2027-05-05"),
        ("出張", "5月3日-5日", "2027-05-03", "2027-05-05"),
        ("出張", "5月3日から5日", "2027-05-03", "2027-05-05"),
        ("出張", "5/3〜5/5", "2027-05-03", "2027-05-05"),
        ("出張", "5月3日(金)〜5日(日)", "2027-05-03", "2027-05-05"),
        ("出張", "５月３日から５日まで", "2027-05-03", "2027-05-05"),
        ("出張", "5月3日から5日までに", "2027-05-03", "2027-05-05"),
        ("出張", "5月30日から6月2日まで", "2027-05-30", "2027-06-02"),
        ("出張", "12月30日から1月2日まで", "2026-12-30", "2027-01-02"),
        ("出張", "10月3日から5日まで", "2026-10-03", "2026-10-05"),
      ], languages: ["ja-JP"])

    // The range may open the line with no space after it, and its particle
    // leaves with it.
    let leading = parse("5月3日から5日まで出張")
    #expect(leading.title == "出張")
    #expect(leading.phrases.map(\.text) == ["5月3日から5日まで"])
    let particle = parse("出張 5月3日から5日までに提出")
    #expect(particle.title == "出張 提出")
    #expect(particle.dueDayOffset == captureDayOffset("2027-05-05"))
  }

  @Test("A range whose end is not after its start stays in the title whole")
  func declinedDateRanges() {
    expectLinesUnread(
      [
        "出張 5月5日から3日まで", "出張 5月5日から5月3日まで", "出張 5月3日から5月3日まで", "出張 5月3日から2月30日まで",
      ], languages: ["ja-JP"])
  }

  @Test("Weekday and time ranges, counts of days, and days with no month are not date ranges")
  func nonDateRanges() {
    // A weekday range is a planned weekday and a due weekday.
    let weekdays = parse("会議 月曜から金曜まで")
    #expect(weekdays.phrases.map(\.kind) == [.when, .due])

    let time = parse("会議 15時から16時まで")
    #expect(time.startMinutes == 15 * 60)
    #expect(time.estimatedMinutes == 60)
    #expect(time.dueDayOffset == nil)

    // 5日後 counts days from today, so "5日後から7日後まで" is two such days.
    let relative = parse("旅行 5日後から7日後まで")
    #expect(relative.plannedDayOffset == 5)
    #expect(relative.dueDayOffset == 7)

    // 5日間 counts days, so it is no end: only the first date is read.
    let span = parse("旅行 5月3日から5日間")
    #expect(span.plannedDayOffset == captureDayOffset("2027-05-03"))
    #expect(span.dueDayOffset == nil)
    #expect(span.title == "旅行 5日間")

    // A lone day of the month is not a date here.
    expectLinesUnread(["旅行 3日から5日まで"], languages: ["ja-JP"])
  }

  @Test("A name that starts with a day word stays whole")
  func namesStayWhole() {
    let asuka = parse("明日香さんに連絡")
    #expect(asuka.plannedDayOffset == nil)
    #expect(asuka.title == "明日香さんに連絡")
    #expect(parse("今日子さんと昼食").plannedDayOffset == nil)
  }

  @Test("Clock times, with a part of the day or without")
  func times() {
    let line = parse("午後3時に会議")
    #expect(line.startMinutes == 15 * 60)
    #expect(line.title == "会議")
    #expect(parse("10時から打ち合わせ").startMinutes == 10 * 60)
    #expect(parse("10時から打ち合わせ").title == "打ち合わせ")
    #expect(parse("3時半に電話").startMinutes == 15 * 60 + 30)
    #expect(parse("3時ごろ電話").startMinutes == 15 * 60)
    #expect(parse("3時ごろ電話").title == "電話")
    #expect(parse("朝7時 ランニング").startMinutes == 7 * 60)
    #expect(parse("夕方6時 買い物").startMinutes == 18 * 60)
    #expect(parse("午後3:30 歯医者").startMinutes == 15 * 60 + 30)
    #expect(parse("午後3:30 歯医者").title == "歯医者")
    #expect(parse("正午にランチ").startMinutes == 12 * 60)
    #expect(parse("正午にランチ").title == "ランチ")
    #expect(parse("十時 朝礼").startMinutes == 10 * 60)
    #expect(parse("3時までに提出").startMinutes == 15 * 60)
    #expect(parse("3時までに提出").title == "提出")

    // The minutes of a clock time are not a length.
    let minutes = parse("9時20分に集合")
    #expect(minutes.startMinutes == 9 * 60 + 20)
    #expect(minutes.estimatedMinutes == nil)
    #expect(minutes.title == "集合")

    // 一時 alone means "for a while".
    #expect(parse("一時保存").startMinutes == nil)
    #expect(parse("一時保存").title == "一時保存")
  }

  @Test("The night runs past midnight, and 今夜 is an evening")
  func nights() {
    #expect(parse("夜8時にジム").startMinutes == 20 * 60)
    #expect(parse("夜8時にジム").title == "ジム")
    let midnight = parse("夜12時に就寝")
    #expect(midnight.startMinutes == 0)
    #expect(midnight.plannedDayOffset == 1)
    let tonight = parse("今夜8時に電話")
    #expect(tonight.startMinutes == 20 * 60)
    #expect(tonight.plannedDayOffset == 0)
    #expect(tonight.title == "電話")
    #expect(parse("今朝7時 散歩").startMinutes == 7 * 60)
    #expect(parse("今朝7時 散歩").plannedDayOffset == 0)
    #expect(parse("今朝7時 散歩").title == "散歩")
    #expect(parse("明日の夜9時 映画").startMinutes == 21 * 60)
    #expect(parse("明日の夜9時 映画").plannedDayOffset == 1)
  }

  @Test("Lengths")
  func lengths() {
    let line = parse("資料作成30分")
    #expect(line.estimatedMinutes == 30)
    #expect(line.title == "資料作成")
    #expect(parse("2時間 勉強").estimatedMinutes == 120)
    #expect(parse("1時間半 ジョギング").estimatedMinutes == 90)
    #expect(parse("1時間30分 会議").estimatedMinutes == 90)
    #expect(parse("一時間 読書").estimatedMinutes == 60)
    #expect(parse("30分ほど散歩").estimatedMinutes == 30)
    #expect(parse("30分ほど散歩").title == "散歩")
    #expect(parse("30分間 瞑想").estimatedMinutes == 30)
  }

  @Test("A day, a time, and a length in one line")
  func everything() {
    let line = parse("明日の午後3時から1時間 会議")
    #expect(line.plannedDayOffset == 1)
    #expect(line.startMinutes == 15 * 60)
    #expect(line.estimatedMinutes == 60)
    #expect(line.title == "会議")
    #expect(line.phrases.map(\.text) == ["明日の", "午後3時から", "1時間"])
  }

  @Test("Repeats")
  func repeats() {
    let line = parse("毎日 日記")
    #expect(line.recurrence == TaskRecurrenceRule(freq: .daily))
    #expect(line.title == "日記")
    #expect(parse("毎週月曜 ゴミ出し").recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["MO"]))
    #expect(parse("毎月曜 定例").recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["MO"]))
    #expect(parse("毎日曜 教会").recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["SU"]))
    #expect(parse("毎日曜 教会").title == "教会")
    #expect(
      parse("毎週月・水・金 ジム").recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "WE", "FR"]))
    #expect(parse("毎週土日 ランニング").recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["SU", "SA"]))
    #expect(parse("毎週木曜日と金曜日 練習").recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["TH", "FR"]))
    #expect(parse("隔週水曜 定例").recurrence == TaskRecurrenceRule(freq: .weekly, interval: 2, byDay: ["WE"]))
    #expect(parse("毎週末 掃除").recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["SA"]))
    #expect(parse("毎月5日 家賃").recurrence == TaskRecurrenceRule(freq: .monthly, byMonthDay: [5]))
    #expect(parse("毎年 健康診断").recurrence == TaskRecurrenceRule(freq: .yearly))
    #expect(parse("3日ごとに水やり").recurrence == TaskRecurrenceRule(freq: .daily, interval: 3))
    #expect(parse("3日ごとに水やり").title == "水やり")
    #expect(parse("1日おきに運動").recurrence == TaskRecurrenceRule(freq: .daily, interval: 2))
    #expect(parse("2週間ごと 振り返り").recurrence == TaskRecurrenceRule(freq: .weekly, interval: 2))
    #expect(parse("3か月ごと 点検").recurrence == TaskRecurrenceRule(freq: .monthly, interval: 3))
    #expect(
      parse("平日毎日 朝礼").recurrence
        == TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "TU", "WE", "TH", "FR"]))

    // A repeat starts on the first day it names: today is Tuesday.
    #expect(parse("毎週金曜 振り返り").recurrenceStartOffset == 3)
    // One weekday character after 毎週 is not a weekday list.
    let watering = parse("毎週水やり")
    #expect(watering.recurrence == TaskRecurrenceRule(freq: .weekly))
    #expect(watering.title == "水やり")
  }

  @Test("Due days and priority")
  func dueAndPriority() {
    let line = parse("金曜までに資料提出")
    #expect(line.dueDayOffset == 3)
    #expect(line.plannedDayOffset == nil)
    #expect(line.title == "資料提出")
    #expect(parse("今日中に返信").dueDayOffset == 0)
    #expect(parse("今日中に返信").title == "返信")
    #expect(parse("報告書 10/5(月)締切").dueDayOffset == 13)
    #expect(parse("報告書 10/5(月)締切").title == "報告書")

    #expect(parse("至急 見積もり").priority == .p1)
    #expect(parse("至急 見積もり").title == "見積もり")
    #expect(parse("急ぎで返信").priority == .p1)
    #expect(parse("緊急対応").priority == .p1)
    #expect(parse("緊急対応").title == "対応")
  }

  @Test("Japanese words are read only for a user who reads Japanese")
  func languageGate() {
    let line = parse("明後日に連絡", languages: ["en-US"])
    #expect(line.plannedDayOffset == nil)
    #expect(line.title == "明後日に連絡")
    #expect(parse("毎週月曜 ゴミ出し", languages: ["en-US", "zh-Hans"]).recurrence == nil)
    #expect(parse("明後日に連絡", languages: ["en-US", "ja"]).plannedDayOffset == 2)
  }
}

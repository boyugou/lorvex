import Foundation

extension LorvexCaptureVocabulary {
  // The Vietnamese repeat rules: working days, weekends, a day of the month,
  // counted intervals, "once per" phrases, repeated weekdays, cadence phrases, and
  // the counts of times in a period that name no repeat. The vocabulary's other
  // words are in ``vietnamese``.

  /// The repeat rules in the order they are tried: the working days and the
  /// weekend and a day of the month before the rule for every day and every month,
  /// which would leave "ngày làm việc" or the day's number in the title; the counted
  /// intervals before the weekday rules, so "mỗi 2 tuần vào thứ Hai" takes its
  /// interval with its weekday; the span of weekdays before the list of them, so
  /// "mỗi thứ Hai đến thứ Sáu" is read whole.
  static let vietnameseRepeatRules: [Rule<Repeat>] = [
    Rule(pattern: vietnameseWorkdaysPattern) { _ in workdays },
    Rule(pattern: vietnameseWeekendRepeatPattern) { _ in weekly(every: nil, on: [6, 0]) },
    Rule(pattern: vietnameseMonthDayRepeatPattern, read: vietnameseMonthDayRepeat),
    Rule(pattern: vietnameseIntervalRepeatPattern, read: vietnameseIntervalRepeat),
    Rule(pattern: vietnameseWeekdaySpanRepeatPattern, read: vietnameseWeekdaySpanRepeat),
    Rule(pattern: vietnameseWeekdayRepeatPattern, read: vietnameseWeekdayRepeat),
    Rule(pattern: vietnameseEveryUnitPattern, read: vietnameseEveryUnit),
  ]

  /// "mỗi", "mọi", "hằng", and "hàng", the words that open a repeat, as a pattern
  /// without groups.
  static let vietnameseRepeatEvery = vietnameseAlternation(["mỗi", "mọi", "hằng", "hàng"])

  /// The words that leave a day out of "every day" or "every working day" ("hằng
  /// ngày trừ Chủ nhật", "mỗi ngày ngoại trừ thứ Bảy"), as a pattern without
  /// groups. A repeat that has an exception is none the app can set, so the phrase
  /// stays in the title whole.
  private static let vietnameseRepeatException =
    vietnameseAlternation(["ngoại trừ", "không kể", "không tính", "trừ", "ngoài"])

  // MARK: - Working days and weekends

  /// "mỗi ngày làm việc", "hàng ngày làm việc", "các ngày làm việc", "vào các ngày
  /// làm việc", "vào ngày làm việc", "các ngày trong tuần". "Ngày làm việc" with no
  /// word before it is a count of working days ("trong 3 ngày làm việc"), and "mỗi
  /// ngày làm việc 8 tiếng" is every day, working. "Các ngày trong tuần" is the
  /// weekdays; "tất cả các ngày trong tuần" and "mọi ngày trong tuần" are every
  /// day, which no rule reads. A day left out ("mỗi ngày làm việc trừ thứ Sáu")
  /// makes the phrase no repeat the app can set.
  private static let vietnameseWorkdaysPattern: String = {
    let working = vietnameseWord("ngày làm việc")
    let notFollowed =
      #"(?!\s+(?:\#(vietnameseAlternation(["với", "cùng", "cho", "tại", "ở", "trên", "dưới", "tiếp theo", "kế tiếp", "đầu tiên", "cuối cùng", "trước", "sau", "gần nhất", "này", "đó"]))|\#(vietnameseRepeatException)\#(vietnameseEnd)|\d))"#
    let weekdays = #"(?<!(?:\#(vietnameseAlternation(["tất cả", "mọi", "mỗi"], gap: #"\s{1,3}"#))\s{1,3}))(?:\#(vietnameseWord("vào"))\s+)?\#(vietnameseWord("các"))\s+\#(vietnameseWord("ngày trong tuần"))"#
    return
      #"\#(vietnameseStart)(?:(?:\#(vietnameseWord("vào"))\s+)?(?:\#(vietnameseRepeatEvery)|\#(vietnameseWord("các")))\s+\#(working)\#(notFollowed)|\#(vietnameseWord("vào"))\s+\#(working)\#(notFollowed)|\#(weekdays))\#(vietnameseEnd)"#
  }()

  /// "mỗi cuối tuần", "hàng cuối tuần", "các cuối tuần", "vào các cuối tuần". "Cuối
  /// tuần" with no word before it names the coming weekend, a day.
  private static let vietnameseWeekendRepeatPattern =
    #"\#(vietnameseStart)(?:\#(vietnameseWord("vào"))\s+)?(?:\#(vietnameseRepeatEvery)|\#(vietnameseWord("các")))\s+\#(vietnameseWord("cuối tuần"))\#(vietnameseEnd)"#

  // MARK: - Day of the month

  /// "mỗi tháng vào ngày 5", "hàng tháng ngày 15", "ngày 5 hàng tháng", "vào ngày 5
  /// của mỗi tháng", "ngày 15 mỗi tháng". The day may not go on as a list or a range
  /// of days ("ngày 5 và 20", "ngày 5 đến 7"). Groups 1 and 2: the day of the month
  /// in each form.
  private static var vietnameseMonthDayRepeatPattern: String {
    let ngay = vietnameseWord("ngày")
    let month = #"\#(vietnameseRepeatEvery)\s+\#(vietnameseWord("tháng"))"#
    let notMore = #"(?![\p{N}%]|[.,:]\p{N})(?!\s*(?:[-–—/,&]|(?:\#(vietnameseAlternation(["đến", "và", "hoặc"]))|\#(vietnameseWord("tới", strict: true)))\s)\s*(?:\#(ngay)\s+)?\d)"#
    return
      #"\#(vietnameseStart)(?:\#(month)\s*,?\s*(?:\#(vietnameseWord("vào"))\s+)?\#(ngay)\s+(\d{1,2})\#(notMore)|(?:\#(vietnameseWord("vào"))\s+)?\#(ngay)\s+(\d{1,2})\#(notMore)\s+(?:\#(vietnameseWord("của"))\s+)?\#(month))\#(vietnameseEnd)"#
  }

  private static func vietnameseMonthDayRepeat(_ match: Match) -> Repeat? {
    guard let text = match.group(1) ?? match.group(2) else { return nil }
    return number(text).flatMap { monthly(every: nil, on: $0) }
  }

  // MARK: - Repeated weekdays

  /// The weekdays of a list, as a pattern without groups: "thứ Hai", "thứ Hai và thứ
  /// Tư", "thứ Hai, thứ Tư, thứ Sáu", and the shorthand "thứ 2, 4, 6" whose numbers
  /// follow the first. A number that counts something ("thứ 2, 4 người") is no day.
  /// After "mỗi", "hàng", or "các", "thu tu" is Wednesday and no order.
  private static var vietnameseRepeatList: String {
    let day = vietnameseWeekdayNamesInList
    let and = vietnameseWord("và")
    let separator = #"(?:\s*,\s*(?:\#(and)\s+)?|\s+\#(and)\s+|\s*&\s*)"#
    let digit = #"[2-7](?![\p{N}])\#(vietnameseNotCounted)"#
    let numeric = #"\#(vietnameseWord("thứ"))\s+\#(digit)(?:\#(separator)\#(digit)){1,5}"#
    return #"(?:\#(numeric)|\#(day)(?:\#(separator)\#(day)){0,6})"#
  }

  /// The weekdays a matched list names, 0 = Sunday.
  private static func vietnameseRepeatWeekdays(_ list: String) -> [Int] {
    let tokens = vietnameseKey(list).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    var days: [Int] = []
    var index = 0
    while index < tokens.count {
      let token = tokens[index]
      if token == "thu", index + 1 < tokens.count, let day = vietnameseWeekdayIndex("thu \(tokens[index + 1])") {
        days.append(day)
        index += 2
        // The shorthand "thứ 2, 4, 6" lists the numbers after the first.
        while index < tokens.count, let digit = Int(tokens[index]), (2...7).contains(digit) {
          days.append(digit - 1)
          index += 1
        }
      } else if token == "chu" || token == "chua", index + 1 < tokens.count, tokens[index + 1] == "nhat" {
        days.append(0)
        index += 2
      } else {
        index += 1
      }
    }
    return days
  }

  /// "mỗi thứ Hai", "mỗi thứ Hai và thứ Tư", "mỗi thứ 2, 4, 6", "mỗi tuần vào thứ
  /// Hai", "hàng tuần vào các thứ Hai", "các thứ Hai", "mỗi sáng thứ Hai", "mỗi thứ
  /// Hai sáng", and the cadence after the weekdays ("thứ Hai hàng tuần", "các thứ
  /// Ba và thứ Năm mỗi tuần"). A part of the day beside the weekdays is part of the
  /// phrase, as in a day phrase, and so is a cadence after weekdays that an
  /// opening word began ("mỗi thứ Hai và thứ Tư hằng tuần"). Groups: 1 the weekdays
  /// after the opening word, 2 the weekdays before the cadence.
  private static var vietnameseWeekdayRepeatPattern: String {
    let week = vietnameseWord("tuần")
    let vao = vietnameseWord("vào")
    let lead =
      #"(?:\#(vietnameseRepeatEvery)(?:\s+\#(week))?(?:\s+\#(vao))?|(?:\#(vao)\s+)?\#(vietnameseWord("các")))\s+"#
    let part = #"(?:\#(vietnameseBuoi)\#(vietnameseDayParts)\s+)?"#
    let partAfter = #"(?:\s+\#(vietnameseBuoi)\#(vietnameseDayParts))?"#
    let cadence = #"(?:\s+\#(vietnameseRepeatEvery)\s+\#(week))?"#
    let opening = #"\#(lead)(?:\#(vietnameseWord("các"))\s+)?\#(part)(\#(vietnameseRepeatList))\#(partAfter)\#(cadence)"#
    let closing =
      #"(?:(?:\#(vao)\s+)?\#(vietnameseWord("các"))\s+)?(\#(vietnameseRepeatList))\s+\#(vietnameseRepeatEvery)\s+\#(week)"#
    return #"\#(vietnameseStart)(?:\#(opening)|\#(closing))\#(vietnameseEnd)"#
  }

  private static func vietnameseWeekdayRepeat(_ match: Match) -> Repeat? {
    guard let list = match.group(1) ?? match.group(2) else { return nil }
    let days = vietnameseRepeatWeekdays(list)
    return days.isEmpty ? nil : weekly(every: nil, on: days)
  }

  /// "mỗi thứ Hai đến thứ Sáu", "mỗi tuần từ thứ Hai đến thứ Sáu", "hàng ngày từ thứ
  /// Hai đến thứ Sáu", "từ thứ Hai đến thứ Sáu hàng tuần", "thứ Hai - thứ Sáu mỗi
  /// tuần": a span of weekdays with a cadence. Groups: 1 and 2 the first and the last
  /// weekday after the opening word; 3 and 4 before the cadence.
  private static var vietnameseWeekdaySpanRepeatPattern: String {
    let day = vietnameseWeekdayNamesInList
    let from = #"(?:\#(vietnameseWord("từ"))\s+)?"#
    let to = #"\s*(?:\#(vietnameseAlternation(["đến", "tới"]))|[-–—])\s*"#
    let unit = vietnameseAlternation(["tuần", "ngày"])
    let opening =
      #"\#(vietnameseRepeatEvery)(?:\s+\#(unit))?\s+\#(from)(\#(day))\#(to)(\#(day))"#
    let closing = #"\#(from)(\#(day))\#(to)(\#(day))\s+\#(vietnameseRepeatEvery)\s+\#(unit)"#
    return #"\#(vietnameseStart)(?:\#(opening)|\#(closing))\#(vietnameseEnd)"#
  }

  private static func vietnameseWeekdaySpanRepeat(_ match: Match) -> Repeat? {
    guard let firstText = match.group(1) ?? match.group(3), let lastText = match.group(2) ?? match.group(4),
      let first = vietnameseWeekdayIndex(firstText), let last = vietnameseWeekdayIndex(lastText), first != last
    else { return nil }
    var days = [first]
    var day = first
    while day != last {
      day = (day + 1) % 7
      days.append(day)
    }
    return weekly(every: nil, on: days)
  }

  // MARK: - Counted intervals and "once per"

  /// The repeat every `every` (nil for each) of the unit a word names: days, weeks,
  /// months, or years. A whole number of weeks counted in days is a weekly repeat
  /// ("14 ngày"), and a word that is no unit returns nil.
  private static func vietnameseRepeat(unit: String, every: Int?) -> Repeat? {
    switch vietnameseKey(unit) {
    case "ngay":
      if let count = every, count % 7 == 0 { return weekly(every: count / 7 == 1 ? nil : count / 7, on: []) }
      return Repeat(rule: TaskRecurrenceRule(freq: .daily, interval: every))
    case "tuan": return weekly(every: every, on: [])
    case "thang": return monthly(every: every, on: nil)
    case "nam": return Repeat(rule: TaskRecurrenceRule(freq: .yearly, interval: every))
    default: return nil
    }
  }

  /// "mỗi 2 ngày", "mỗi hai tuần", "cứ 3 tháng", "cứ 2 ngày một lần", "2 ngày một lần",
  /// "hai tuần một lần", "2 tuần/lần", "tuần một lần", "ngày một lần", "một lần mỗi
  /// tuần", "1 lần/tháng", "một lần một năm", "cách ngày", "cách tuần", each maybe
  /// before weekdays after a weekly interval ("mỗi 2 tuần vào thứ Ba"). A count of
  /// times in a period ("hai lần một tuần") is no repeat and an interval of hours
  /// ("mỗi 2 giờ") is a length, so both stay in the title; "ngày làm việc" after a
  /// count is a count of working days. Groups: 1 and 2 the count and the unit after
  /// "mỗi" or "cứ"; 3 and 4 the count and the unit before "một lần"; 5 the unit
  /// before "một lần"; 6 the unit after "một lần"; 7 the unit after "cách"; 8 the
  /// weekdays.
  private static var vietnameseIntervalRepeatPattern: String {
    let count = #"(\d{1,3}|\#(vietnameseNumberWords))"#
    let units = vietnameseAlternation(["ngày", "tuần", "tháng", "năm"])
    let once = #"(?:\#(vietnameseWord("một"))|1)\s+\#(vietnameseWord("lần"))"#
    let weekdays = #"(?:\s+(?:\#(vietnameseWord("vào"))\s+)?(\#(vietnameseRepeatList)))?"#
    let notWorking = #"(?!\s+\#(vietnameseWord("làm việc")))"#
    let every = "(?:\(vietnameseRepeatEvery)|\(vietnameseWord("cứ", strict: true)))"
    let afterOnce =
      #"(?:\#(vietnameseWord("một"))\s+|\#(vietnameseRepeatEvery)\s+|\#(vietnameseWord("trong"))\s+|\s*/\s*)"#
    return
      #"\#(vietnameseStart)(?:\#(every)\s+\#(count)\s+(\#(units))\#(notWorking)(?:\s+\#(once))?|\#(count)\s+(\#(units))\#(notWorking)\s*(?:\#(once)|/\s*\#(vietnameseWord("lần")))|(?:\#(vietnameseRepeatEvery)\s+)?(\#(units))\s+\#(once)|\#(once)\s*\#(afterOnce)(\#(units))|\#(vietnameseWord("cách"))\s+(\#(vietnameseAlternation(["ngày", "tuần", "tháng"])))\#(notWorking)(?!\s+\d))\#(weekdays)\#(vietnameseEnd)"#
  }

  private static func vietnameseIntervalRepeat(_ match: Match) -> Repeat? {
    let base: Repeat?
    if let countText = match.group(1), let unit = match.group(2) {
      base = vietnameseCounted(countText, unit)
    } else if let countText = match.group(3), let unit = match.group(4) {
      base = vietnameseCounted(countText, unit)
    } else if let unit = match.group(5) ?? match.group(6) {
      base = vietnameseRepeat(unit: unit, every: nil)
    } else if let unit = match.group(7) {
      base = vietnameseRepeat(unit: unit, every: 2)
    } else {
      return nil
    }
    guard let base else { return nil }
    guard let list = match.group(8) else { return base }
    // A weekday after a weekly interval fixes the repeat's days.
    let days = vietnameseRepeatWeekdays(list)
    return base.rule.freq == .weekly && !days.isEmpty ? weekly(every: base.rule.interval, on: days) : nil
  }

  /// The repeat every `count` of `unit`, for a count from 1 to 99.
  private static func vietnameseCounted(_ countText: String, _ unit: String) -> Repeat? {
    guard let count = vietnameseCount(countText), (1...99).contains(count) else { return nil }
    return vietnameseRepeat(unit: unit, every: count == 1 ? nil : count)
  }

  /// "2 lần mỗi ngày", "hai lần một tuần", "3 lần/tuần", "ngày 2 lần", "mỗi tuần ba
  /// lần", "2 lần trong một tháng": a count of times in a period names no repeat the
  /// app can set, so the phrase stays in the title whole. Once ("một lần mỗi tuần") is
  /// a repeat of the interval rule. Groups: 1 the unit and 2 the count before
  /// "lần"; 3 the count and 4 the unit after "lần".
  static let vietnameseTimesPerPeriodPattern: String = {
    let count = #"(\d{1,3}|\#(vietnameseNumberWords))"#
    let units = vietnameseAlternation(["ngày", "tuần", "tháng", "năm"])
    let times = vietnameseWord("lần")
    let afterTimes =
      #"(?:/\s*|\s*(?:\#(vietnameseRepeatEvery)|\#(vietnameseWord("trong"))|\#(vietnameseWord("một"))|1)\s+(?:\#(vietnameseWord("một"))\s+)?)"#
    return
      #"\#(vietnameseStart)(?:(?:\#(vietnameseRepeatEvery)\s+)?(\#(units))\s+\#(count)\s+\#(times)|\#(count)\s+\#(times)\s*\#(afterTimes)(\#(units)))\#(vietnameseEnd)"#
  }()

  /// Whether a match of ``vietnameseTimesPerPeriodPattern`` counts two times or more.
  static func vietnameseIsMultipleTimes(_ match: Match) -> Bool {
    guard let text = match.group(2) ?? match.group(3), let count = vietnameseCount(text) else { return false }
    return count >= 2
  }

  // MARK: - Cadence phrases

  /// "mỗi ngày", "hàng ngày", "hằng ngày", "mỗi tuần", "hàng tuần", "mỗi tháng", "hàng
  /// năm", "mỗi quý", "mỗi sáng", "mỗi tối", each maybe with "một lần" after it. "Ngày"
  /// before a rest day, a holiday, a day left out, or a weekday ("mỗi ngày nghỉ",
  /// "mỗi ngày lễ", "mỗi ngày trừ Chủ nhật", "mỗi ngày thứ Sáu", which may also be
  /// every sixth day), a working day or the days of the week ("mỗi ngày làm việc",
  /// "mỗi ngày trong tuần"), or a number that ends the phrase ("mỗi ngày 15" is the
  /// 15th of each month, while "mỗi ngày 30 phút" is a daily length), "tuần" before
  /// a week word ("mỗi tuần này"), "tháng" before a number ("mỗi tháng 10" is every
  /// October), and "năm" before a unit or a number ("mỗi năm ngày") name no cadence
  /// the app can set and stay in the title. Group 1: the unit or the part of the day
  /// after the opening word.
  private static var vietnameseEveryUnitPattern: String {
    let notFollowedByWeekWord =
      #"(?!\s+\#(vietnameseAlternation(["này", "sau", "tới", "trước", "qua", "rồi"]))\#(vietnameseEnd))"#
    let notADay =
      #"(?!\s+(?:\#(vietnameseAlternation(["làm việc", "trong tuần", "nghỉ", "lễ", "tết", "thường", "cuối tuần"]))|\#(vietnameseRepeatException)|\#(vietnameseWeekdayNames))\#(vietnameseEnd))(?!\s+\d{1,2}(?![\p{N}%]|[.,:]\p{N}|\s*\p{L}))"#
    let notAMonth =
      #"(?!\s+(?:\d|\#(vietnameseNumberWords)(?!\s+\#(vietnameseWord("lần")))))\#(notFollowedByWeekWord)"#
    let notAYear =
      #"(?!\s+(?:\d|\#(vietnameseAlternation(["ngày", "tuần", "tháng", "giờ", "phút", "tiếng"]))\#(vietnameseEnd)))\#(notFollowedByWeekWord)"#
    let parts = vietnameseAlternation(["sáng", "trưa", "chiều", "tối"])
    let night = #"(?:\#(vietnameseWord("đêm", strict: true))|dem(?=\s*(?:$|[,.;:!?)])))"#
    let once = #"(?:\s+(?:\#(vietnameseWord("một"))|1)\s+\#(vietnameseWord("lần")))?"#
    return
      #"\#(vietnameseStart)\#(vietnameseRepeatEvery)\s+(\#(vietnameseWord("ngày"))\#(notADay)|\#(vietnameseWord("tuần"))\#(notFollowedByWeekWord)|\#(vietnameseWord("tháng"))\#(notAMonth)|\#(vietnameseWord("năm"))\#(notAYear)|\#(vietnameseWord("quý"))(?!\s+(?:\d|[ivx]+\#(vietnameseEnd)))|\#(parts)(?!\s+\#(vietnameseWord("thứ")))|\#(night))\#(once)\#(vietnameseEnd)"#
  }

  private static func vietnameseEveryUnit(_ match: Match) -> Repeat? {
    guard let word = match.group(1).map(vietnameseKey) else { return nil }
    switch word {
    case "tuan": return weekly(every: nil, on: [])
    case "thang": return monthly(every: nil, on: nil)
    case "nam": return Repeat(rule: TaskRecurrenceRule(freq: .yearly))
    case "quy": return monthly(every: 3, on: nil)
    default: return Repeat(rule: TaskRecurrenceRule(freq: .daily))
    }
  }
}

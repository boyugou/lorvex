import Foundation

extension LorvexCaptureVocabulary {
  // The Vietnamese day rules: the due day, the planned day, and the date ranges.
  // The vocabulary's other words are in ``vietnamese``.

  // MARK: - Parts of the day

  /// The words that name a part of the day, as a pattern without groups: "sáng"
  /// (and "sáng sớm", "rạng sáng"), "trưa", "chiều", "tối", "đêm", "khuya". "Đêm"
  /// typed without its marks is "dem", which is also "đem" (to bring) and "đếm" (to
  /// count), so it is the night only before "nay" or "mai" or at the end of a
  /// clause; "đem" typed with its stroke is never the night.
  static let vietnameseDayParts: String = {
    let night =
      #"(?:\#(vietnameseWord("đêm", strict: true))|dem(?=\s*(?:$|[,.;:!?)]|(?:nay|mai)(?![\p{Latin}\p{N}\p{M}]))))"#
    let morning = vietnameseAlternation(["sáng sớm", "rạng sáng", "sáng"])
    return "(?:\(morning)|\(vietnameseAlternation(["trưa", "chiều", "tối"]))|\(night)|khuya)"
  }()

  /// "Buổi" before a part of the day ("buổi sáng"), with the space after it, as an
  /// optional pattern without groups.
  static let vietnameseBuoi = #"(?:\#(vietnameseWord("buổi"))\s+)?"#

  /// The words that form a noun with the part of the day written after them ("ăn
  /// tối" is dinner, "bữa trưa" lunch, "ca sáng" the morning shift, "ngủ trưa" a
  /// nap), as a pattern without groups.
  private static let vietnameseNounsBeforePart =
    vietnameseAlternation(["ăn", "bữa", "cơm", "tiệc", "ca", "lớp", "ngủ", "nghỉ", "phê"])

  /// What may not come before a part of the day that names a day ("tối mai", "sáng
  /// nay"): a word it forms a noun with. That part belongs to the noun, so it is
  /// not the part of a day that follows it: in "Ăn tối mai" the day is "mai" and the
  /// title stays "Ăn tối".
  static let vietnameseNotNounBeforePart =
    #"(?<!(?:^|[^\p{Latin}\p{N}\p{M}])\#(vietnameseNounsBeforePart)\s{1,3})"#

  /// "Mai" or "nay" after a part of the day that forms a noun with the word before
  /// it ("ăn tối mai", "ngủ trưa nay"): the day, with the part left in the title.
  /// The look-behind is built from bounded repetitions, which ICU requires of one,
  /// and so spells the parts itself: the toneless "dem" needs no guard here, since
  /// the "mai" or "nay" after it is what the guard asks for.
  private static let vietnameseDayAfterNounPart: String = {
    let gap = #"\s{1,3}"#
    let morning = vietnameseAlternation(["sáng sớm", "rạng sáng", "sáng"], gap: gap)
    let others = vietnameseAlternation(["trưa", "chiều", "tối", "đêm", "khuya"], gap: gap)
    let buoi = #"(?:\#(vietnameseWord("buổi"))\#(gap))?"#
    return
      #"(?<=(?:^|[^\p{Latin}\p{N}\p{M}])\#(vietnameseNounsBeforePart)\#(gap)\#(buoi)(?:\#(morning)|\#(others))\#(gap))(?:mai|\#(vietnameseWord("nay")))"#
  }()

  // MARK: - Weekdays

  /// The weekday names, as a pattern without groups: "thứ Hai", "thứ Ba", "thứ Tư",
  /// "thứ Năm", "thứ Sáu", "thứ Bảy", "thứ 2" to "thứ 7", and "Chủ nhật" ("Chúa
  /// nhật"). "Tư" is read only with its mark: "tu" is also "tự" ("thứ tự" is an
  /// order, not Wednesday).
  static let vietnameseWeekdayNames = vietnameseWeekdayNamePattern(strictWednesday: true)

  /// The weekday names where "thứ tư" may be typed without its marks: the names
  /// inside a list or a span of weekdays ("thứ Hai và thứ Tư", "thứ Hai đến thứ
  /// Tư"), where "thu tu" is Wednesday and no order.
  static let vietnameseWeekdayNamesInList = vietnameseWeekdayNamePattern(strictWednesday: false)

  private static func vietnameseWeekdayNamePattern(strictWednesday: Bool) -> String {
    let thu = vietnameseWord("thứ")
    let names =
      "(?:\(vietnameseAlternation(["hai", "ba", "năm", "sáu", "bảy"]))|\(vietnameseWord("tư", strict: strictWednesday)))"
    return "(?:\(thu)\\s+(?:\(names)|[2-7](?!\\p{N}))|\(vietnameseAlternation(["chủ nhật", "chúa nhật"])))"
  }

  /// The weekday a matched phrase names, 0 = Sunday: the name, with the words that
  /// introduce it or follow it ignored.
  static func vietnameseWeekdayIndex(_ phrase: String) -> Int? {
    let tokens = vietnameseKey(phrase).split(separator: " ").map(String.init)
    if tokens.contains("nhat"), tokens.contains(where: { $0 == "chu" || $0 == "chua" }) { return 0 }
    guard let thu = tokens.firstIndex(of: "thu"), thu + 1 < tokens.count else { return nil }
    switch tokens[thu + 1] {
    case "hai": return 1
    case "ba": return 2
    case "tu": return 3
    case "nam": return 4
    case "sau": return 5
    case "bay": return 6
    default: return Int(tokens[thu + 1]).flatMap { (2...7).contains($0) ? $0 - 1 : nil }
    }
  }

  /// The words after which "thứ" and a number or a name is an ordinal of the thing
  /// the word names ("lần thứ hai" is the second time, "màn hình thứ hai" the
  /// second screen), not a weekday.
  private static let vietnameseOrdinalNouns = VietnameseWordSet([
    "lần", "bước", "phần", "chương", "tập", "bài", "trang", "dòng", "hàng", "cột", "tầng", "lầu", "vòng", "hiệp",
    "hạng", "giải", "người", "con", "cái", "chiếc", "cuốn", "quyển", "ngăn", "ổ", "đợt", "kỳ", "ca", "tiết", "câu",
    "mục", "điều", "khoản", "ngày", "tuần", "tháng", "năm", "lớp", "bản", "đứa", "bé", "ly", "cốc", "tách", "chén",
    "hình", "sổ", "lượt", "trận", "tuổi", "thế hệ", "đời", "cấp", "loại",
  ])

  /// The words that follow a weekday and set its week or put it in the past, as a
  /// pattern without groups: "này", "tuần này", "tuần sau", "tuần tới", "tới",
  /// "trước", "tuần trước", "tuần qua", "rồi", "vừa rồi". Directly after a weekday
  /// "tới" needs its mark, since "thứ Hai toi" is "thứ Hai tối" (Monday evening).
  static let vietnameseWeekdaySuffix: String = {
    let week = vietnameseWord("tuần")
    let this = vietnameseWord("này")
    let past = vietnameseAlternation(["trước", "qua", "rồi"])
    return
      #"(?:\s+\#(week)\s+(?:\#(this)|sau|\#(vietnameseWord("tới"))|\#(past))|\s+(?:\#(this)|\#(vietnameseWord("tới", strict: true))|\#(past)|\#(vietnameseWord("vừa rồi"))))"#
  }()

  /// "Thứ Bảy và Chủ nhật" (the weekend), as a pattern without groups.
  private static let vietnameseWeekendPair =
    #"\#(vietnameseWord("thứ bảy"))\s*(?:\#(vietnameseWord("và"))|,|&)\s*\#(vietnameseAlternation(["chủ nhật", "chúa nhật"]))"#

  /// The separators of a list of weekdays: a comma, "và", "hoặc", "hay", "&", "/".
  private static let vietnameseListSeparator =
    #"\s*(?:,\s*\#(vietnameseAlternation(["và", "hoặc", "hay"]))|,|\#(vietnameseAlternation(["và", "hoặc", "hay"]))|&|/)\s*"#

  /// Whether the weekday `match` names stands in a list of weekdays ("thứ Hai và
  /// thứ Tư", "thứ Ba hoặc thứ Năm", "thứ Hai, thứ Tư"): a list names no one day,
  /// so none of its weekdays is read and the whole list stays in the title. "Thứ
  /// Bảy và Chủ nhật" is the weekend, which a rule of its own reads first.
  private static func vietnameseIsInWeekdayList(_ match: Match) -> Bool {
    let names = vietnameseWeekdayNamesInList
    let part = #"(?:\s+\#(vietnameseBuoi)\#(vietnameseDayParts))?"#
    return vietnameseFinds(#"^\#(vietnameseListSeparator)\#(names)\#(vietnameseEnd)"#, in: vietnameseTextAfter(match))
      || vietnameseFinds(
        #"\#(vietnameseStart)\#(names)\#(part)\#(vietnameseListSeparator)$"#, in: vietnameseTextBefore(match))
  }

  /// Days from today to `weekday` (0 = Sunday) of the current week, weeks starting
  /// on Monday, or nil when that day has passed.
  private static func thisWeekOffset(_ weekday: Int, todayWeekday: Int) -> Int? {
    let todayFromMonday = (todayWeekday + 5) % 7
    let weekdayFromMonday = (weekday + 6) % 7
    return weekdayFromMonday >= todayFromMonday ? weekdayFromMonday - todayFromMonday : nil
  }

  // MARK: - Months and dates

  /// A day with its month and maybe a year, as a pattern without groups and with
  /// no condition on what comes before it: "15 tháng 10", "ngày 15 tháng 10", "15
  /// thg 10", "15 tháng 10 năm 2026", "15 tháng 10, 2026". A date followed by a
  /// unit ("5 tháng 3 ngày" is 5 months and 3 days) is no date.
  private static var vietnameseMonthDateBody: String {
    let month = #"(?:\#(vietnameseWord("tháng"))|thg\.?)"#
    let year = #"(?:\s*,?\s*(?:\#(vietnameseWord("năm"))\s+)?(?:19|20)\d{2}(?!\p{N}))?"#
    let units = vietnameseAlternation(["ngày", "tuần", "tháng", "năm", "tiếng", "giờ", "phút", "lần", "người", "tuổi"])
    return
      #"(?:\#(vietnameseWord("ngày"))\s+)?\d{1,2}\s*\#(month)\s*(?:1[0-2]|[1-9])(?!\p{N})\#(year)(?!\s*\#(units)\#(vietnameseEnd))"#
  }

  /// A day with its month: "15 tháng 10", "ngày 15 tháng 10 năm 2026", "15 thg 10".
  static var vietnameseMonthDatePattern: String {
    #"(?<![\p{Latin}\p{N}\p{M}.,:/-])\#(vietnameseMonthDateBody)"#
  }

  /// "15/10/2026", "15-10-2026", "15.10.2026", "15/10/26": a day, a month, and a
  /// year in digits, which nothing else reads as.
  static let vietnameseNumericDatePattern =
    #"(?<![\p{Latin}\p{N}\p{M}.,:/-])\d{1,2}[./-]\d{1,2}[./-](?:\d{4}|\d{2})(?![\p{N}]|[.,/]\p{N})"#

  /// "15/10", "15-10": a day and a month in digits with no year, which a date reads
  /// only after a word that introduces it ("ngày 15/10", "vào 15/10", "trước
  /// 15/10"), since "1/2", "24/7", and "3-4 ngày" are other things.
  static let vietnameseLooseDatePattern =
    #"(?<![\p{N}.,:/-])\d{1,2}[/-]\d{1,2}(?![\p{N}]|[.,/]\p{N}|[-–]\p{N})(?!\s*\#(vietnameseAlternation(["giờ", "phút", "ngày", "tuần", "tháng", "năm", "lần", "người", "cái", "kg", "km", "cm", "mm", "tiếng", "tuổi"]))\#(vietnameseEnd))"#

  /// "ngày 15": a day of the month with no month, read as this month's or, once
  /// passed, next month's. It may not follow a word that makes "ngày" a rate ("mỗi
  /// ngày 2 lần"), be followed by a count unit ("ngày 2 lần", "ngày 3 buổi") or a
  /// colon ("Ngày 1: chuẩn bị"), or go on as a list or a range of days.
  static let vietnameseDayOfMonthPattern: String = {
    let rateWords = vietnameseAlternation(["mỗi", "hằng", "hàng", "mọi", "một"])
    let units = vietnameseAlternation([
      "lần", "lượt", "buổi", "bữa", "ly", "cốc", "chén", "viên", "gói", "người", "cái", "tiếng", "giờ", "phút", "trang",
      "tiết", "ca", "trận", "vòng", "bước", "kg", "cm", "km", "tuổi", "tháng", "x", "l",
    ])
    return
      #"(?<!\#(rateWords)\s{1,3})\#(vietnameseStart)\#(vietnameseWord("ngày"))\s+\d{1,2}(?![\p{N}%/]|[.,:]\p{N})(?!\s*:)(?!\s*[-–—/,&]\s*\d)(?!\s*\#(vietnameseAlternation(["đến", "tới", "và", "hoặc"]))\s*(?:\#(vietnameseWord("ngày"))\s+)?\d)(?!\s*\#(units)\#(vietnameseEnd))"#
  }()

  /// A date written in digits, or with its month name, as the pattern of one date
  /// alternative: the lead that makes the short "15/10" a date and the weekday
  /// before the date ("thứ Sáu 16 tháng 10") are part of it.
  private static let vietnameseWeekdayBeforeDate = #"(?:\#(vietnameseWeekdayNames)\s*,?\s+)"#

  /// A written-out date and whether it is written in digits only.
  private struct VietnameseWrittenDate {
    var date: ExplicitDate
    var isNumeric: Bool
  }

  /// The date a day phrase names, in the phrase as ``vietnameseKey(_:)`` leaves it.
  private static func vietnameseExplicitDate(_ key: String) -> VietnameseWrittenDate? {
    guard key.contains(where: \.isNumber) else { return nil }
    if let found = key.firstMatch(of: /(\d{1,2}) ?(?:thang|thg\.?) ?(\d{1,2})(?:,? ?(?:nam )?((?:19|20)\d{2}))?/),
      let day = number(found.output.1), let month = number(found.output.2)
    {
      return VietnameseWrittenDate(
        date: ExplicitDate(year: found.output.3.flatMap { number($0) }, month: month, day: day), isNumeric: false)
    }
    if let found = key.firstMatch(of: /(\d{1,2})[.\/-](\d{1,2})(?:[.\/-](\d{4}|\d{2})(?!\d))?/),
      let day = number(found.output.1), let month = number(found.output.2)
    {
      let year = found.output.3.flatMap { number($0) }.map { $0 < 100 ? 2000 + $0 : $0 }
      return VietnameseWrittenDate(date: ExplicitDate(year: year, month: month, day: day), isNumeric: true)
    }
    if let found = key.firstMatch(of: /ngay (\d{1,2})/), let day = number(found.output.1) {
      return VietnameseWrittenDate(date: ExplicitDate(day: day), isNumeric: false)
    }
    return nil
  }

  // MARK: - Date range

  /// A side of a date range: a date with its month ("15 tháng 10"), a date in
  /// digits ("15/10"), or a day alone ("5", "ngày 5"). The end of a range may
  /// follow its dash directly ("5-7 tháng 10"), which a start may not.
  private static func vietnameseRangeSide(isEnd: Bool) -> String {
    let lookbehind = isEnd ? #"(?<![\p{N}.,:/])"# : #"(?<![\p{N}.,:/-])"#
    let bare = #"(?:\#(vietnameseWord("ngày"))\s+)?\d{1,2}\#(vietnameseNoMoreDigits)"#
    let numeric = #"\d{1,2}/\d{1,2}(?:/(?:\d{4}|\d{2}))?(?![\p{N}]|[.,/]\p{N})"#
    return #"\#(lookbehind)\#(vietnameseMonthDateBody)|\#(lookbehind)\#(numeric)|\#(lookbehind)\#(bare)"#
  }

  /// "từ ngày 3 đến ngày 5 tháng 5", "từ 3 đến 5 tháng 5", "3-5 tháng 5", "3 đến 5
  /// tháng 5", "từ ngày 3 tháng 5 đến ngày 5 tháng 5", "từ 3/5 đến 5/5", "giữa
  /// ngày 3 và ngày 5 tháng 5", each maybe with a year after the end. Groups: 1
  /// the word that opens the range, if any ("từ", "giữa"), 2 the start, 3 a dash
  /// between the sides, 4 the word between them ("đến", "tới", "và"), 5 the end.
  static var vietnameseDateRangePattern: String {
    let start = vietnameseRangeSide(isEnd: false)
    let end = vietnameseRangeSide(isEnd: true)
    let opener = vietnameseAlternation(["từ", "giữa"])
    let joiner = vietnameseAlternation(["đến", "tới", "và"])
    return
      #"\#(vietnameseStart)(?:(\#(opener))\s+)?(\#(start))(?:\s*([-–—])\s*|\s+(\#(joiner))\s+)(\#(end))(?![\p{Latin}\p{N}\p{M}]|[.,]\p{N})"#
  }

  static func vietnameseDateRange(_ match: Match) -> DayRangeReading? {
    guard let startText = match.group(2), let endText = match.group(5), let start = vietnameseRangeDate(startText),
      let end = vietnameseRangeDate(endText), end.date.month != nil
    else { return nil }
    let lead = match.group(1).map(vietnameseKey)
    let word = match.group(4).map(vietnameseKey)
    // "Và" joins the sides after "giữa" only, and "giữa" takes no other joiner.
    if (lead == "giua") != (word == "va") { return nil }
    // A date in digits with no month ("15/10") needs the opening word, since "3/4 - 5/6" may be fractions.
    if start.isNumeric || end.isNumeric, lead == nil { return nil }
    // A start that is a day alone with a dash and no opening word reads only when the dash touches
    // both sides ("5-7 tháng 10"): "Sprint 12 - 20 tháng 5" names a sprint and a date.
    if word == nil, start.date.month == nil, lead == nil, !dashTouchesBothSides(match, start: 2, end: 5) {
      return nil
    }
    return dayRangeReading(from: start.date, to: end.date, today: match.today)
  }

  /// A side of a date range as a date: with its month, or a day alone, which has no
  /// month.
  private static func vietnameseRangeDate(_ text: String) -> VietnameseWrittenDate? {
    let key = vietnameseKey(text)
    if let found = vietnameseExplicitDate(key), found.date.month != nil { return found }
    guard let day = key.wholeMatch(of: /(?:ngay )?(\d{1,2})/), let value = number(day.output.1) else { return nil }
    return VietnameseWrittenDate(date: ExplicitDate(day: value), isNumeric: false)
  }

  /// "từ thứ Hai đến thứ Sáu", "thứ 2 đến thứ 6", "thứ Hai - thứ Sáu", "từ thứ Tư tới
  /// Chủ nhật": a span of weekdays. Groups: 1 "từ", 2 and 5 the first and the last
  /// weekday, 3 the word between them, 4 a dash.
  static var vietnameseWeekdayRangePattern: String {
    let day = vietnameseWeekdayNamesInList
    let joiner = vietnameseAlternation(["đến", "tới"])
    return
      #"\#(vietnameseStart)(?:(\#(vietnameseWord("từ")))\s+)?(\#(day))(?:\s+(\#(joiner))\s+|\s*([-–—])\s*)(\#(day))\#(vietnameseEnd)"#
  }

  /// A span of weekdays plans the coming first day and is due on the first last day
  /// after it, so on a Tuesday "thứ Tư đến thứ Sáu" runs from tomorrow to Friday
  /// and "thứ Hai đến thứ Tư" from next Monday to the Wednesday after it, where
  /// reading the two weekdays apart would plan next Monday and make the task due
  /// tomorrow. A span after "mỗi", "hằng", or "hàng", or before "hằng tuần",
  /// repeats, which the repeat rules read, and a span from a day to itself is no
  /// span.
  static func vietnameseWeekdayRange(_ match: Match) -> DayRangeReading? {
    guard let firstText = match.group(2), let lastText = match.group(5), let first = vietnameseWeekdayIndex(firstText),
      let last = vietnameseWeekdayIndex(lastText), first != last, !vietnameseIsRepeatSpan(match),
      !vietnameseIsOrdinalNoun(wordBefore(match))
    else { return nil }
    let start = comingWeekdayOffset(first, todayWeekday: match.todayWeekday)
    return .range(DayRange(start: start, end: start + (last - first + 7) % 7))
  }

  /// Whether `match` is a span of weekdays a repeat names: "mỗi thứ Hai đến thứ Sáu",
  /// "hằng ngày từ thứ Hai đến thứ Sáu", "từ thứ Hai đến thứ Sáu hàng tuần".
  private static func vietnameseIsRepeatSpan(_ match: Match) -> Bool {
    let every = vietnameseAlternation(["mỗi", "hằng", "hàng", "mọi"])
    let unit = vietnameseAlternation(["ngày", "tuần"])
    return vietnameseFinds(#"(?:^|\s)\#(every)(?:\s+\#(unit)(?:\s+\#(vietnameseWord("vào")))?)?\s*$"#, in: vietnameseTextBefore(match))
      || vietnameseFinds(#"^\s*\#(every)\s+\#(unit)\#(vietnameseEnd)"#, in: vietnameseTextAfter(match))
  }

  /// Whether `word`, the word before a weekday name, makes the name an ordinal
  /// ("lần thứ hai").
  private static func vietnameseIsOrdinalNoun(_ word: String?) -> Bool {
    guard let word else { return false }
    return vietnameseOrdinalNouns.contains(word)
  }

  /// The word just before the day phrase (group 1) of a due or day match, lowercased:
  /// for a due match, the last word of its lead ("hết" in "đến hết thứ Sáu"), so the
  /// word before the lead ("bài" in "Nộp bài đến hết thứ Sáu") is not taken for the
  /// noun of an ordinal.
  private static func vietnameseWordBeforeDay(_ match: Match) -> String? {
    let range = match.result.range(at: 1)
    guard range.location != NSNotFound, let start = Range(range, in: match.source)?.lowerBound else {
      return wordBefore(match)
    }
    let word = match.source[..<start].reversed().drop(while: \.isWhitespace).prefix(while: \.isLetter)
    return word.isEmpty ? nil : String(word.reversed()).lowercased()
  }

  // MARK: - Due day

  /// The words that introduce a due day, as a pattern without groups: "trước",
  /// "hạn", "hạn chót", "hạn cuối", "hạn nộp", "hết hạn", "đến hạn", "deadline",
  /// "đến", "đến hết", "tới", "cho đến", "chậm nhất", "muộn nhất", each with its
  /// colon or space and maybe "vào" after it. "Tới" needs its mark: "toi" is also
  /// "tối" (evening) and "tôi" (I). "Tới" after "tuần" is next week ("tuần tới thứ
  /// Hai"), no word that introduces a day.
  static let vietnameseDueLead: String = {
    let words = vietnameseAlternation([
      "trước", "hạn chót", "hạn cuối cùng", "hạn cuối", "hạn nộp", "hạn hoàn thành", "hết hạn", "đến hạn", "hạn",
      "đến hết", "đến", "cho đến", "cho tới", "chậm nhất là", "chậm nhất", "muộn nhất là", "muộn nhất", "trễ nhất là",
      "trễ nhất",
    ])
    let until = #"(?<!\#(vietnameseNounBeforeNext)\s{1,3})\#(vietnameseWord("tới", strict: true))"#
    return #"(?:\#(words)|deadline|\#(until))(?:\s*:\s*|\s+)(?:\#(vietnameseWord("vào"))\s+)?"#
  }()

  /// "Hôm nay" and "ngày hôm nay", as a pattern without groups.
  private static let vietnameseToday = #"(?:\#(vietnameseWord("ngày"))\s+)?\#(vietnameseWord("hôm nay"))"#

  /// The days a due phrase may name, as a pattern without groups: hôm nay, ngày
  /// mai, ngày kia, a part of the day with nay or mai, a weekday (maybe with a
  /// week or a part of the day), and a date. The weekend, next week, and a count of
  /// days are no due day.
  static var vietnameseDueDay: String {
    let names = vietnameseWeekdayNames
    let part = vietnameseDayParts
    let alternatives = [
      vietnameseToday,
      #"\#(vietnameseWord("ngày"))\s+(?:\#(vietnameseWord("mai"))|kia|\#(vietnameseWord("mốt", strict: true)))"#,
      #"\#(vietnameseBuoi)\#(vietnameseNotNounBeforePart)\#(part)\s+(?:mai|\#(vietnameseWord("nay")))"#,
      #"\#(vietnameseWeekdayBeforeDate)(?:\#(vietnameseMonthDatePattern)|\#(vietnameseNumericDatePattern)|\#(vietnameseLooseDatePattern))"#,
      #"\#(vietnameseBuoi)\#(vietnameseNotNounBeforePart)\#(part)\s+\#(names)\#(vietnameseWeekdaySuffix)?"#,
      #"\#(names)\#(vietnameseWeekdaySuffix)?(?:\s+\#(vietnameseBuoi)\#(part))?"#,
      vietnameseMonthDatePattern, vietnameseNumericDatePattern, vietnameseLooseDatePattern,
      vietnameseDayOfMonthPattern,
    ]
    return alternatives.joined(separator: "|")
  }

  /// "trước thứ Sáu", "hạn chót 15 tháng 10", "đến ngày mai", "hạn thứ Sáu tuần sau",
  /// "deadline 15/10", "chậm nhất chiều thứ Sáu". Group 1: the day after a word
  /// that introduces it.
  static var vietnameseDuePattern: String {
    #"\#(vietnameseStart)\#(vietnameseDueLead)(\#(vietnameseDueDay))\#(vietnameseEnd)"#
  }

  static func vietnameseDue(_ match: Match) -> Day? {
    match.group(1).flatMap { vietnameseDay($0, in: match) }.map { Day(offset: $0.offset) }
  }

  // MARK: - Planned day

  /// "hôm nay", "sáng nay", "tối nay", "đêm nay", "ngày mai", "sáng mai", "chiều
  /// mai", "ngày kia", "tuần sau", "cuối tuần", "3 ngày nữa", "sau 3 ngày", "1 tuần
  /// nữa", a weekday ("thứ Hai", "thứ Hai tuần này", "thứ Hai tuần sau", "chiều thứ
  /// Sáu", "thứ Sáu chiều", "thứ Bảy và Chủ nhật"), and a date, maybe with its
  /// weekday ("ngày 15 tháng 10", "thứ Sáu 16/10", "ngày 15"), any of them maybe
  /// after "vào" ("vào ngày mai", "vào thứ Hai", "vào 15/10"). Group 1: the day,
  /// with the words that introduce it.
  static var vietnameseWhenPattern: String {
    let names = vietnameseWeekdayNames
    let part = vietnameseDayParts
    let buoi = vietnameseBuoi
    let vao = #"(?:\#(vietnameseWord("vào"))\s+)?"#
    let count = #"(?:\d{1,3}|\#(vietnameseNumberWords))"#
    let week = vietnameseWord("tuần")
    let weekend =
      #"\#(vao)\#(vietnameseWord("cuối tuần"))(?:\s+(?:\#(vietnameseWord("này"))|\#(vietnameseWord("tới", strict: true))|sau|\#(vietnameseAlternation(["trước", "qua", "rồi", "vừa rồi"]))))?"#
    let counts = [
      #"\#(count)\s+(?:\#(vietnameseWord("ngày"))|\#(week))\s+(?:\#(vietnameseWord("nữa"))|sau)(?!\s+(?:khi|\#(vietnameseAlternation(["làm việc", "là"]))))"#,
      #"sau\s+\#(count)\s+(?:\#(vietnameseWord("ngày"))|\#(week))(?!\s+(?:\#(vietnameseAlternation(["làm việc", "nữa", "trước", "qua", "kể", "nay", "tới"]))))"#,
    ]
    let today = [
      #"\#(vao)\#(vietnameseToday)"#,
      #"\#(vao)\#(buoi)\#(vietnameseNotNounBeforePart)\#(part)\s+\#(vietnameseWord("nay"))"#,
    ]
    let tomorrow = [
      #"\#(vao)\#(vietnameseWord("ngày mai"))"#, #"\#(vao)\#(buoi)\#(vietnameseNotNounBeforePart)\#(part)\s+mai"#,
      #"\#(vao)\#(vietnameseWord("ngày"))\s+(?:kia|\#(vietnameseWord("mốt", strict: true)))"#, vietnameseDayAfterNounPart,
    ]
    let strict = #"\#(vietnameseMonthDatePattern)|\#(vietnameseNumericDatePattern)"#
    let looseLead = #"(?:\#(vietnameseWord("vào"))\s+(?:\#(vietnameseWord("ngày"))\s+)?|\#(vietnameseWord("ngày"))\s+)"#
    let alternatives =
      [weekend] + counts + today + tomorrow + [
        #"\#(vao)(?:\#(vietnameseWeekdayBeforeDate))?(?:\#(strict))"#,
        #"\#(looseLead)(?:\#(vietnameseWeekdayBeforeDate))?\#(vietnameseLooseDatePattern)"#,
        #"\#(vietnameseWeekdayBeforeDate)\#(vietnameseLooseDatePattern)"#,
        #"\#(vao)\#(vietnameseDayOfMonthPattern)"#,
        #"\#(vao)\#(vietnameseWeekendPair)"#,
        #"\#(vao)\#(buoi)\#(vietnameseNotNounBeforePart)\#(part)\s+\#(names)\#(vietnameseWeekdaySuffix)?"#,
        #"\#(vao)\#(names)\#(vietnameseWeekdaySuffix)?(?:\s+\#(buoi)\#(part))?"#,
        #"\#(vao)\#(week)\s+(?:\#(vietnameseWord("này"))|sau|\#(vietnameseWord("tới")))\s*,?\s+\#(names)(?:\s+\#(buoi)\#(part))?"#,
        #"\#(vao)\#(week)\s+(?:sau|\#(vietnameseWord("tới")))(?!\s+khi)"#,
      ]
    return #"\#(vietnameseStart)(\#(alternatives.joined(separator: "|")))\#(vietnameseEnd)"#
  }

  static func vietnameseWhen(_ match: Match) -> Day? {
    match.group(1).flatMap { vietnameseDay($0, in: match) }
  }

  /// The words after which a day is left out of a phrase or only added to it, not
  /// named ("hằng ngày trừ Chủ nhật", "mỗi ngày kể cả Chủ nhật"), as keys.
  private static let vietnameseExceptWords: Set<String> = ["tru", "ngoai", "ke", "ca"]

  /// The count of units a day phrase spells, in days: "3 ngày nữa", "sau 3 ngày", "2
  /// tuần nữa", "một tuần sau".
  private static func vietnameseCountedDays(_ key: String) -> Int? {
    func days(_ count: Int, _ unit: Substring) -> Int { unit == "ngay" ? count : count * 7 }
    if let found = key.wholeMatch(of: /(?:vao )?(\d{1,3}|[a-z]+(?: [a-z]+){0,2}) (ngay|tuan) (?:nua|sau)/),
      let count = vietnameseCount(String(found.output.1))
    {
      return days(count, found.output.2)
    }
    if let found = key.wholeMatch(of: /(?:vao )?sau (\d{1,3}|[a-z]+(?: [a-z]+){0,2}) (ngay|tuan)/),
      let count = vietnameseCount(String(found.output.1))
    {
      return days(count, found.output.2)
    }
    return nil
  }

  /// Whether a part of the day in a phrase makes it an evening: "tối", "đêm", "khuya",
  /// where "toi" typed with no mark after "tuần" is "tuần tới" and one typed with
  /// "tới" is no part of the day.
  private static func vietnameseIsEvening(typed: [String], keys: [String]) -> Bool {
    typed.indices.contains { index in
      switch keys[index] {
      case "dem", "khuya": return true
      case "toi": return typed[index] == "tối" || (typed[index] == "toi" && !(index > 0 && keys[index - 1] == "tuan"))
      default: return false
      }
    }
  }

  /// Whether a count stands right before `match`: "3 ngày 2 đêm" is three days and
  /// two nights, so its "ngày 2" is no day of the month. A number after "thứ" is a
  /// weekday ("thứ 6 ngày 16"), no count.
  private static func vietnameseFollowsCount(_ match: Match) -> Bool {
    vietnameseFinds(
      #"(?<![\p{Latin}\p{N}\p{M}])(?<!\#(vietnameseWord("thứ"))\s{1,3})(?:\d{1,3}|\#(vietnameseNumberWords))\s{1,3}$"#,
      in: vietnameseTextBefore(match))
  }

  /// The day a phrase names: the phrase of a rule's match, with the words that
  /// introduce it. Nil when the phrase names no day, a past one ("thứ Hai tuần
  /// trước"), or this week's weekday that has passed, follows "trừ", or is an
  /// ordinal ("lần thứ hai") or one weekday of a list.
  private static func vietnameseDay(_ phrase: String, in match: Match) -> Day? {
    let wordBeforeDay = vietnameseWordBeforeDay(match)
    if let before = wordBeforeDay.map(vietnameseKey), vietnameseExceptWords.contains(before) { return nil }
    let key = vietnameseKey(phrase)
    if let found = vietnameseExplicitDate(key) {
      if found.date.month == nil, vietnameseFollowsCount(match) { return nil }
      guard let today = match.today, let days = offset(to: found.date, from: today) else { return nil }
      return Day(offset: days)
    }
    if let days = vietnameseCountedDays(key) { return Day(offset: days) }
    let typed = vietnameseTypedWords(phrase)
    let tokens = typed.map(vietnameseKey)
    if tokens.contains(where: { ["truoc", "qua", "roi", "vua"].contains($0) }) { return nil }
    let isEvening = vietnameseIsEvening(typed: typed, keys: tokens)
    let todayWeekday = match.todayWeekday
    // "Sau" and "tới" mean next week only right after "tuần": "thứ Sáu" has "sau" in it too.
    let isNextWeek = tokens.firstIndex(of: "tuan").map { $0 + 1 < tokens.count && ["sau", "toi"].contains(tokens[$0 + 1]) } ?? false
    if let first = tokens.firstIndex(of: "cuoi"), first + 1 < tokens.count, tokens[first + 1] == "tuan" {
      let weekend = weekendOffset(todayWeekday: todayWeekday)
      return Day(offset: isNextWeek ? weekend + 7 : weekend)
    }
    if tokens.contains("bay"), tokens.contains("nhat") {
      return Day(offset: weekendOffset(todayWeekday: todayWeekday))
    }
    if let weekday = vietnameseWeekdayIndex(phrase) {
      if vietnameseIsInWeekdayList(match) { return nil }
      if tokens.first == "thu", vietnameseIsOrdinalNoun(wordBeforeDay) { return nil }
      if tokens.contains("tuan") {
        if isNextWeek {
          return Day(offset: nextWeekOffset(weekday, todayWeekday: todayWeekday), isEvening: isEvening)
        }
        guard let days = thisWeekOffset(weekday, todayWeekday: todayWeekday) else { return nil }
        return Day(offset: days, isEvening: isEvening)
      }
      if tokens.contains("nay") {
        return Day(offset: weekdayDelta(weekday, todayWeekday: todayWeekday), isEvening: isEvening)
      }
      return Day(offset: comingWeekdayOffset(weekday, todayWeekday: todayWeekday), isEvening: isEvening)
    }
    if isNextWeek { return Day(offset: 7) }
    if tokens.contains("kia") || (tokens.contains("ngay") && tokens.contains("mot")) { return Day(offset: 2) }
    // "Mai" after a part of the day that forms a noun with the word before it has the part left out
    // of the match, so the evening is judged by the text before.
    let isEveningBefore = vietnameseFinds(
      #"(?:^|\s)\#(vietnameseAlternation(["tối", "đêm", "khuya"]))\s*$"#, in: vietnameseTextBefore(match))
    if tokens.contains("mai") { return Day(offset: 1, isEvening: isEvening || isEveningBefore) }
    if tokens.contains("hom") || tokens.contains("nay") { return Day(offset: 0, isEvening: isEvening || isEveningBefore) }
    return nil
  }

  // MARK: - Text that names no day

  /// "thứ Hai đầu tiên của tháng", "mỗi thứ Sáu cuối cùng của tháng", "thứ Ba thứ
  /// hai trong tháng": a weekday by its place in the month. The repeat has no such
  /// rule and no day rule can name it, so the text stays in the title whole, with
  /// no part of it read as a weekday.
  static let vietnameseOrdinalWeekdayPattern: String = {
    let place = vietnameseAlternation(["đầu tiên", "cuối cùng", "đầu", "cuối"])
    let ordinal = "(?:\(vietnameseWord("thứ"))\\s+(?:\(vietnameseAlternation(["hai", "ba", "bốn", "tư"]))|[2-4]))"
    return
      #"\#(vietnameseStart)(?:\#(vietnameseAlternation(["mỗi", "hằng", "hàng"]))\s+)?\#(vietnameseWeekdayNames)\s+(?:\#(place)|\#(ordinal))\s+(?:\#(vietnameseAlternation(["của", "trong"]))\s+)?(?:\#(vietnameseWord("mỗi"))\s+)?\#(vietnameseWord("tháng"))\#(vietnameseEnd)"#
  }()

  /// "Thứ Sáu đen" (Black Friday), "Thứ Sáu Tuần Thánh", "Chủ nhật Phục Sinh", "Chủ
  /// nhật Lễ Lá": the name of a day, which names no day to plan, so the whole name
  /// stays in the title.
  static let vietnameseNamedWeekdayPattern: String = {
    // "Đen" is read with its stroke only: "den" is also "đến" of "thứ Hai đến thứ Sáu".
    let black = vietnameseWord("đen", strict: true)
    let others = vietnameseAlternation(["tuần thánh", "phục sinh", "lễ lá"])
    return #"\#(vietnameseStart)\#(vietnameseWeekdayNames)\s+(?:\#(black)|\#(others))\#(vietnameseEnd)"#
  }()

  /// "trước cuối tuần", "đến cuối tuần", "sau cuối tuần", "cho cuối tuần", "trong
  /// cuối tuần", "cuối tuần trước", "trước tuần sau", "cho tuần tới", "trong 3 ngày
  /// nữa": a bound at a period, a period a task is for, or a past weekend. None
  /// names a day the planner can set, so the whole phrase stays in the title,
  /// where the period would otherwise be planned with the preposition left behind.
  static let vietnameseBoundedPeriodPattern: String = {
    // "Tới" is read with its mark, and "sau" not after "thứ": "toi" is "tôi" (I), and "thu Sau" is Friday
    // typed without marks ("thu Sau tuan sau" is Friday next week).
    let lead = "(?:" + [
      vietnameseAlternation(["trước", "đến", "cho đến", "qua", "hết", "cho", "trong"]),
      vietnameseAlternation(["tới", "cho tới"], strict: true),
      #"(?<!\#(vietnameseWord("thứ"))\s{1,3})sau"#,
    ].joined(separator: "|") + ")"
    let weekend = vietnameseWord("cuối tuần")
    let week = vietnameseWord("tuần")
    let next = #"(?:sau|\#(vietnameseWord("tới")))"#
    let count = #"(?:\d{1,3}|\#(vietnameseNumberWords))"#
    let periods = [
      #"\#(weekend)(?:\s+(?:\#(vietnameseWord("này"))|\#(next)))?"#,
      #"\#(week)\s+\#(next)"#,
      #"\#(count)\s+(?:\#(vietnameseWord("ngày"))|\#(week))\s+(?:\#(vietnameseWord("nữa"))|sau)"#,
    ]
    let after = vietnameseAlternation(["trước", "qua", "rồi", "vừa rồi"])
    return
      #"\#(vietnameseStart)(?:\#(lead)\s+(?:\#(periods.joined(separator: "|")))|\#(weekend)\s+\#(after))\#(vietnameseEnd)"#
  }()

  /// A date of the lunar calendar, which is no day of the calendar the planner
  /// counts in: "15 tháng 8 âm lịch", "ngày 15/8 âm", "15/8 AL", "âm lịch 15/8",
  /// "mùng 5 tháng 10", "mồng 1". Vietnamese people note the dates of Tết, the
  /// full moon, and death anniversaries by the lunar calendar, so a date that
  /// names it stays in the title whole. "Mùng" and "mồng" count the first ten
  /// days of a lunar month. "Âm" alone is read with its mark: "am" is also the
  /// English "am" of a clock time.
  static let vietnameseLunarDatePattern: String = {
    let month = #"(?:\#(vietnameseWord("tháng"))|thg\.?)"#
    let lunar =
      #"(?:\#(vietnameseWord("âm lịch"))|\#(vietnameseWord("âm", strict: true))|(?-i:ÂL|AL)(?![\p{Latin}\p{N}\p{M}]))"#
    let day = #"(?:\#(vietnameseWord("ngày"))\s+)?\d{1,2}"#
    let date = #"\#(day)(?:\s*\#(month)\s*(?:1[0-2]|[1-9])|\s*[/-]\s*(?:1[0-2]|[1-9]))(?!\p{N})(?:\s*,?\s*(?:\#(vietnameseWord("năm"))\s+)?(?:19|20)\d{2}(?!\p{N}))?"#
    let counted = #"\#(vietnameseAlternation(["mùng", "mồng", "mống"]))\s+\d{1,2}(?!\p{N})(?:\s*\#(month)\s*(?:1[0-2]|[1-9])(?!\p{N}))?"#
    return
      #"\#(vietnameseStart)(?:\#(date)\s*\(?\s*\#(lunar)\)?|\#(lunar)\s*:?\s*\#(date)|\#(counted))\#(vietnameseEnd)"#
  }()

  /// "3 tuần tới", "2 ngày tới", "6 tháng tới": the next days, weeks, or months, a
  /// span no day names, so the "tuần tới" in it is not next week.
  static let vietnameseNextSpanPattern =
    #"\#(vietnameseStart)(?<!\#(vietnameseWord("thứ"))\s{1,3})(?:\d{1,3}|\#(vietnameseNumberWords))\s+\#(vietnameseAlternation(["tuần", "ngày", "tháng"]))\s+\#(vietnameseWord("tới"))\#(vietnameseEnd)"#
}

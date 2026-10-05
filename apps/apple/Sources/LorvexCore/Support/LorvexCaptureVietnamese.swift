import Foundation

extension LorvexCaptureVocabulary {
  /// Vietnamese, read for a user who reads Vietnamese. The words are written in the
  /// patterns with their tone marks and vowel marks, and a line may be typed with
  /// every mark, with none ("ngay mai", "thu hai", "3 gio chieu"), or with the stroke
  /// of "đ" written as "d"; a letter's marks may be composed or typed as combining
  /// characters. A word is read in one of those spellings whole: "đem" (to bring) is
  /// not "đêm" (night), "tôi" (I) is not "tối" (evening) or "tới" (next), and "Tuấn"
  /// (a name) is not "tuần" (week). A few words are read only with their marks
  /// because their toneless spelling is another everyday word ("tư" for Wednesday
  /// is "tu" toneless, which is also "tự"). A word needs a boundary of Latin
  /// letters, digits, and combining marks on both sides. The title keeps what was
  /// typed, with the marks it was typed with.
  ///
  /// - Day: hôm nay, ngày hôm nay, sáng nay, trưa nay, chiều nay, tối nay, đêm
  ///   nay, khuya nay, ngày mai, sáng mai, trưa mai, chiều mai, tối mai, đêm mai
  ///   (each part of the day maybe after "buổi"), ngày kia, ngày mốt (each of
  ///   these maybe after "vào": "vào ngày mai"), 3 ngày nữa, sau 3 ngày, ba ngày
  ///   nữa, 2 tuần nữa, sau 2 tuần, tuần sau, tuần tới, cuối tuần (also "cuối
  ///   tuần này", "cuối tuần sau"), the weekday names (thứ Hai, thứ Ba, thứ Tư,
  ///   thứ Năm, thứ Sáu, thứ Bảy, Chủ nhật, and thứ 2 to thứ 7: alone, after
  ///   "vào", with a part of the day before or after it ("chiều thứ Sáu", "thứ
  ///   Sáu chiều"), or with "tuần này", "tuần sau", or "tuần tới" after or before
  ///   it: "thứ Sáu tuần sau", "tuần sau thứ Sáu"), thứ Bảy và Chủ nhật (the
  ///   weekend); a date: 15 tháng 10, ngày 15 tháng 10, 15 thg 10, 15 tháng 10 năm
  ///   2026, 15/10/2026, 15-10-2026, 15.10.2026, 15/10/26, and after "ngày" or
  ///   "vào" the short 15/10, each maybe after its weekday ("thứ Sáu 16 tháng
  ///   10"); a day of the month alone: "ngày 5", this month's or, once it has
  ///   passed, next month's. A weekday alone is the next such day, a full week
  ///   ahead when it names today; with "tuần này" it is this week's, and a day
  ///   that has passed is not read; with "tuần sau" or "tuần tới" it is next
  ///   week's, weeks starting on Monday. The weekend is the coming Saturday, and
  ///   "cuối tuần sau" the Saturday a week later. A date with no year is this
  ///   year's, or next year's once it has passed. A past day (hôm qua, hôm kia,
  ///   tối qua, sáng qua, tuần trước, tuần qua, thứ Hai tuần trước, cuối tuần
  ///   trước, 3 ngày trước) is never read, and neither are phrases whose day
  ///   cannot be named: a month or a year ahead ("tháng sau", "tháng tới", "năm
  ///   sau", "2 tháng nữa"), a count of working days ("3 ngày làm việc nữa"), a
  ///   list of weekdays ("thứ Hai và thứ Tư", "thứ Ba hoặc thứ Năm"), a bound at
  ///   a period or a period a task is for ("trước cuối tuần", "đến tuần sau",
  ///   "cho tuần tới", "trong 3 ngày nữa"), "3 tuần tới" (the next three weeks),
  ///   the short "15/10" with no word before it (a fraction or a score), a date
  ///   that does not exist ("30 tháng 2"), a day of the month right after a count
  ///   ("3 ngày 2 đêm" is three days and two nights), and the dates of the lunar
  ///   calendar ("15 tháng 8 âm lịch", "15/8 AL", "âm lịch 15/8", "mùng 5 tháng
  ///   10"). "Mai" alone is the name and the apricot blossom ("Họp Mai", "hoa
  ///   mai"), so it is the next day after "ngày" or a part of the day only, and
  ///   "mốt" alone ("Mốt Hoàng đến chơi") is read after "ngày" only.
  ///   The ordinals ("lần thứ hai", "màn hình thứ hai", "ngày thứ hai" which is the
  ///   second day, "thứ tự" which is an order), the abbreviations T2 to T7 and CN,
  ///   the names of days ("Thứ Sáu đen", "Chủ nhật Phục Sinh"), and a weekday by its
  ///   place in a month ("thứ Hai đầu tiên của tháng") are no days. A part of the day
  ///   that forms a noun with the word before it ("ăn tối", "bữa trưa", "ngủ trưa",
  ///   "lớp tối", "ca sáng") stays with that noun when a day follows: "Ăn tối mai"
  ///   is dinner tomorrow, and the title stays "Ăn tối".
  /// - Date range: từ ngày 3 đến ngày 5 tháng 5, từ 3 đến 5 tháng 5, 3-5 tháng 5,
  ///   từ 3 tháng 5 đến 5 tháng 5, từ 3/5 đến 5/5, giữa ngày 3 và ngày 5 tháng 5,
  ///   each maybe with a year after the end; from weekday to weekday: từ thứ Hai
  ///   đến thứ Sáu, thứ 2 đến thứ 6, thứ Hai - thứ Sáu. The first day is the planned
  ///   day and the last the due day.
  /// - Repeat: mỗi ngày, hằng ngày, hàng ngày, mỗi tuần, hằng tuần, hàng tuần, mỗi
  ///   tháng, hàng năm, mỗi quý, mỗi sáng, mỗi tối, mỗi thứ Hai, mọi thứ Hai, mỗi
  ///   thứ Ba và thứ Năm, mỗi thứ 2, 4, 6, thứ Hai hàng tuần, các thứ Hai, mỗi tuần
  ///   vào thứ Hai, mỗi thứ Hai đến thứ Sáu, mỗi cuối tuần, mỗi ngày làm việc, các
  ///   ngày làm việc, các ngày trong tuần, mỗi 2 ngày, mỗi hai tuần, cứ 3 tháng, 2
  ///   ngày một lần, 2 tuần/lần, cách ngày, cách tuần, một lần mỗi tuần, mỗi 2 tuần
  ///   vào thứ Ba, ngày 15 hàng tháng, mỗi tháng vào ngày 5. A count of times in a
  ///   period ("2 lần một tuần", "ngày 2 lần", "mỗi tuần ba lần"), an interval of
  ///   hours ("mỗi 2 giờ"), every day with a day left out ("mỗi ngày trừ Chủ
  ///   nhật"), "mỗi ngày thứ Sáu" (which may also be every sixth day), every
  ///   October ("mỗi tháng 10"), and a weekday by its place in the month name no
  ///   repeat the app can set and stay in the title.
  /// - Due: a day after trước, hạn, hạn chót, hạn cuối, hạn nộp, hết hạn, đến hạn,
  ///   deadline, đến, đến hết, tới, cho đến, chậm nhất, muộn nhất, or trễ nhất
  ///   ("trước thứ Sáu", "hạn chót 15/10", "đến hết hôm nay", "chậm nhất chiều thứ
  ///   Sáu"). A clock time after those words ("trước 5 giờ chiều", "chậm nhất
  ///   17h", "sau 18:00") is a bound that stays in the title, and the day before it
  ///   is the due day ("trước thứ Sáu 5 giờ chiều").
  /// - Time: 3 giờ chiều, lúc 3 giờ chiều, 3h chiều, 15h, 15h30, 15 giờ 30, 3 giờ
  ///   15 phút chiều, lúc 3 giờ rưỡi, 3 giờ kém 15, ba giờ chiều, 8 giờ tối, 12 giờ
  ///   đêm, nửa đêm, lúc 15.30, lúc 15:30, 9:30 sáng, 3:30 CH, 9:30 SA, lúc 3pm, 3
  ///   giờ đúng; a range: từ 3 giờ đến 5 giờ chiều, 3-5 giờ chiều, từ 14h đến 16h30,
  ///   14:00-16:00, giữa 3 giờ và 5 giờ chiều. A bare number of "giờ" is a clock
  ///   hour ("Họp 3 giờ" is 15:00), not a length: "giờ" is a length with "đồng
  ///   hồ" ("2 giờ đồng hồ"), after an opener that only a length has ("mất 2 giờ"),
  ///   or with minutes counted in "phút" when no part of the day or lead makes it
  ///   a clock and the hour is no more than 12 ("3 giờ 15 phút" is 3 hours 15
  ///   minutes, while "15 giờ 30 phút" and "18h30p" are clock times), while
  ///   "tiếng" is always a length. A time from 1 to 6 o'clock with no part of the
  ///   day is the afternoon, unless written with a leading zero, and a part of the
  ///   day or a meal beside an hour gives it its part ("tối 8 giờ", "ăn tối 7
  ///   giờ"). "Sáng" is 1 to 11 in the morning, "trưa" 10 to 12 and the early
  ///   afternoon, "chiều" the afternoon, "tối" the evening, "đêm" and "khuya" the
  ///   night; "12 giờ đêm", "12 giờ tối", and "nửa đêm" are midnight at the end of
  ///   the named day, which moves the planned day one day on, and "2 giờ đêm" is
  ///   02:00 of the next day. "Rưỡi" after an hour is the half hour ("3 giờ rưỡi"
  ///   is 3:30), and "kém" counts minutes before it ("3 giờ kém 15" is 2:45).
  ///   Minutes after "h" follow it directly ("15h30") or, with their unit, after a
  ///   space ("15h 30 phút"): a number after "h" and a space with no unit is the
  ///   next thing of the line ("18h 1 tiếng" is 18:00 and an hour). An hour
  ///   spelled as a word, an hour with "rưỡi" and no "giờ", and a dotted time need
  ///   a lead ("lúc") or a part of the day. "SA" and "CH", typed in capitals, are
  ///   the 12-hour clock's AM and PM that Apple's Vietnamese writes. An
  ///   approximate hour ("khoảng 3 giờ", "tầm 3 giờ") is as often a length and
  ///   stays in the title, and so does "12 giờ sáng" or "12 giờ chiều", which
  ///   people mean both ways. A time written with a colon and no Vietnamese word
  ///   ("15:30", "3pm") is English's.
  /// - Length: 30 phút, 2 tiếng, 1,5 giờ, 1.5h, 1 tiếng rưỡi, nửa tiếng, nửa giờ, 1
  ///   giờ 30 phút, 2 tiếng 30 phút, 1 tiếng 30, 2 giờ đồng hồ, 1h30p, 1h 30p, ba
  ///   mươi phút, mười lăm phút, each maybe after mất, tốn, kéo dài, thời lượng,
  ///   ước tính, dự kiến, khoảng, or tầm ("mất 2 giờ", "khoảng 30 phút"). Minutes
  ///   after "h" follow it directly or, with their unit, after a space; a number
  ///   after "h" and a space with no unit is the next thing of the line ("18h 1
  ///   tiếng" is 18:00 and an hour). An hour past 12 with minutes ("15 giờ 30
  ///   phút", "18h30p") is a clock time and no length of 15 or 18 hours, unless an
  ///   opener that only a length has comes first ("mất 15 giờ 30 phút"). A moment,
  ///   an interval, a bound, a rate, or a language ("trong 2 tiếng", "sau 30
  ///   phút", "2 tiếng nữa", "mỗi 2 giờ", "cách 2 tiếng", "tối đa 2 tiếng", "2
  ///   tiếng một ngày", "30 phút/ngày", "học 2 tiếng Anh") is no length and stays
  ///   in the title, and neither is a side of a range ("2-3 tiếng", "2 hoặc 3
  ///   tiếng") or a fraction ("1/2 giờ").
  /// - Priority: ưu tiên cao, ưu tiên thấp, ưu tiên trung bình, mức độ ưu tiên cao,
  ///   ưu tiên 1 to 3, and khẩn cấp, quan trọng, khẩn, or gấp (maybe after rất, cực
  ///   kỳ, vô cùng, hết sức, or khá) at the end of the line or opening it before a
  ///   colon or comma. "Khẩn" and "gấp" are read with their marks only ("gap" is
  ///   "gặp", to meet). A negation before them ("không gấp", "chưa khẩn cấp",
  ///   "không quan trọng") keeps them in the title, and so does "quan trọng nhất"
  ///   (the most important thing).
  ///
  /// Vietnamese writes a clock time with the letter h ("15h", "7h30"), so it sets
  /// `writesClockTimesWithH`: beside English, an hour count written with h is read
  /// by Vietnamese alone, as a time ("15h" is 15:00, "2h" is 14:00, "1h30" is 13:30)
  /// or, with "m" or "p" after the minutes or a decimal fraction, as a length ("1h30m"
  /// and "1,5h" are 90 minutes).
  static let vietnamese = LorvexCaptureVocabulary(
    priority: [Rule(pattern: vietnamesePriorityPattern, read: vietnamesePriority)],
    dateRange: [
      Rule(pattern: vietnameseDateRangePattern, read: vietnameseDateRange),
      Rule(pattern: vietnameseWeekdayRangePattern, read: vietnameseWeekdayRange),
    ],
    keptInTitle: [
      Rule(pattern: vietnameseNegatedUrgentPattern) { _ in true },
      Rule(pattern: vietnameseDeadlineClockPattern) { $0.group(1) == nil ? nil : true },
      Rule(pattern: vietnameseDueClockPattern) { vietnameseIsClockAfterDueDay($0) ? true : nil },
      Rule(pattern: vietnameseLengthPattern) { vietnameseClaimsLength($0) ? true : nil },
      Rule(pattern: vietnameseTimesPerPeriodPattern) { vietnameseIsMultipleTimes($0) ? true : nil },
      Rule(pattern: vietnameseOrdinalWeekdayPattern) { _ in true },
      Rule(pattern: vietnameseLunarDatePattern) { _ in true },
      Rule(pattern: vietnameseBoundedPeriodPattern) { _ in true },
      Rule(pattern: vietnameseNextSpanPattern) { _ in true },
      Rule(pattern: vietnameseNamedWeekdayPattern) { _ in true },
      Rule(pattern: vietnameseMidnightDayPattern) { _ in true },
    ],
    length: [Rule(pattern: vietnameseLengthPattern, read: vietnameseLength)],
    time: [
      Rule(pattern: vietnameseTimeRangePattern, read: vietnameseTimeRange),
      Rule(pattern: vietnameseClockPattern, read: vietnameseClock),
      Rule(pattern: vietnameseMeridiemTimePattern, read: vietnameseMeridiemTime),
      Rule(pattern: vietnameseMidnightPattern, read: vietnameseMidnight),
    ],
    repeats: vietnameseRepeatRules,
    due: [Rule(pattern: vietnameseDuePattern, read: vietnameseDue)],
    when: [Rule(pattern: vietnameseWhenPattern, read: vietnameseWhen)],
    writesClockTimesWithH: true)

  // MARK: - Priority

  /// The words that make a task urgent, maybe after an intensifier, as a pattern
  /// without groups: "khẩn cấp", "quan trọng", "khẩn", "gấp". "Khẩn" and "gấp"
  /// are read only with their marks: "gap" without them is "gặp" (to meet), and
  /// "khan" is another word.
  private static let vietnameseUrgentWords: String = {
    let intensifier = "(?:\(vietnameseAlternation(["rất", "cực kỳ", "vô cùng", "hết sức", "khá"]))\\s+)?"
    let words = [
      vietnameseWord("khẩn cấp"), vietnameseWord("quan trọng"), vietnameseWord("khẩn", strict: true),
      vietnameseWord("gấp", strict: true),
    ]
    return intensifier + "(?:" + words.joined(separator: "|") + ")"
  }()

  /// Group 1: a written priority ("ưu tiên cao", "mức độ ưu tiên thấp", "ưu tiên:
  /// trung bình", "ưu tiên 1"); the urgency words (at the end of the line, with the
  /// full stop or exclamation mark that ends it, or opening the line before a
  /// colon or a comma) have no group. The words are adjectives and a verb too
  /// ("tài liệu quan trọng", "gấp quần áo"), and the end of the line is where one
  /// says how urgent a task is.
  private static var vietnamesePriorityPattern: String {
    let lead = "(?:\(vietnameseAlternation(["mức độ", "mức", "độ"]))\\s+)?\(vietnameseWord("ưu tiên"))"
    let level = "(?:\(vietnameseAlternation(["cao", "thấp", "trung bình"]))|[1-3](?![\\p{N}.,:]))"
    let written = #"\#(lead)\s*[=:]?\s*(?:\#(vietnameseWord("rất"))\s+)?\#(level)"#
    return
      #"\#(vietnameseStart)(\#(written))\#(vietnameseEnd)|(?<=\s)\#(vietnameseUrgentWords)\#(vietnameseEnd)[.!]*(?=\s*$)|^\s*\#(vietnameseUrgentWords)\#(vietnameseEnd)(?=\s*[,:，：])"#
  }

  private static func vietnamesePriority(_ match: Match) -> LorvexTask.Priority? {
    guard let phrase = match.group(1) else { return .p1 }
    let key = vietnameseKey(phrase)
    if let digit = key.last(where: { "123".contains($0) }) {
      return digit == "1" ? .p1 : (digit == "2" ? .p2 : .p3)
    }
    if key.contains("trung binh") { return .p2 }
    return key.contains("thap") ? .p3 : .p1
  }

  /// "không gấp", "chưa khẩn cấp", "không quan trọng", "không cần gấp", "ít quan
  /// trọng": a negation turns the urgency word around, so the phrase stays in the
  /// title whole and no rule reads the word as urgent.
  private static let vietnameseNegatedUrgentPattern =
    #"\#(vietnameseStart)\#(vietnameseAlternation(["không", "chưa", "chẳng", "đừng", "ít", "bớt", "hơi"]))(?:\s+\#(vietnameseAlternation(["cần", "phải", "có", "quá", "lắm", "đâu"])))*\s+\#(vietnameseUrgentWords)\#(vietnameseEnd)"#

  // MARK: - Length

  /// The words that open a length and go with it, as a pattern without groups:
  /// "mất 2 giờ", "tốn 30 phút", "kéo dài 2 tiếng", "ước tính 1 giờ", "dự kiến 45
  /// phút", "khoảng 30 phút".
  private static let vietnameseLengthOpener =
    #"\#(vietnameseAlternation(["kéo dài", "thời lượng", "thời gian", "ước tính", "ước lượng", "dự kiến", "trong khoảng", "khoảng chừng", "khoảng", "chừng", "mất", "tốn", "dài", "tầm", "cỡ"]))"#

  /// The openers that mark an amount of "giờ" as a length where "giờ" alone could
  /// be a clock hour ("mất 2 giờ" takes two hours; "khoảng 2 giờ" is about two
  /// hours or about two o'clock), as keys.
  private static let vietnameseStrongLengthOpeners: Set<String> = [
    "mat", "ton", "keo dai", "dai", "thoi luong", "thoi gian", "uoc tinh", "uoc luong", "du kien",
  ]

  /// The words before an amount that make it a moment, an interval, a bound, or a
  /// distance rather than a length: "trong 2 tiếng", "sau 30 phút", "mỗi 2 giờ",
  /// "cách 2 tiếng", "trước 30 phút", "tối đa 2 tiếng", "ít nhất 30 phút", "hơn 2
  /// tiếng", "dưới 1 giờ".
  private static let vietnameseLengthDecliner: String = {
    let words = vietnameseAlternation([
      "trong vòng", "trong", "cứ mỗi", "mỗi", "cách đây", "cách", "trước", "tối đa", "tối thiểu", "ít nhất", "nhiều nhất",
      "chưa đầy", "hơn", "dưới", "trên", "quá", "cho đến", "cho tới", "đến",
    ])
    // "Sau" typed without marks after "thứ" is Friday ("thu Sau 5 gio chieu") and "tuần sau" is next week
    // ("tuần sau 2 tiếng"): no word that makes an amount a moment.
    let after = #"(?<!\#(vietnameseNounBeforeNext)\s{1,3})sau(?:\s+\#(vietnameseWord("khoảng")))?"#
    return #"(?:\#(words)|\#(after))(?:\s+\#(vietnameseWord("là")))?"#
  }()

  /// The words after an amount that make it a moment, the past, a bound, or a rate:
  /// "2 tiếng nữa", "2 tiếng trước", "2 tiếng sau", "2 tiếng tối đa", "2 tiếng trở
  /// lên", "30 phút một lần", "2 tiếng một ngày", "2 tiếng/ngày".
  private static let vietnameseLengthTrailing: String = {
    let words = vietnameseAlternation([
      "nữa", "trước", "sau", "qua", "rồi", "vừa rồi", "một lần", "một ngày", "một tuần", "một tháng", "một buổi",
      "một bữa", "tối đa", "tối thiểu", "ít nhất", "nhiều nhất", "trở lên", "trở xuống",
    ])
    // "Tới" before a number ("3 giờ tới 5 giờ chiều") joins the two sides of a range of times.
    return
      "(?:\(words)|\(vietnameseWord("tới", strict: true))(?!\\s+\\d)|/\\s*\(vietnameseAlternation(["ngày", "tuần", "tháng", "buổi"])))"
  }()

  /// What may not follow "tiếng" of an hours amount: the name of a language
  /// ("2 tiếng Anh" is two English words or lessons, not two hours).
  private static let vietnameseNotALanguage =
    #"(?!\s+\#(vietnameseAlternation(["anh", "việt", "pháp", "nhật", "hàn", "trung", "đức", "ý", "nga", "tây ban nha", "thái", "lào", "hoa", "quan thoại", "hà lan", "bồ đào nha", "ả rập", "do thái", "ba lan", "mẹ đẻ"]))\#(vietnameseEnd))"#

  /// "30 phút", "2 tiếng", "1,5 giờ", "1 giờ 30 phút", "1 tiếng 30", "1 tiếng
  /// rưỡi", "2 giờ đồng hồ", "nửa tiếng", "nửa giờ", "một tiếng", "ba mươi phút",
  /// "1h30p", and "mất 2 giờ", each maybe after an opener. Groups: 1 the opener; 2
  /// a word that makes the amount a moment, an interval, or a bound; 3 the amount
  /// of hours of a whole or spelled count, 4 its unit ("giờ" or "tiếng"), 5 "rưỡi"
  /// after it, 6 "đồng hồ" after it, 7 the amount of minutes after it (digits, or
  /// a spelled count followed by its unit, since "2 tiếng một ngày" is no 2 hours
  /// and 1 minute), 8 their unit; 9 hours with a decimal fraction and 10 their
  /// unit ("giờ", "tiếng", or "h"); 11 and 12 the hours and the minutes of
  /// "1h30p", "1h 30p", and "1h30", 13 the minutes' unit; 14 whole hours written
  /// with h; 15 minutes of an amount of "phút" and 16 its unit; 17 "nửa giờ" or
  /// "nửa tiếng"; 18 a word after the amount that makes it a moment, the past, or
  /// a rate, which may follow a slash directly ("30 phút/ngày"). A match
  /// with group 2 or 18 is no length: the reader declines it and the title keeps
  /// it. The amount may not follow a digit, a colon, a slash, or a separator ("1/2
  /// giờ" is half an hour, no length of 2 hours), and an amount that is a side of
  /// a range ("2-3 tiếng", "2 hoặc 3 tiếng") is no length.
  static var vietnameseLengthPattern: String {
    let amount = #"(\d+|\#(vietnameseNumberWords))"#
    let hours = vietnameseAlternation(["giờ", "tiếng"])
    let minutes = vietnameseAlternation(["phút", "ph"])
    let minuteAmount = #"(\d+|\#(vietnameseNumberWords)(?=\s*\#(minutes)\#(vietnameseEnd)))"#
    let notRangeStart =
      #"(?<![\p{N}:.,/])(?<![\p{N}]\s?[-–—]\s?)(?<!\d\s{1,3}\#(vietnameseAlternation(["hoặc", "hay", "đến", "tới", "và"]))\s{1,3})"#
    // Minutes after "h" follow it directly ("1h30"), or after a space with their unit ("1h 30p"): a number
    // after "h" and a space with no unit is the next thing of the line ("18h 1 tiếng").
    let hourMinutes =
      #"(\d+)\s*h(?:\s+(?=\d{1,2}\s*(?:\#(minutes)|p|m|')(?![\p{Latin}\p{N}\p{M}])))?(\d{1,2})(?:\s*(\#(minutes)|p|m|'))?"#
    let hoursAmount =
      #"\#(amount)\s*(\#(vietnameseWord("giờ"))|\#(vietnameseWord("tiếng"))\#(vietnameseNotALanguage))(?:\s+(\#(vietnameseWord("rưỡi")))|\s+(\#(vietnameseWord("đồng hồ")))|\s*(?:\#(vietnameseWord("và"))\s+)?\#(minuteAmount)(?:\s*(\#(minutes)))?)?"#
    return
      #"\#(vietnameseStart)(?:(\#(vietnameseLengthOpener))\s+|(\#(vietnameseLengthDecliner))\s+)?\#(notRangeStart)(?:\#(hoursAmount)|(\d+[.,]\d+)\s*(\#(hours)|h)|\#(hourMinutes)|(\d+)\s*h|\#(amount)\s*(\#(minutes))|(\#(vietnameseWord("nửa"))\s+\#(hours))(?:\s+\#(vietnameseWord("đồng hồ")))?)\#(vietnameseEnd)(?!\s*[-–—]\s*\d)(?:(?:\s+|(?=/))(\#(vietnameseLengthTrailing))\#(vietnameseEnd))?"#
  }

  /// Whether a match of ``vietnameseLengthPattern`` is kept in the title whole: it
  /// names a moment, an interval, a bound, the past, or a rate. An hour count
  /// written with "giờ" or "h" after "đến" is no claim of a length: it is a clock
  /// bound, which ``vietnameseDeadlineClockPattern`` keeps by itself, or the end
  /// of a range of times ("từ 3 giờ đến 5 giờ chiều") the time rule reads.
  static func vietnameseClaimsLength(_ match: Match) -> Bool {
    if match.group(18) != nil { return true }
    guard let word = match.group(2) else { return false }
    let key = vietnameseKey(word)
    let isUntil = key == "den" || key.hasPrefix("den ") || key.hasPrefix("cho ")
    let isClockHours = match.group(4).map(vietnameseKey) == "gio" || match.group(11) != nil || match.group(14) != nil
    return !(isUntil && isClockHours)
  }

  /// Whether the hours of `match` are written as a clock time: after a clock lead
  /// ("lúc 3 giờ 15 phút"), before a part of the day ("3 giờ 15 phút chiều"), or
  /// where the line names a part of the day beside them ("chiều mai 3 giờ 30 phút").
  private static func vietnameseIsClockWritten(_ match: Match) -> Bool {
    vietnameseFinds(#"(?:^|\s)\#(vietnameseClockLead)\s*$"#, in: vietnameseTextBefore(match))
      || vietnameseFinds(#"^\s*(?:\#(vietnameseWord("buổi"))\s+)?\#(vietnameseDayParts)\#(vietnameseEnd)"#, in: vietnameseTextAfter(match))
      || vietnameseHasLinePart(beside: match)
  }

  private static func vietnameseLength(_ match: Match) -> Int? {
    if match.group(2) != nil || match.group(18) != nil { return nil }
    let isStrongOpener = match.group(1).map { vietnameseStrongLengthOpeners.contains(vietnameseKey($0)) } ?? false
    if let amountText = match.group(3), let unit = match.group(4).map(vietnameseKey),
      let hours = vietnameseCount(amountText)
    {
      if unit == "tieng" {
        var minutes = hours * 60
        if match.group(5) != nil {
          minutes += 30
        } else if let text = match.group(7) {
          guard let extra = vietnameseCount(text), extra < 60 else { return nil }
          minutes += extra
        }
        return taskLength(minutes: minutes)
      }
      // "Giờ" is a length with minutes counted in "phút", with "đồng hồ", or after
      // an opener that only a length has; otherwise it is a clock hour. An hour past
      // 12 with minutes is a clock time ("15 giờ 30 phút"), no length of 15 hours.
      if let text = match.group(7) {
        guard match.group(8) != nil, let extra = vietnameseCount(text), extra < 60,
          isStrongOpener || (hours <= 12 && !vietnameseIsClockWritten(match))
        else { return nil }
        return taskLength(minutes: hours * 60 + extra)
      }
      if match.group(6) != nil { return taskLength(minutes: hours * 60) }
      return isStrongOpener ? taskLength(minutes: hours * 60 + (match.group(5) != nil ? 30 : 0)) : nil
    }
    if let amountText = match.group(9), let hours = decimalAmount(amountText) {
      return taskLength(minutes: Int((hours * 60).rounded()))
    }
    if let hours = match.group(11).flatMap(number), let minutes = match.group(12).flatMap(number), minutes < 60 {
      // "1h30p" is a length; "1h30" is one only after an opener that only a length has. Either is a
      // clock time where the line writes it as one ("lúc 3h30p", "3h30p chiều") and where the hour
      // is past 12 ("18h30p"), which is no length of 18 hours.
      if !isStrongOpener, match.group(13) == nil || hours > 12 || vietnameseIsClockWritten(match) { return nil }
      return taskLength(minutes: hours * 60 + minutes)
    }
    if let hours = match.group(14).flatMap(number) {
      // Whole hours written with h are a clock hour unless an opener says length.
      return isStrongOpener ? taskLength(minutes: hours * 60) : nil
    }
    if let text = match.group(15), let minutes = vietnameseCount(text) {
      // The minutes of "3 giờ kém 15 phút" belong to the clock time.
      if vietnameseFinds(#"(?:^|\s)\#(vietnameseWord("kém"))\s*$"#, in: vietnameseTextBefore(match)) { return nil }
      return taskLength(minutes: minutes)
    }
    return match.group(17) == nil ? nil : 30
  }
}

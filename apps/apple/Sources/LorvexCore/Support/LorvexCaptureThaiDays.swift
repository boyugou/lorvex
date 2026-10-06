import Foundation

extension LorvexCaptureVocabulary {
  // The Thai day rules: the due day, the planned day, the date ranges, and the
  // past days and ordinal weekdays that stay in the title. The vocabulary's
  // other words are in ``thai``.

  // MARK: - Weekdays

  /// Each weekday's names, Sunday first: อาทิตย์ is also the word for a week, so
  /// a weekday written without "วัน" never names Sunday alone.
  private static let thaiWeekdayRows: [(names: [String], index: Int)] = [
    (["อาทิตย์"], 0), (["จันทร์"], 1), (["อังคาร"], 2), (["พุธ"], 3), (["พฤหัสบดี", "พฤหัสฯ", "พฤหัส"], 4),
    (["ศุกร์"], 5), (["เสาร์"], 6),
  ]

  private static let thaiWeekdayWords: [String: Int] = {
    var words: [String: Int] = [:]
    for row in thaiWeekdayRows { for name in row.names { words[name] = row.index } }
    return words
  }()

  /// The weekday names, as a pattern without groups.
  static var thaiWeekdayNames: String {
    alternation(of: thaiWeekdayRows.flatMap(\.names))
  }

  /// The weekday names but Sunday, as a pattern without groups: the names a
  /// weekday may be written with when "วัน" does not stand before it.
  static var thaiWeekdayNamesExceptSunday: String {
    alternation(of: thaiWeekdayRows.filter { $0.index != 0 }.flatMap(\.names))
  }

  /// The weekday a matched name stands for, 0 = Sunday.
  static func thaiWeekdayIndex(_ name: String) -> Int? {
    thaiWeekdayWords[name]
  }

  /// "วัน" before a weekday name: not the end of "ตะวัน" (sun) and not the
  /// "วัน" of "ทุกวัน", which the repeat rules read.
  static let thaiWan = #"(?<!ตะ)(?<!ทุก)(?<!ทุกๆ)วัน"#

  // MARK: - Parts of the day

  /// The words for a part of the day, as a pattern without groups.
  static let thaiPartWords = #"(?:เช้า|บ่าย|เย็น|ค่ำ|คืน|ดึก)"#

  /// What may follow a part of the day written after a day word: the end of the
  /// line, a space, punctuation, or a particle or preposition that goes on
  /// with the sentence. Any other letter after it makes it the start of a longer
  /// word ("เช้ามืด", "เย็นย่ำ").
  static let thaiPartEnd =
    #"(?:(?![\p{L}\p{M}\p{N}])|(?=(?:ที่|นี้|นะ|ครับ|ค่ะ|คะ|ด้วย|เลย|ไป|มา|ให้|กับ|และ|หรือ|แล้ว)))"#

  /// A part of the day after a day word, optional: "พรุ่งนี้เช้า", "วันศุกร์ตอนเย็น",
  /// "วันนี้ช่วงบ่าย".
  static let thaiPartTail = #"(?:\s*(?:(?:ตอน|ช่วง)\s*)?\#(thaiPartWords)\#(thaiPartEnd))?"#

  /// A part of the day before a day word, optional, which must open a word of its
  /// own: "เย็นวันศุกร์", "คืนวันเสาร์", "เช้าพรุ่งนี้". Glued to the word before
  /// it ("ข้าวเย็น", "ส่งคืน"), the part belongs to that word.
  private static let thaiPartPrefix =
    #"(?:(?<![\p{L}\p{M}\p{N}])(?:(?:ตอน|ช่วง)\s*)?\#(thaiPartWords)\s*(?:ของ)?\s*)?"#

  /// The words that end a compound a part of the day is the last word of, which
  /// makes "เย็นนี้" in "ข้าวเย็นนี้" no day: meals, shifts, and the verbs and
  /// nouns "คืน" belongs to ("ส่งคืนนี้", "เงินคืน").
  static let thaiNotAfterCompound =
    #"(?<!ข้าว|อาหาร|มื้อ|ข่าว|รอบ|กะ|ละคร|ชา|กาแฟ|นม|น้ำ|ขนม|โจ๊ก|ส่ง|ชำระ|ขอ|นำ|ใช้|เรียก|เงิน|จ่าย|ผ่อน|แลก|ถอน|ค่า|ราย|ยา)"#

  /// What may not stand before a weekday name written without "วัน": the word
  /// for a planet, the moon, or a title, which makes the name another thing
  /// ("ดาวศุกร์", "พระจันทร์", "คุณจันทร์").
  private static let thaiNotAfterTitle = #"(?<!ดาว|ดวง|พระ|คุณ|นาย|นาง)"#

  /// What may follow "หน้า" for it to mean "next" and not begin another word:
  /// "หน้าต่าง" (window), "หน้าจอ" (screen), "หน้าฝน" (rainy season).
  private static let thaiNotAfterNext =
    #"ต่าง|ตา|จอ|แรก|ฝน|ร้อน|หนาว|ร้าน|บ้าน|ห้อง|ประตู|อาคาร|โรง|เวที|งาน|สุด|กาก|กระดาษ|อก|ท้อง|ผาก|ม้า|ไหน|เว็บ|เพจ|แอป|ปก|นี้"#

  /// What may follow "วัน" after a count for it to be the unit "day": not
  /// "วันหยุด" (holiday), "วันละ" (per day), "วันเกิด" (birthday).
  private static let thaiNotAfterWan = #"หยุด|ละ|เว้น|เกิด|ทำงาน|ลา|ว่าง|นี้|ที่"#

  // MARK: - Months

  private static let thaiMonthRows: [(name: String, abbreviation: String)] = [
    ("มกราคม", "ม.ค."), ("กุมภาพันธ์", "ก.พ."), ("มีนาคม", "มี.ค."), ("เมษายน", "เม.ย."), ("พฤษภาคม", "พ.ค."),
    ("มิถุนายน", "มิ.ย."), ("กรกฎาคม", "ก.ค."), ("สิงหาคม", "ส.ค."), ("กันยายน", "ก.ย."), ("ตุลาคม", "ต.ค."),
    ("พฤศจิกายน", "พ.ย."), ("ธันวาคม", "ธ.ค."),
  ]

  /// The month names and abbreviations ("ตุลาคม", "ต.ค."), as a pattern without
  /// groups. An abbreviation ends with its period or at the end of a word.
  static var thaiMonthNames: String {
    let full = alternation(of: thaiMonthRows.map(\.name))
    let abbreviations = thaiMonthRows.map { row -> String in
      let stem = row.abbreviation.dropLast().replacingOccurrences(of: ".", with: #"\."#)
      return stem + #"(?:\.|(?![\p{L}\p{M}\p{N}]))"#
    }
    return "(?:(?:\(full))\(thaiEnd)|\(abbreviations.joined(separator: "|")))"
  }

  /// The month a matched name or abbreviation names, 1 = January.
  private static func thaiMonthNumber(_ text: String) -> Int? {
    let key = text.filter { $0 != "." && !$0.isWhitespace }
    for (index, row) in thaiMonthRows.enumerated() {
      if key == row.name || key == row.abbreviation.filter({ $0 != "." }) { return index + 1 }
    }
    return nil
  }

  // MARK: - Dates

  /// A four-digit year that is one a task can fall in: 19xx and 20xx in the
  /// Christian Era, 24xx and 25xx in the Buddhist Era, in Arabic or Thai digits.
  private static let thaiYear = #"(?:[1๑][9๙]|[2๒][0๐4๔5๕])\d{2}"#

  /// A year after a month, with the era marker "พ.ศ." (Buddhist Era) or "ค.ศ."
  /// (Christian Era) maybe before it.
  private static var thaiYearTail: String {
    #"\s*(?:(?:พ\.ศ\.|ค\.ศ\.)\s*)?\#(thaiYear)(?![\p{N}]|[.,/-]\p{N})"#
  }

  /// What may follow a month in a date: a year, or "นี้" (this) written right
  /// after the month name ("15 ตุลาคมนี้", "15 ต.ค.นี้"). The word goes with the
  /// date and leaves its reading unchanged.
  private static var thaiMonthTail: String {
    #"(?:\#(thaiYearTail)|นี้)?"#
  }

  /// "15 ตุลาคม", "15ตุลาคม", "15 ต.ค.", "15 ตุลาคม 2569", "15 ต.ค. พ.ศ. 2569",
  /// "15 ตุลาคมนี้": a day and a month, maybe with a year. A month needs its day
  /// number ("ตุลาคม" alone is no date).
  private static var thaiMonthDate: String {
    #"(?<![\p{N}.,:/-])\d{1,2}\s*\#(thaiMonthNames)\#(thaiMonthTail)"#
  }

  /// The words that make a number beside a slash a numbered item of the title
  /// and no date: "เวอร์ชัน 1.10.2026", "ข้อ 3/4/2026", "เลขที่ 99/9/2569".
  private static let thaiNumberingWords =
    #"(?:เวอร์ชัน|เวอร์ชั่น|version|ver|v|ข้อ|หน้า|บทที่|เลขที่|หมายเลข|ห้อง|ชั้น|ซอย)"#

  /// "15/10/2569", "15-10-2026", "15.10.2569": a day, a month, and a four-digit
  /// year in digits, which nothing else is written as.
  private static var thaiNumericDate: String {
    #"(?<![\p{N}.,:/-])(?<!\#(thaiNumberingWords)\s{0,2})\d{1,2}[/.\-]\d{1,2}[/.\-]\d{4}(?![\p{N}]|[.,/]\p{N})"#
  }

  /// "15/10", "15.10", "15/10/69": a day and a month in digits with no year or
  /// with two digits of one, which a date reads only where something introduces
  /// it: Thai addresses are written "99/9", and "15.10" is as often a time or an
  /// amount. A dash does not join them, since "2-3" after "วันที่" is a range of
  /// days.
  private static var thaiLooseDate: String {
    #"(?<![\p{N}.,:/-])\d{1,2}[/.]\d{1,2}(?:[/.]\d{2})?(?![\p{N}]|[.,/]\p{N}|[-–]\p{N})(?!\s*(?:\#(thaiCountedUnits)))"#
  }

  /// The words that introduce a date: "วันที่", "ในวันที่".
  private static let thaiDateLead = #"(?:(?:ใน)?วันที่\s*)"#

  /// "วันที่ 15", "ในวันที่ 15": a day of the month with no month name, which is
  /// this month's or, once passed, next month's. It is no day after "ทุก" (a
  /// repeat) or "เมื่อ" (the past), before a colon ("วันที่ 1: เตรียมงาน" is day 1
  /// of something), where it goes on as a list or a range of days, or before a
  /// month name, a counted unit, or a "ของ" that names something other than the
  /// month ("วันที่ 2 ของงาน").
  private static var thaiDayOfMonth: String {
    let continues = #"(?:[-–—,/&]|และ|กับ|หรือ|ถึง|จนถึง|จน)"#
    let notBefore =
      #"(?!\s*(?:\#(thaiMonthNames)|\#(thaiCountedUnits)|ของ(?!\s*(?:ทุก\s*)?เดือน)))"#
    return
      #"(?<!ทุก\s{0,2})(?<!ทุกๆ\s{0,2})(?<!เมื่อ\s{0,2})\#(thaiDateLead)\d{1,2}(?![\p{N}:./%-])(?!\s*[:：])(?!\s*\#(continues)\s*\d)\#(notBefore)"#
  }

  /// A weekday written before the date it belongs to, as a pattern without
  /// groups: "วันศุกร์ที่ 16 ตุลาคม", "วันศุกร์ 16 ตุลาคม", "ศุกร์ที่ 16 ตุลาคม".
  private static var thaiWeekdayBeforeDate: String {
    let name = thaiWeekdayNames
    return #"(?:\#(thaiWan)(?:\#(name))\s*(?:ที่\s*)?|(?:\#(name))\s*ที่\s*)"#
  }

  /// The Christian Era year a written year names. "พ.ศ." and a year from 2400 are
  /// Buddhist Era, "ค.ศ." and a smaller year Christian Era.
  private static func thaiGregorianYear(_ text: String, marker: String?) -> Int? {
    guard let value = number(text) else { return nil }
    if marker?.hasPrefix("ค") == true { return value }
    if marker != nil { return value - 543 }
    return value >= 2400 ? value - 543 : value
  }

  /// The date a day phrase names, or nil when it names no date, a day or month
  /// the calendar lacks, or a two-digit year that is neither era's near future.
  private static func thaiExplicitDate(_ phrase: String, in match: Match) -> ExplicitDate? {
    guard phrase.contains(where: \.isNumber) else { return nil }
    let monthPattern =
      #"(\d{1,2})\s*(\#(thaiMonthNames))(?:\s*((?:พ\.ศ\.|ค\.ศ\.))?\s*(\#(thaiYear))(?![\p{N}]|[.,/-]\p{N}))?"#
    if let found = thaiFirstGroups(monthPattern, in: phrase), let day = found[1].flatMap(number),
      let month = found[2].flatMap(thaiMonthNumber), (1...31).contains(day)
    {
      let year = found[4].flatMap { thaiGregorianYear($0, marker: found[3]) }
      return ExplicitDate(year: year, month: month, day: day)
    }
    guard let found = thaiFirstGroups(#"(\d{1,2})[/.\-](\d{1,2})(?:[/.\-](\d{4}|\d{2}))?"#, in: phrase),
      let day = found[1].flatMap(number), let month = found[2].flatMap(number), (1...12).contains(month),
      (1...31).contains(day)
    else { return nil }
    guard let yearText = found[3] else { return ExplicitDate(year: nil, month: month, day: day) }
    guard let value = number(yearText) else { return nil }
    if yearText.count == 4 {
      return ExplicitDate(year: thaiGregorianYear(yearText, marker: nil), month: month, day: day)
    }
    // Two digits are the Christian Era's 20xx or the Buddhist Era's 25xx,
    // whichever is a year from this one to ten years on.
    guard let today = match.today, let thisYear = utcCalendar.dateComponents([.year], from: today).year else {
      return nil
    }
    let candidates = [2000 + value, 1957 + value].filter { (thisYear...(thisYear + 10)).contains($0) }
    guard let year = candidates.first else { return nil }
    return ExplicitDate(year: year, month: month, day: day)
  }

  // MARK: - Date range

  /// A side of a date range: a day with its month ("5 พฤษภาคม", "30 พ.ค. 2570",
  /// "5 พฤษภาคมนี้"), or a day alone ("3"), each maybe after "วันที่".
  private static func thaiRangeSide(isEnd: Bool) -> String {
    let lookbehind = isEnd ? #"(?<![\p{N}.,:/])"# : #"(?<![\p{N}.,:/-])"#
    let month = #"\d{1,2}\s*\#(thaiMonthNames)\#(thaiMonthTail)"#
    let bare = #"\d{1,2}(?![\p{N}%]|[.,:/]\p{N}|\s*(?:\#(thaiCountedUnits)))"#
    return #"\#(lookbehind)\#(thaiDateLead)?(?:\#(month)|\#(bare))"#
  }

  /// "3-5 พฤษภาคม", "3 ถึง 5 พฤษภาคม", "3 พ.ค. - 5 พ.ค.", "ตั้งแต่ 3 ถึง 5 พฤษภาคม",
  /// "ตั้งแต่วันที่ 3 ถึงวันที่ 5 พฤษภาคม", "30 พฤษภาคม - 2 มิถุนายน", each maybe with
  /// a year after the end. Groups: 1 the opening word, 2 the start, 3 a dash
  /// between the sides, 4 the word that means "to" between them, 5 the end.
  static var thaiDateRangePattern: String {
    let opening = #"(?:(?:ตั้งแต่|จาก|ระหว่าง)\s*(?:(?:ใน)?วันที่\s*)?|(?:ใน)?วันที่\s*)"#
    return
      #"\#(thaiStart)(\#(opening))?(\#(thaiRangeSide(isEnd: false)))(?:\s*([-–—])\s*|\s*(จนถึง|ถึง|จน)\s*)(\#(thaiRangeSide(isEnd: true)))\#(thaiEnd)"#
  }

  /// A side of a date range as a date: with its month, or a day alone, which
  /// has no month.
  private static func thaiRangeDate(_ text: String, in match: Match) -> ExplicitDate? {
    if thaiMatches(thaiMonthNames, text) { return thaiExplicitDate(text, in: match) }
    guard let found = thaiFirstGroups(#"(\d{1,2})$"#, in: text), let day = found[1].flatMap(number),
      (1...31).contains(day)
    else { return nil }
    return ExplicitDate(day: day)
  }

  /// A range joined by a word that means "to" is read without an opening word
  /// ("3 ถึง 5 พฤษภาคม"), since its end names a month; one with a dash and a day
  /// alone for its start needs the dash to touch both sides ("3-5 พฤษภาคม"),
  /// because "Sprint 12 - 20 พฤษภาคม" sets a number of the title apart from a
  /// date.
  static func thaiDateRange(_ match: Match) -> DayRangeReading? {
    guard let startText = match.group(2), let endText = match.group(5),
      let start = thaiRangeDate(startText, in: match), let end = thaiRangeDate(endText, in: match),
      end.month != nil
    else { return nil }
    if start.month == nil, match.group(1) == nil, match.group(3) != nil,
      !dashTouchesBothSides(match, start: 2, end: 5)
    {
      return nil
    }
    return dayRangeReading(from: start, to: end, today: match.today)
  }

  // MARK: - Weekday range

  /// "ตั้งแต่วันศุกร์ถึงวันอาทิตย์", "วันศุกร์ถึงวันอาทิตย์", "วันศุกร์-อาทิตย์",
  /// "จากศุกร์ถึงอาทิตย์": a span of weekdays, joined by a dash or by "ถึง",
  /// "จนถึง", or "จน". The first name needs "วัน" before it or an opening word. A
  /// span after "ทุก" is a repeat, which the repeat rules read. Groups: 1 the
  /// opening word, 2 the first weekday, 3 a dash, 4 the word that means "to", 5
  /// the last weekday.
  static var thaiWeekdayRangePattern: String {
    let name = thaiWeekdayNames
    return
      #"\#(thaiStart)(?<!ทุก\s{0,2})(?<!ทุกๆ\s{0,2})(?:(ตั้งแต่|จาก)\s*)?(?:\#(thaiWan)|(?<=(?:ตั้งแต่|จาก)\s{0,2}))(\#(name))\s*(?:([-–—])\s*|(จนถึง|ถึง|จน)\s*)(?:วัน)?(\#(name))\#(thaiEnd)"#
  }

  /// A span of weekdays plans the coming first day and is due on the last day
  /// after it, so on a Tuesday "วันศุกร์ถึงวันอาทิตย์" runs from Friday to the
  /// Sunday after it. A span from a day to itself is no span.
  static func thaiWeekdayRange(_ match: Match) -> DayRangeReading? {
    guard let firstText = match.group(2), let lastText = match.group(5),
      let first = thaiWeekdayIndex(firstText), let last = thaiWeekdayIndex(lastText), first != last
    else { return nil }
    let start = comingWeekdayOffset(first, todayWeekday: match.todayWeekday)
    return .range(DayRange(start: start, end: start + (last - first + 7) % 7))
  }

  // MARK: - Past days, nowadays, and ordinal weekdays

  /// "เมื่อวาน", "เมื่อวานนี้", "เมื่อคืน", "เมื่อเช้า", "เมื่อวันศุกร์", "วันศุกร์ที่แล้ว",
  /// "สัปดาห์ที่แล้ว", "เดือนที่ผ่านมา", "3 วันก่อน", each with the part of the day
  /// and the clock time that follow it: a day or a week that is past, which
  /// names no day a task can be set for. It stays in the title whole, so the
  /// weekday or the hour inside it is not read.
  static var thaiPastPattern: String {
    let name = thaiWeekdayNames
    let past = #"(?:ที่แล้ว|ที่ผ่านมา)"#
    let days =
      #"(?:เมื่อวานซืน|เมื่อวานนี้|เมื่อวาน|วานซืน|วานนี้|เมื่อคืนก่อน|เมื่อคืนนี้|เมื่อคืน|เมื่อเช้านี้|เมื่อเช้า|เมื่อบ่าย|เมื่อเย็น|เมื่อวัน(?:\#(name))|เมื่อวันที่\s*\d{1,2}(?:\s*\#(thaiMonthNames))?)"#
    let periods = #"(?:(?:วัน)?(?:\#(name))|สัปดาห์|อาทิตย์|สุดสัปดาห์|เดือน|ปี)\#(past)"#
    let counted = #"(?:เมื่อ\s*)?\d{1,3}\s*(?:วัน|สัปดาห์|เดือน|ปี)(?:\#(past)|ก่อน)"#
    let part = #"(?:\s*(?:(?:ตอน|ช่วง)\s*)?\#(thaiPartWords))?"#
    return
      #"\#(thaiStart)(?:\#(days)|\#(periods)|\#(counted))\#(part)(?:\s*\#(thaiClockAlternatives))?\#(thaiEnd)"#
  }

  /// "ทุกวันนี้": nowadays, which names no day and no repeat.
  static let thaiNowadaysPattern = #"\#(thaiStart)ทุก(?:ๆ)?วันนี้\#(thaiEnd)"#

  /// "วันจันทร์แรกของเดือน", "ทุกวันศุกร์สุดท้ายของเดือน", "วันพุธที่สองของเดือน": an
  /// ordinal weekday of the month, which is not the plain weekday its name
  /// says. It stays in the title whole.
  static var thaiOrdinalWeekdayPattern: String {
    let ordinal = #"(?:แรก|สุดท้าย|ที่\s*(?:\d|\#(thaiNumberWords)))"#
    return
      #"\#(thaiStart)(?:ทุก(?:ๆ)?\s*)?(?:วัน)?(?:\#(thaiWeekdayNames))\s*\#(ordinal)\s*(?:ของ|ใน)\s*(?:ทุก)?เดือน\#(thaiEnd)"#
  }

  // MARK: - Day phrases

  /// What may follow a weekday name in a phrase that names one day: no further
  /// weekday joined to it by "และ", "กับ", "หรือ", or a comma, which makes the
  /// phrase a list of days that names no one planned day.
  private static var thaiNameEnd: String {
    #"\#(thaiEnd)(?!\s*(?:และ|กับ|หรือ|,|/|&)\s*(?:วัน)?(?:\#(thaiWeekdayNames)))"#
  }

  /// What may not stand before a weekday for it to name a day by itself: a
  /// separator that makes it the second item of a list.
  private static let thaiNotAfterListSeparator = #"(?<!(?:และ|กับ|หรือ|,|/|&)\s{0,2})"#

  /// The days a phrase may name, as the alternatives of a pattern without
  /// groups: a weekend, next week, a count of days or weeks, a date, a weekday,
  /// and a day word. After a word that introduces the day (`afterLead`) a
  /// weekday may be written without "วัน", a count needs no "อีก", a day of the
  /// month alone is a date, and a loose date ("15/10") is a date; without one a
  /// loose date needs "วันที่" before it.
  private static func thaiDayAlternatives(afterLead: Bool) -> [String] {
    let name = thaiWeekdayNames
    let noSunday = thaiWeekdayNamesExceptSunday
    let weekWord = #"(?:สัปดาห์|อาทิตย์)"#
    let next = #"(?:หน้า(?!\#(thaiNotAfterNext))|ถัดไป)"#
    let coming = #"ที่(?:กำลัง)?จะ?ถึง(?:นี้)?"#
    let wd = #"(?:\#(thaiWan)(?:\#(name)))"#
    let count = #"(?:\d{1,3}|\#(thaiNumberWords))"#
    let tail = thaiPartTail
    let partNames = #"(?:เช้า|บ่าย|เย็น|ค่ำคืน|ค่ำ|คืน|ดึก)"#
    let dayWords = #"(?:วันนี้|(?:วัน)?พรุ[่้]งนี้|มะรืน(?:นี้)?)"#
    var alternatives: [String] = [
      #"(?<!ทุก)(?<!ทุกๆ)สุดสัปดาห์(?:\#(next)|นี้|\#(coming))?"#,
      #"(?<!ทุก)(?<!ทุกๆ)(?:วัน)?เสาร์\s*[-–—]?\s*(?:และ\s*)?(?:วัน)?อาทิตย์(?:\#(next)|นี้)?"#,
      #"\#(weekWord)\#(next)\s*(?:ของ\s*)?(?:\#(wd)|(?:\#(noSunday)))\#(thaiEnd)"#,
      #"(?:\#(wd)|\#(name))\s*(?:ของ|ใน)?\s*\#(weekWord)\#(next)"#,
      #"\#(thaiPartPrefix)\#(wd)(?:\#(next)|นี้|\#(coming))\#(thaiEnd)\#(tail)"#,
      #"\#(thaiNotAfterTitle)(?:\#(noSunday))(?:\#(next)|นี้)\#(thaiEnd)"#,
      #"\#(weekWord)\#(next)"#,
      #"อีก\s*(?:\#(count)\s*(?:วัน(?!\#(thaiNotAfterWan))|สัปดาห์|อาทิตย์)|สัปดาห์|อาทิตย์)"#,
    ]
    let dates =
      afterLead
      ? #"(?:\#(thaiMonthDate)|\#(thaiNumericDate)|\#(thaiLooseDate))"#
      : #"(?:\#(thaiMonthDate)|\#(thaiNumericDate))"#
    alternatives.append(#"(?:\#(thaiWeekdayBeforeDate))?\#(thaiDateLead)?\#(dates)"#)
    alternatives.append(
      #"(?:\#(wd)|\#(thaiNotAfterTitle)(?:\#(noSunday)))\s*ที่\s*\d{1,2}(?![\p{N}:./-])(?!\s*(?:\#(thaiMonthNames)|โมง|ทุ่ม|นาฬิกา|น\.|\#(thaiCountedUnits)))"#)
    alternatives.append(thaiDayOfMonth)
    if !afterLead {
      alternatives.append(#"(?:\#(thaiWeekdayBeforeDate)|\#(thaiDateLead))\#(thaiLooseDate)"#)
    }
    if afterLead {
      alternatives.append(contentsOf: [
        #"\#(count)\s*(?:วัน(?!\#(thaiNotAfterWan))|สัปดาห์|อาทิตย์)"#,
        #"(?:\#(noSunday))\#(thaiNameEnd)\#(tail)"#,
      ])
    }
    alternatives.append(contentsOf: [
      #"\#(thaiNotAfterListSeparator)\#(thaiPartPrefix)\#(wd)\#(thaiNameEnd)\#(tail)"#,
      #"(?<!ทุก)(?<!ทุกๆ)(?<!เมื่อ)วันนี้\#(tail)"#,
      #"(?:วัน)?พรุ[่้]งนี้\#(tail)"#,
      #"มะรืน(?:นี้)?\#(tail)"#,
      #"\#(thaiNotAfterCompound)(?:(?:ตอน|ช่วง)\s*)?(?:เช้า|บ่าย|เย็น|ค่ำคืน|ค่ำ|คืน|ดึก)นี้"#,
      #"(?<![\p{L}\p{M}\p{N}])(?:(?:ตอน|ช่วง)\s*)?\#(partNames)\s*(?:ของ)?\s*\#(dayWords)"#,
    ])
    return alternatives
  }

  // MARK: - Due day

  /// The words that introduce a due day: "ภายใน", "ไม่เกิน", "ก่อน", "จนถึง",
  /// "เดดไลน์", "กำหนดส่ง", "ครบกำหนด", each with its colon or space.
  static let thaiDueLead =
    #"(?<!เมื่อ)(?<!แต่)(?<!ตั้งแต่)(?:ภายใน|ไม่เกิน|ก่อน|จนถึง|เดดไลน์|deadline|กำหนดส่ง|ครบกำหนด)\s*(?::\s*)?"#

  /// The days a phrase may name right after a word that introduces a due day,
  /// as the alternatives of a pattern without groups.
  static var thaiDaysAfterLead: String {
    thaiDayAlternatives(afterLead: true).joined(separator: "|")
  }

  /// "ภายในวันศุกร์", "ก่อนวันศุกร์", "ภายในพรุ่งนี้", "ภายใน 15 ตุลาคม", "ภายในสัปดาห์หน้า",
  /// "ภายใน 3 วัน", "เดดไลน์วันศุกร์", "กำหนดส่ง 15/10", and a day before a clock
  /// written as a deadline ("พรุ่งนี้ก่อน 5 โมงเย็น"). Groups: 1 the day after a
  /// word that introduces it; 2 the day before a deadline clock.
  static var thaiDuePattern: String {
    let plain = thaiDayAlternatives(afterLead: false).joined(separator: "|")
    return
      #"\#(thaiStart)(?:\#(thaiDueLead)(\#(thaiDaysAfterLead))|(\#(plain))\#(thaiBeforeDeadlineClock))\#(thaiEnd)"#
  }

  static func thaiDue(_ match: Match) -> Day? {
    guard let phrase = match.group(1) ?? match.group(2) else { return nil }
    return thaiDay(phrase, in: match).map { Day(offset: $0.offset) }
  }

  // MARK: - Planned day

  /// "วันนี้", "พรุ่งนี้" (maybe with a part of the day: "พรุ่งนี้เช้า"), "มะรืนนี้",
  /// "คืนนี้", "เย็นนี้", "วันศุกร์", "วันศุกร์นี้", "วันศุกร์หน้า", "ศุกร์หน้า",
  /// "สัปดาห์หน้า", "อาทิตย์หน้า", "สัปดาห์หน้าวันศุกร์", "สุดสัปดาห์", "เสาร์อาทิตย์", "อีก
  /// 3 วัน", "อีกสัปดาห์", and a date ("15 ตุลาคม", "วันที่ 15 ตุลาคม", "15/10/2569",
  /// "วันศุกร์ที่ 16 ตุลาคม", "วันที่ 15/10"). Group 1: the day, with the words that
  /// introduce it.
  static var thaiWhenPattern: String {
    #"\#(thaiStart)\#(thaiNotAfterBound)(\#(thaiDayAlternatives(afterLead: false).joined(separator: "|")))\#(thaiEnd)"#
  }

  /// What may not stand before a planned day: "ถึง" (to, until) or "ตั้งแต่"
  /// (from, since), which make the day the end or the start of a stretch of
  /// time and no day of its own ("ส่งงานถึงวันศุกร์", "ส่งงานตั้งแต่วันศุกร์").
  private static let thaiNotAfterBound = #"(?<!(?:ถึง|ตั้งแต่)\s{0,2})"#

  static func thaiWhen(_ match: Match) -> Day? {
    match.group(1).flatMap { thaiDay($0, in: match) }
  }

  // MARK: - Reading a day

  /// The day a phrase names: the phrase of a rule's match, with the words that
  /// introduce it. Nil when it names no day or names a date the calendar lacks.
  private static func thaiDay(_ phrase: String, in match: Match) -> Day? {
    let isEvening = thaiMatches(#"(?:ค่ำ|คืน|ดึก)"#, phrase)
    if let found = thaiFirstGroups(
      #"^(?:อีก\s*)?(\d{1,3}|\#(thaiNumberWords))\s*(วัน|สัปดาห์|อาทิตย์)"#, in: phrase),
      let count = found[1].flatMap(thaiCount), let unit = found[2]
    {
      return Day(offset: unit == "วัน" ? count : count * 7)
    }
    if thaiMatches(#"^อีก\s*(?:สัปดาห์|อาทิตย์)"#, phrase) { return Day(offset: 7) }
    if let found = thaiExplicitDate(phrase, in: match) {
      guard let today = match.today, let days = offset(to: found, from: today) else { return nil }
      return Day(offset: days)
    }
    // A number before a month name that is no date ("32 ตุลาคมนี้") names no
    // day, whatever else the phrase holds.
    if thaiMatches(#"\d\s*\#(thaiMonthNames)"#, phrase) { return nil }
    if let found = thaiFirstGroups(#"^(?:ใน)?วันที่\s*(\d{1,2})$"#, in: phrase), let day = found[1].flatMap(number) {
      guard let today = match.today, let days = offset(to: ExplicitDate(day: day), from: today) else { return nil }
      return Day(offset: days)
    }
    if let found = thaiFirstGroups(#"^(?:วัน)?(\#(thaiWeekdayNames))\s*ที่\s*(\d{1,2})$"#, in: phrase),
      let name = found[1], let weekday = thaiWeekdayIndex(name), let day = found[2].flatMap(number)
    {
      // A weekday with a day of the month ("วันอังคารที่ 29") names the next
      // such date, and only when that date falls on the weekday.
      guard let today = match.today, let days = offset(to: ExplicitDate(day: day), from: today),
        (match.todayWeekday - 1 + days) % 7 == weekday
      else { return nil }
      return Day(offset: days)
    }
    let todayWeekday = match.todayWeekday
    let weekendPair = #"เสาร์\s*[-–—]?\s*(?:และ\s*)?(?:วัน)?อาทิตย์"#
    if thaiMatches("สุดสัปดาห์|\(weekendPair)", phrase) {
      if thaiMatches(#"(?:หน้า|ถัดไป)"#, phrase) { return Day(offset: nextWeekOffset(6, todayWeekday: todayWeekday)) }
      if thaiMatches(#"ที่(?:กำลัง)?จะ?ถึง"#, phrase) {
        return Day(offset: comingWeekdayOffset(6, todayWeekday: todayWeekday))
      }
      return Day(offset: weekendOffset(todayWeekday: todayWeekday))
    }
    let weekdayPattern =
      #"(?:วัน(\#(thaiWeekdayNames))|(\#(thaiWeekdayNamesExceptSunday)))\s*(นี้|หน้า|ถัดไป|ที่(?:กำลัง)?จะ?ถึง)?"#
    if let found = thaiFirstGroups(weekdayPattern, in: phrase), let nameText = found[1] ?? found[2],
      let weekday = thaiWeekdayIndex(nameText)
    {
      let isNextWeek =
        thaiMatches(#"^(?:หน้า|ถัดไป)$"#, found[3] ?? "")
        || thaiMatches(#"(?:สัปดาห์|อาทิตย์)\s*(?:หน้า|ถัดไป)"#, phrase)
      if isNextWeek {
        return Day(offset: nextWeekOffset(weekday, todayWeekday: todayWeekday), isEvening: isEvening)
      }
      if found[3] == "นี้" {
        return Day(offset: weekdayDelta(weekday, todayWeekday: todayWeekday), isEvening: isEvening)
      }
      return Day(offset: comingWeekdayOffset(weekday, todayWeekday: todayWeekday), isEvening: isEvening)
    }
    if thaiMatches(#"(?:สัปดาห์|อาทิตย์)\s*(?:หน้า|ถัดไป)"#, phrase) { return Day(offset: 7) }
    if thaiMatches(#"มะรืน"#, phrase) { return Day(offset: 2, isEvening: isEvening) }
    if thaiMatches(#"พรุ[่้]งนี้"#, phrase) { return Day(offset: 1, isEvening: isEvening) }
    if thaiMatches(#"นี้"#, phrase) { return Day(offset: 0, isEvening: isEvening) }
    return nil
  }
}

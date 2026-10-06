import Foundation

extension LorvexCaptureVocabulary {
  /// Thai, read for a user who reads Thai. Thai is written without spaces between
  /// words, so a detail word is found by its syllables and not by a space. A
  /// phrase starts only where no leading vowel (เ แ โ ใ ไ) stands before it and
  /// ends only where no vowel sign or tone mark of its last consonant follows
  /// it, so "ประชุมพรุ่งนี้" plans "ประชุม" for tomorrow, "ส่งรายงานภายในวันศุกร์"
  /// is a title and a due day, and "สาม" in "สามัคคี" is no hour. A few words are
  /// checked by name on top of that boundary. A weekday name after "ดาว", "ดวง",
  /// "พระ", "คุณ", "นาย", or "นาง" is no day ("ดาวศุกร์" is Venus, "พระจันทร์" the
  /// moon), and a part of the day glued to the word before it belongs to that
  /// word ("ข้าวเย็น" is dinner, "ส่งคืน" is to return something). "ด่วน",
  /// "สำคัญ", and "เที่ยง" are read only as words of their own, with a space,
  /// punctuation, or an end of the line on both sides ("ทางด่วน" is an
  /// expressway, "เอกสารสำคัญ" a kind of document, "ข้าวเที่ยง" lunch). A phrase
  /// taken out from between two Thai words leaves one space between them.
  ///
  /// The line is read as typed. Digits are Arabic or Thai (๐-๙). A year of 2400
  /// or more is Buddhist Era, the Christian year plus 543 ("2569" is 2026), and
  /// "พ.ศ." and "ค.ศ." name the era outright. Each pattern spells a word with its
  /// vowel sign before its tone mark, and the sara am "ำ" also matches the
  /// nikhahit and sara aa that some keyboards write in its place.
  ///
  /// - Day: วันนี้, พรุ่งนี้, มะรืนนี้, มะรืน, each maybe with a part of the day
  ///   after it (พรุ่งนี้เช้า, วันศุกร์ตอนเย็น), and คืนนี้, เย็นนี้, เช้านี้,
  ///   บ่ายนี้; the weekday names with "วัน" (วันศุกร์, วันพฤหัส), and every name
  ///   but Sunday without it where "นี้" or "หน้า" follows (ศุกร์นี้, ศุกร์หน้า),
  ///   since "อาทิตย์" alone is the word for a week; วันศุกร์นี้, วันศุกร์หน้า,
  ///   วันศุกร์ที่จะถึง, สัปดาห์หน้า, อาทิตย์หน้า, สัปดาห์หน้าวันพุธ,
  ///   วันพุธสัปดาห์หน้า, สุดสัปดาห์ (maybe with นี้ or หน้า), เสาร์อาทิตย์,
  ///   อีก 3 วัน, อีก 2 สัปดาห์, อีกสัปดาห์; a date: 15 ตุลาคม, 15 ต.ค.,
  ///   15 ตุลาคมนี้, 15 ตุลาคม 2569, 15 ต.ค. พ.ศ. 2569, ๑๕ ตุลาคม ๒๕๖๙,
  ///   15/10/2569, 15-10-2026, with a weekday before it (วันศุกร์ที่ 16 ตุลาคม),
  ///   and after "วันที่" or a deadline word the short 15/10 ("วันที่ 15/10").
  ///   "วันที่ 15" with no month is that day of this month, or of the next once
  ///   it has passed, and "วันอังคารที่ 29" is the next 29th when it falls on a
  ///   Tuesday. A weekday alone is the next such day, a full week ahead when it
  ///   names today; with "นี้" it is the coming one counting today; with "หน้า"
  ///   it is next week's, weeks starting on Monday. "สุดสัปดาห์" is the coming
  ///   Saturday. A day after "ถึง" or "ตั้งแต่" ("ส่งงานถึงวันศุกร์",
  ///   "ส่งงานตั้งแต่วันศุกร์") is the end or the start of a stretch of time and
  ///   names no planned day. A past day or week (เมื่อวาน, เมื่อคืน, เมื่อเช้า,
  ///   วันศุกร์ที่แล้ว, สัปดาห์ที่แล้ว, 3 วันก่อน) is never read and stays in the
  ///   title with the clock time that follows it. "ทุกวันนี้" (nowadays) and an
  ///   ordinal weekday of the month ("วันพุธที่สองของเดือน") stay whole.
  /// - Date range: 3-5 พฤษภาคม, 3 ถึง 5 พฤษภาคม, ตั้งแต่ 3 ถึง 5 พฤษภาคม,
  ///   จาก 3 ถึง 5 พฤษภาคม, 30 พฤษภาคม - 2 มิถุนายน, 3-5 พ.ค. 2570; a span of
  ///   weekdays: ตั้งแต่วันศุกร์ถึงวันอาทิตย์, วันศุกร์-อาทิตย์. The first day is
  ///   the planned day and the last the due day. The months are written in full
  ///   or with the abbreviations ม.ค. ก.พ. มี.ค. เม.ย. พ.ค. มิ.ย. ก.ค. ส.ค. ก.ย.
  ///   ต.ค. พ.ย. ธ.ค., and a month may be followed by "นี้" (this), which goes
  ///   with the date ("15 ตุลาคมนี้", "3-5 พฤษภาคมนี้").
  /// - Repeat: ทุกวัน, ทุกสัปดาห์, ทุกอาทิตย์, ทุกเดือน, ทุกปี, ทุกเช้า, ทุกเย็น,
  ///   ทุกวันจันทร์, ทุกจันทร์, ทุกวันจันทร์และวันพุธ, ทุกสัปดาห์วันศุกร์,
  ///   ทุก 2 วัน, ทุก 2 สัปดาห์, ทุกสองเดือน, ทุก 2 สัปดาห์วันศุกร์, ทุกๆ 2 วัน,
  ///   วันเว้นวัน, สัปดาห์เว้นสัปดาห์, วันละครั้ง, สัปดาห์ละครั้ง, ทุกวันทำงาน,
  ///   ทุกวันทำการ, ทุกวันจันทร์ถึงวันศุกร์, ทุกสุดสัปดาห์, ทุกเสาร์อาทิตย์,
  ///   ทุกไตรมาส, ทุกครึ่งปี, ทุกวันที่ 15, ทุกเดือนวันที่ 15, วันที่ 15 ของเดือน.
  ///   Whole weeks counted in days are a weekly repeat ("ทุก 14 วัน").
  ///   "ทุกวันหยุด", "ทุกวันเกิด", "ทุกวันนี้", "สัปดาห์ละ 2 ครั้ง", and the
  ///   weekdays of a month ("ทุกวันศุกร์สุดท้ายของเดือน") name no repeat the app
  ///   can set and stay.
  /// - Due: ภายใน, ไม่เกิน, ก่อน, จนถึง, เดดไลน์, deadline, กำหนดส่ง, or ครบกำหนด
  ///   before a day ("ภายในวันศุกร์", "ก่อนพรุ่งนี้", "ภายใน 15 ตุลาคม",
  ///   "ภายใน 3 วัน", "เดดไลน์: วันศุกร์", "กำหนดส่ง 15/10"). A clock time
  ///   written as a bound ("ก่อน 5 โมงเย็น", "ภายใน 17:00 น.", "ไม่เกินบ่ายสาม",
  ///   "หลังเที่ยง", "ตั้งแต่ 9 โมงเป็นต้นไป") is no start time and stays in the
  ///   title, and the day before it is the due day.
  /// - Time: the traditional clock, บ่ายสามโมง, สี่โมงเย็น, หกโมงเช้า, 3 โมง,
  ///   3 โมง 15 นาที, บ่ายโมง, บ่ายสาม, สองทุ่ม, ห้าทุ่ม, ตีหนึ่ง, ตีห้า, เที่ยง,
  ///   เที่ยงคืน, and the 24-hour clock with a unit, 15:00 น., 15.30 น., 9 น.,
  ///   15 นาฬิกา, each maybe after ตอน, เวลา, or ประมาณ; "ครึ่ง" after an hour
  ///   adds thirty minutes to it (บ่ายสามครึ่ง, 3 โมงครึ่ง, ทุ่มครึ่ง are 15:30,
  ///   15:30, 19:30); a range: 10:00-11:00 น., 9-11 โมงเช้า, บ่ายสองถึงสี่โมง,
  ///   ตั้งแต่ 9 โมงถึง 11 โมง. An hour of โมง with no part of the day takes the
  ///   part of the day the line names beside it ("พรุ่งนี้เย็น 7 โมง" is
  ///   19:00); with none, 1 to 6 o'clock is the afternoon and 7 to 11 the
  ///   morning. เช้า goes with 6 to 11, บ่าย with 1 to 6, and เย็น with 3 to
  ///   11, and an hour a part never goes with ("สองโมงเช้า") is no time.
  ///   "เที่ยงคืน" is the midnight that ends the day, so it plans the day after
  ///   the one named (tomorrow, when none is), and an hour of ตี after "คืนนี้"
  ///   or another evening day is the small hours of the day after it. A time
  ///   with น. or นาฬิกา is on the 24-hour clock ("3.30 น." is 03:30). A time
  ///   with no Thai word or unit ("15:30", "3pm") is left to English. An amount
  ///   of minutes right after an hour is its minutes ("บ่ายสามโมง 30 นาที" is
  ///   15:30), so a length beside a time needs an opener such as ใช้เวลา.
  /// - Length: 30 นาที, 1 ชั่วโมง, 1 ชม., 1.5 ชั่วโมง, ครึ่งชั่วโมง, ชั่วโมงครึ่ง,
  ///   1 ชั่วโมงครึ่ง, 2 ชั่วโมง 30 นาที, สามสิบนาที, หนึ่งชั่วโมง, each maybe
  ///   after ใช้เวลา, ระยะเวลา, นาน, or ประมาณ. An amount that names a moment, a
  ///   bound, the past, or a rate ("อีก 30 นาที", "ภายใน 2 ชั่วโมง",
  ///   "ทุก 30 นาที", "30 นาทีที่แล้ว", "วันละ 2 ชั่วโมง", "2-3 ชั่วโมง") is no
  ///   length, and neither are a single spelled minute and an amount over
  ///   twenty-four hours.
  /// - Priority: ด่วน, ด่วนมาก, ด่วนที่สุด, เร่งด่วน, สำคัญ, สำคัญมาก, สำคัญที่สุด
  ///   (high); ไม่ด่วน, ไม่เร่งด่วน, ไม่สำคัญ, ไม่ด่วนมาก (low); ความสำคัญสูง,
  ///   ความสำคัญปานกลาง, ความสำคัญต่ำ, ลำดับความสำคัญ: สูง, ความสำคัญ 1. A
  ///   repetition mark ๆ after the word belongs to it ("ด่วนมากๆ"), and a word
  ///   that goes on into a comparison ("สำคัญมากกว่า") is no priority.
  static let thai = LorvexCaptureVocabulary(
    priority: [thaiRule(thaiPriorityPattern, read: thaiPriority)],
    dateRange: [
      thaiRule(thaiDateRangePattern, read: thaiDateRange),
      thaiRule(thaiWeekdayRangePattern, read: thaiWeekdayRange),
    ],
    keptInTitle: [
      thaiRule(thaiPastPattern) { _ in true },
      thaiRule(thaiNowadaysPattern) { _ in true },
      thaiRule(thaiOrdinalWeekdayPattern) { _ in true },
      thaiRule(thaiDeadlineClockPattern) { $0.group(1) == nil ? nil : true },
      thaiRule(thaiDueClockPattern) { thaiIsClockAfterDueDay($0) ? true : nil },
      thaiRule(thaiLengthPattern) { thaiClaimsLength($0) ? true : nil },
    ],
    length: [thaiRule(thaiLengthPattern, read: thaiLength)],
    time: [
      thaiRule(thaiTimeRangePattern, read: thaiTimeRange),
      thaiRule(thaiTimePattern, read: thaiTime),
    ],
    repeats: thaiRepeatRules,
    due: [thaiRule(thaiDuePattern, read: thaiDue)],
    when: [thaiRule(thaiWhenPattern, read: thaiWhen)])

  // MARK: - Rules and patterns

  /// A rule for `pattern`, in which each sara am "ำ" also matches the
  /// nikhahit and sara aa that some keyboards and pasted texts write in its
  /// place ("สำคัญ", "สํา" + "คัญ").
  static func thaiRule<Value>(
    _ pattern: String, read: @escaping @Sendable (Match) -> Value?
  ) -> Rule<Value> {
    Rule(pattern: thaiSaraAm(pattern), read: read)
  }

  /// `pattern` with each sara am "ำ" in it also matching its two-code-point
  /// spelling.
  static func thaiSaraAm(_ pattern: String) -> String {
    pattern.replacingOccurrences(of: "ำ", with: "(?:ำ|\u{0E4D}\u{0E32})")
  }

  /// `pattern` with every capture group made non-capturing, so a pattern
  /// written with groups for a reader to take apart can also stand inside a
  /// bigger pattern without shifting its group numbers.
  static func thaiNonCapturing(_ pattern: String) -> String {
    var result = ""
    var isEscaped = false
    var isInSet = false
    let characters = Array(pattern)
    for (index, character) in characters.enumerated() {
      result.append(character)
      if isEscaped {
        isEscaped = false
      } else if character == "\\" {
        isEscaped = true
      } else if isInSet {
        isInSet = character != "]"
      } else if character == "[" {
        isInSet = true
      } else if character == "(", index + 1 < characters.count, characters[index + 1] != "?" {
        result += "?:"
      }
    }
    return result
  }

  /// The capture groups of `pattern` matched against all of `text`, or nil
  /// when it does not match. Group 0 is the whole text. A reader matches by
  /// regular expression and not by `String` comparison, which compares
  /// characters, and a Thai consonant with its vowel and tone marks is one
  /// character that a literal cut in the middle would miss.
  static func thaiGroups(_ pattern: String, in text: String) -> [String?]? {
    thaiFirstGroups("^(?:\(pattern))$", in: text)
  }

  /// The capture groups of the first match of `pattern` in `text`, or nil
  /// when it does not match. Group 0 is the whole match.
  static func thaiFirstGroups(_ pattern: String, in text: String) -> [String?]? {
    guard let regex = LorvexCapturePatterns.regex(thaiSaraAm(pattern)),
      let result = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
    else { return nil }
    return (0..<result.numberOfRanges).map { index in
      let range = result.range(at: index)
      guard range.location != NSNotFound, let bounds = Range(range, in: text) else { return nil }
      return String(text[bounds])
    }
  }

  /// Whether `pattern` matches anywhere in `text`.
  static func thaiMatches(_ pattern: String, _ text: String) -> Bool {
    thaiFirstGroups(pattern, in: text) != nil
  }

  // MARK: - Boundaries

  /// What may not stand before a Thai phrase and after it for the phrase to
  /// begin and end on a syllable. A syllable's leading vowel (เ แ โ ใ ไ) is
  /// written before its consonant, and its other vowel signs and marks (ะ ั า ำ
  /// ิ ี ึ ื ุ ู ็ ่ ้ ๊ ๋ ์ ํ) after it, so a phrase never starts right after a
  /// leading vowel or ends right before a sign that belongs to its last
  /// consonant: "สาม" is no word of "สามัคคี" or "สามี". Thai has no spaces
  /// between words, so a detail word glued to the words of the title is still
  /// read: "ประชุมพรุ่งนี้" plans "ประชุม" for tomorrow.
  static let thaiStart = #"(?<![เ-ไ])"#
  static let thaiEnd = #"(?![ะ-ฺๅ็-๎])"#

  /// A boundary for a word that is read only as a word of its own: no letter,
  /// combining mark, or digit directly before or after it.
  static let thaiWordStart = #"(?<![\p{L}\p{M}\p{N}])"#
  static let thaiWordEnd = #"(?![\p{L}\p{M}\p{N}])"#

  /// How many characters before and after a match the rules that judge a match
  /// by its surroundings look at. A bounded look-around keeps the time a line
  /// takes linear in its length.
  static let thaiContextLength = 60

  /// The text of the line just before `match`: at most ``thaiContextLength``
  /// characters, ending where the match starts.
  static func thaiTextBefore(_ match: Match) -> String {
    guard let start = Range(match.result.range, in: match.source)?.lowerBound else { return "" }
    let from =
      match.source.index(start, offsetBy: -thaiContextLength, limitedBy: match.source.startIndex)
      ?? match.source.startIndex
    return String(match.source[from..<start])
  }

  /// The text of the match itself.
  static func thaiMatched(_ match: Match) -> String {
    guard let range = Range(match.result.range, in: match.source) else { return "" }
    return String(match.source[range])
  }

  // MARK: - Numbers

  /// The numbers Thai spells as words, from 1 to 99: the units (หนึ่ง, สอง,
  /// สาม, …; นึง is the colloquial one), the tens (สิบ, ยี่สิบ, สามสิบ, …), and
  /// the numbers between, where the unit one after a ten is เอ็ด ("สิบเอ็ด",
  /// "ยี่สิบเอ็ด") and สิบ alone is ten.
  private static let thaiSpelledNumbers: [String: Int] = {
    let units: [(word: String, value: Int)] = [
      ("หนึ่ง", 1), ("นึง", 1), ("สอง", 2), ("สาม", 3), ("สี่", 4), ("ห้า", 5), ("หก", 6), ("เจ็ด", 7), ("แปด", 8),
      ("เก้า", 9),
    ]
    let tens: [(prefix: String, value: Int)] = [
      ("", 10), ("ยี่", 20), ("สาม", 30), ("สี่", 40), ("ห้า", 50), ("หก", 60), ("เจ็ด", 70), ("แปด", 80), ("เก้า", 90),
    ]
    var words: [String: Int] = [:]
    for unit in units { words[unit.word] = unit.value }
    for ten in tens {
      words[ten.prefix + "สิบ"] = ten.value
      words[ten.prefix + "สิบเอ็ด"] = ten.value + 1
      for unit in units where unit.value >= 2 { words[ten.prefix + "สิบ" + unit.word] = ten.value + unit.value }
    }
    return words
  }()

  /// The numbers 1 to 99 as Thai spells them, as a pattern without groups. A
  /// number never starts inside a longer one, so "ห้า" in "สิบห้า" (fifteen) and
  /// "สิบ" in "สามสิบ" (thirty) are no numbers of their own when the longer one
  /// cannot be read from its start.
  static let thaiNumberWords =
    #"(?:(?:(?:ยี่|สาม|สี่|ห้า|หก|เจ็ด|แปด|เก้า)สิบ|(?<!ยี่|สอง|สาม|สี่|ห้า|หก|เจ็ด|แปด|เก้า)สิบ)(?:เอ็ด|สอง|สาม|สี่|ห้า|หก|เจ็ด|แปด|เก้า)?|(?<!สิบ)(?:หนึ่ง|นึง|สอง|สาม|สี่|ห้า|หก|เจ็ด|แปด|เก้า))"#

  /// The count a matched text names: digits of any script, or a number spelled
  /// as words.
  static func thaiCount(_ text: String) -> Int? {
    number(text) ?? thaiSpelledNumbers[text]
  }

  /// Every word ``thaiNumberWords`` is a pattern for, for a check that the two
  /// agree.
  static var thaiSpelledNumberWords: [String] { Array(thaiSpelledNumbers.keys) }

  /// The nouns and units a number counts, which make a number written beside
  /// them an amount and no time or date: "ตี 3 ชั้น", "บ่าย 2 คน".
  static let thaiCountedUnits =
    #"ชั่วโมง|นาที|วินาที|วัน|สัปดาห์|อาทิตย์|เดือน|ปี|คน|ครั้ง|ข้อ|อัน|ตัว|ชิ้น|บาท|เท่า|รอบ|ชั้น|ห้อง|แผ่น|เล่ม|ชุด|คู่|ใบ|ลูก|%"#

  // MARK: - Priority

  /// Group 1: a written priority ("ความสำคัญสูง", "ลำดับความสำคัญ: ต่ำ",
  /// "ความสำคัญ 1"); group 2: a word that makes the task low priority ("ไม่ด่วน",
  /// "ไม่เร่งด่วน", "ไม่สำคัญ", "ไม่ด่วนมาก", "ไม่ค่อยสำคัญ", "ไม่ได้ด่วน"); no
  /// group: a word that makes it high priority.
  /// The high words are "เร่งด่วน", "ด่วนมาก", "ด่วนที่สุด", "สำคัญมาก", and
  /// "สำคัญที่สุด" anywhere, glued to the words around them or not, and "ด่วน"
  /// and "สำคัญ" as words of their own: with a space or the start of the line
  /// before them and a space, punctuation, or the end of the line after them.
  /// Glued to another word they belong to a compound that names something else
  /// ("ทางด่วน" is an expressway, "รถด่วน" an express train, "เอกสารสำคัญ" a kind
  /// of document). A repetition mark "ๆ" after a priority word ("ด่วนมากๆ")
  /// belongs to it. A priority word that goes on into a comparison
  /// ("สำคัญมากกว่า", "ไม่สำคัญเท่า": more important than, not as important as) is
  /// no priority.
  private static var thaiPriorityPattern: String {
    let high = "สูงสุด|สูงที่สุด|สูง|มากที่สุด|มาก"
    let medium = "ปานกลาง|กลาง"
    let low = "ต่ำสุด|ต่ำที่สุด|ต่ำ|น้อยที่สุด|น้อย"
    let comparison = "(?!กว่า|เท่า)"
    let written =
      #"(?:(?:ระดับ|ลำดับ)?ความสำคัญ(?:ระดับ)?\s*[=:]?\s*(?:(?:\#(high)|\#(medium)|\#(low))\#(thaiEnd)\#(comparison)|[1-3๑-๓](?![\p{N}]))|ลำดับความสำคัญ\s*(?:ที่\s*)?[1-3๑-๓](?![\p{N}]))"#
    let lowWords = #"ไม่(?:ได้|ค่อย)?(?:(?:เร่ง)?ด่วน|สำคัญ)(?:มาก|นัก)?"#
    let highPhrases = #"เร่งด่วน(?:ที่สุด|มาก)?|ด่วน(?:ที่สุด|มาก)|สำคัญ(?:ที่สุด|มาก)"#
    let highWords = #"ด่วน|สำคัญ"#
    let mark = "(?:ๆ)?"
    let end = #"\#(thaiEnd)\#(comparison)"#
    return
      #"\#(thaiStart)(\#(written))|\#(thaiStart)(\#(lowWords))\#(mark)\#(end)|\#(thaiStart)(?:\#(highPhrases))\#(mark)\#(end)|\#(thaiWordStart)(?:\#(highWords))\#(mark)\#(thaiWordEnd)"#
  }

  private static func thaiPriority(_ match: Match) -> LorvexTask.Priority? {
    if match.group(2) != nil { return .p3 }
    guard let phrase = match.group(1) else { return .p1 }
    if let digit = phrase.last(where: { "123๑๒๓".contains($0) }) {
      return "1๑".contains(digit) ? .p1 : ("2๒".contains(digit) ? .p2 : .p3)
    }
    if thaiMatches(#"(?:ปานกลาง|กลาง)$"#, phrase) { return .p2 }
    if thaiMatches(#"(?:ต่ำสุด|ต่ำที่สุด|ต่ำ|น้อยที่สุด|น้อย)$"#, phrase) { return .p3 }
    return .p1
  }

  // MARK: - Length

  /// The words that open a length and go with it: "ใช้เวลา 2 ชั่วโมง",
  /// "ระยะเวลา 30 นาที", "เป็นเวลา 1 ชั่วโมง", "นาน 45 นาที".
  private static let thaiLengthOpener = #"(?:ใช้เวลา|ระยะเวลา|ความยาว|เป็นเวลา|นาน)"#

  /// "ประมาณ" and "ราว", which say a length is a round figure.
  private static let thaiApproximately = #"(?:ประมาณ|ราว(?:ๆ)?)"#

  /// The words before an amount that make it a moment, an interval, a bound, or
  /// the time that passed rather than a length: "อีก 30 นาที" (in 30 minutes),
  /// "ภายใน 2 ชั่วโมง", "ทุก 30 นาที", "หลัง 2 ชั่วโมง", "ก่อน 1 ชั่วโมง", "อย่างน้อย
  /// 2 ชั่วโมง", "ผ่านไป 10 นาที", "วันละ 2 ชั่วโมง" (a rate).
  private static let thaiLengthDecliner =
    #"ภายใน|ผ่านไป|อย่างน้อย|ไม่เกิน|ทุก(?:ๆ)?|หลังจาก|หลัง|ก่อน|เกิน|ครบ|อีก|ใน|เมื่อ|ล่วงหน้า|(?:วัน|สัปดาห์|อาทิตย์|เดือน|ปี)ละ"#

  /// The words glued to an amount that make it a moment, the past, a bound, or a
  /// rate: "30 นาทีก่อน", "30 นาทีที่แล้ว", "2 ชั่วโมงต่อวัน", "2 ชั่วโมงกว่า".
  private static let thaiLengthTrailing =
    #"ก่อน|หลัง|ที่แล้ว|ที่ผ่านมา|ต่อ|ละ|ข้างหน้า|เศษ|กว่า|ขึ้นไป|ล่วงหน้า|ถัดไป|เป็นต้นไป"#

  /// The unit "ชั่วโมง" and its abbreviation "ชม." ("ชม" with no period is
  /// read only as a word of its own, since "ชม" also means to admire).
  private static let thaiHours = #"(?:ชั่วโมง|ชม\.|ชม(?![\p{L}\p{M}\p{N}]))"#

  /// The amounts a length is written as, as a pattern without groups: "30
  /// นาที", "สามสิบนาที", "1 ชั่วโมง", "1.5 ชั่วโมง", "ครึ่งชั่วโมง", "ชั่วโมงครึ่ง",
  /// "1 ชั่วโมงครึ่ง", "1 ชั่วโมง 30 นาที", "ชั่วโมงนึง".
  private static var thaiLengthAmount: String {
    let count = #"(?:\d{1,4}|\#(thaiNumberWords))"#
    return [
      #"\#(count)\s*\#(thaiHours)\s*(?:ครึ่ง|(?:และ\s*)?\#(count)\s*นาที)"#,
      #"ครึ่ง\s*\#(thaiHours)"#,
      #"\#(thaiHours)(?:ครึ่ง|นึง|หนึ่ง)"#,
      #"(?:\d{1,4}(?:\.\d+)?|\#(thaiNumberWords))\s*\#(thaiHours)"#,
      #"\#(thaiNotAfterClockHour)\#(count)\s*นาที"#,
    ].joined(separator: "|")
  }

  /// What may not stand right before an amount of minutes for it to be a
  /// length: the unit of an hour of a clock time ("3 โมง 15 นาที", "สองทุ่มสิบห้า
  /// นาที", "ตี 3 15 นาที"), whose minutes the time rules read. An amount of
  /// hours after a clock time is a length ("บ่ายสามโมง 2 ชั่วโมง").
  private static var thaiNotAfterClockHour: String {
    #"(?<!(?:โมง|ทุ่ม|นาฬิกา|ครึ่ง)\s{0,2})(?<!ตี\s{0,2}(?:\d{1,2}|\#(thaiNumberWords))\s{0,2})"#
  }

  /// "30 นาที", "สามสิบนาที", "1 ชั่วโมง", "ครึ่งชั่วโมง", "ชั่วโมงครึ่ง", "1 ชั่วโมง
  /// 30 นาที", each maybe after an opener ("ใช้เวลา", "นาน", "ประมาณ") and before
  /// "โดยประมาณ". Groups: 1 a word before the amount that makes it a moment, an
  /// interval, or a bound; 2 the amount; 3 a word glued after it that makes it
  /// a moment, the past, or a rate. A match with group 1 or 3 is no length: the
  /// reader declines it and the title keeps it. The amount may not follow a
  /// digit, a colon, or a separator, and an amount that is a side of a range
  /// ("2-3 ชั่วโมง", "สองถึงสามชั่วโมง", "2 หรือ 3 ชั่วโมง") is no length.
  static var thaiLengthPattern: String {
    #"\#(thaiStart)(?:(\#(thaiLengthDecliner))\s*)?(?:\#(thaiLengthOpener)\s*)?(?:\#(thaiApproximately)\s*)?(?<![\p{N}:.,/])(?<!(?:ถึง|หรือ|[-–—~])\s{0,2})(\#(thaiLengthAmount))\#(thaiEnd)(?![\p{N}])(?!\s*[-–—~]\s*\d)(?:โดยประมาณ)?(?:(\#(thaiLengthTrailing)))?"#
  }

  /// Whether a match of ``thaiLengthPattern`` is kept in the title whole: it
  /// names a moment, an interval, a bound, the past, or a rate.
  static func thaiClaimsLength(_ match: Match) -> Bool {
    match.group(1) != nil || match.group(3) != nil
  }

  private static func thaiLength(_ match: Match) -> Int? {
    if thaiClaimsLength(match) { return nil }
    guard let amount = match.group(2) else { return nil }
    return thaiLengthMinutes(amount)
  }

  /// The minutes an amount of ``thaiLengthPattern`` names, or nil when it names
  /// none a task can take. A spelled one minute ("หนึ่งนาที") is left out: it
  /// is as often "a moment".
  private static func thaiLengthMinutes(_ amount: String) -> Int? {
    let count = #"(\d{1,4}|\#(thaiNumberWords))"#
    let hours = #"(?:ชั่วโมง|ชม\.?)"#
    if let found = thaiGroups(#"\#(count)\s*\#(hours)\s*(?:ครึ่ง|(?:และ\s*)?\#(count)\s*นาที)"#, in: amount),
      let whole = found[1].flatMap(thaiCount)
    {
      let rest = found[2].flatMap(thaiCount) ?? 30
      return taskLength(minutes: whole * 60 + rest)
    }
    if thaiGroups(#"ครึ่ง\s*\#(hours)"#, in: amount) != nil { return 30 }
    if thaiGroups(#"\#(hours)ครึ่ง"#, in: amount) != nil { return 90 }
    if thaiGroups(#"\#(hours)(?:นึง|หนึ่ง)"#, in: amount) != nil { return 60 }
    if let found = thaiGroups(#"(\d{1,4}(?:\.\d+)?|\#(thaiNumberWords))\s*\#(hours)"#, in: amount),
      let text = found[1]
    {
      if let hoursAmount = decimalAmount(text) { return taskLength(minutes: Int((hoursAmount * 60).rounded())) }
      return thaiCount(text).flatMap { taskLength(minutes: $0 * 60) }
    }
    if let found = thaiGroups(#"\#(count)\s*นาที"#, in: amount), let text = found[1] {
      if text == "หนึ่ง" || text == "นึง" { return nil }
      return thaiCount(text).flatMap { taskLength(minutes: $0) }
    }
    return nil
  }
}

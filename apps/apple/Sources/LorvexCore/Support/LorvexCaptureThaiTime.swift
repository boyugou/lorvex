import Foundation

extension LorvexCaptureVocabulary {
  // The Thai clock-time rules: the traditional clock (โมง, ทุ่ม, ตี, เที่ยง),
  // times with the unit น. or นาฬิกา, ranges, and the rules that keep a deadline
  // written as a clock time in the title. The vocabulary's other words are in
  // ``thai``.

  // MARK: - Words around a clock time

  /// An hour as a number: digits or a number spelled as words. A reader checks
  /// the range the form allows.
  private static let thaiHour = #"(?:\d{1,2}|\#(thaiNumberWords))"#

  /// The words that introduce a clock time and go with it: "ตอน" (at the time
  /// of), "เวลา" (time), "ประมาณ" and "ราว" (about). They are part of the
  /// phrase, so they leave the title with the time.
  static let thaiTimeLead = #"(?:(?:ตอน|เวลา|ประมาณ|ราว(?:ๆ)?)\s*){0,3}"#

  /// What may follow a clock time: no vowel sign, digit, or colon (the word or
  /// the number goes on), no decimal fraction, no slash and digit (which makes
  /// it a date), no percent or currency sign with or without a space before it,
  /// and no dash before a digit, which makes the time one side of a range
  /// written with a dash.
  static let thaiTimeEnd = #"\#(thaiEnd)(?![\p{N}:]|[.,/]\p{N}|\s*[%\p{Sc}]|\s*[-–—]\s*\d)"#

  /// The unit of a time on the 24-hour clock: "น." and "น" (short for นาฬิกา,
  /// which also names a clock or watch), and "นาฬิกา" itself. A bare "น" is the
  /// unit only as a word of its own, since many words begin with it.
  private static let thaiClockUnit =
    #"(?:น\.|น(?![\p{L}\p{M}\p{N}])|นาฬิกา(?!ข้อมือ|ปลุก|แขวน|ทราย|พก))"#

  /// The words before "เที่ยง" that make it noon and no part of a longer word
  /// ("ข้าวเที่ยง" is lunch, "พักเที่ยง" a lunch break): the start of a word, or a
  /// word that introduces a time or a day.
  private static var thaiNoonStart: String {
    #"(?:(?<![\p{L}\p{M}\p{N}])|(?<=ตอน|เวลา|ช่วง|นี้|หน้า|ถึง|ตั้งแต่|จาก|ประมาณ|ราว|ราวๆ|ก่อน|หลัง|ภายใน|เกิน|มะรืน|พรุ่งนี้|วันนี้|\#(thaiWeekdayNames)))"#
  }

  // MARK: - Clock forms

  /// One way a clock time is written.
  private enum ThaiClockForm: CaseIterable, Sendable {
    /// "สามโมง", "บ่ายสามโมง", "สี่โมงเย็น", "บ่ายโมง", "สิบโมงครึ่ง", "3 โมง 15 นาที"
    case moong
    /// "บ่ายสอง", "บ่ายสามครึ่ง"
    case afternoon
    /// "สองทุ่ม", "สามทุ่มครึ่ง", "ทุ่มตรง"
    case thum
    /// "ตีหนึ่ง", "ตีห้า", "ตีสองครึ่ง"
    case tee
    /// "เที่ยงคืน"
    case midnight
    /// "เที่ยง", "เที่ยงวัน", "เที่ยงครึ่ง", "เที่ยงตรง"
    case noon
    /// "15:00 น.", "15.00 น.", "09.30น"
    case unitColon
    /// "15 นาฬิกา", "สิบห้านาฬิกาสามสิบนาที"
    case unitHours
    /// "9 น."
    case unitDot
    /// "เวลา 15:00", "ตอน 9.30"
    case leadColon
  }

  /// A part of the day a clock time may carry.
  private enum ThaiPart: Sendable {
    case morning, afternoon, evening
  }

  /// How a clock time's unit reads its hour.
  private enum ThaiClockUnit: Sendable {
    /// โมง, with or without a part of the day; a 12-hour clock counted from
    /// six in the morning and from one in the afternoon.
    case moong
    /// ทุ่ม: the evening hours 19:00 to 23:00, counted from one.
    case thum
    /// ตี: the small hours, 01:00 to 05:00.
    case tee
    case midnight
    case noon
    /// น. and นาฬิกา: the hour as written on a 24-hour clock.
    case clock24
    /// A time written with a colon and no unit, after "เวลา" or "ตอน".
    case bare
  }

  /// A clock time as a phrase spells it, before it is placed on the clock.
  private struct ThaiParsedClock: Sendable {
    var unit: ThaiClockUnit
    var hour: Int
    var minute: Int
    var part: ThaiPart? = nil
    var hasLeadingZero = false
  }

  /// "ครึ่ง" (half past) or minutes counted with "นาที": groups 1 and 2. A "ครึ่ง"
  /// that begins "ครึ่งชั่วโมง" (half an hour) is a length and no half past.
  private static var thaiMinuteTail: String {
    #"(?:\s*(ครึ่ง)(?!\s*(?:ชั่วโมง|ชม(?![\p{L}\p{M}\p{N}])|ชม\.))|\s*(?:และ\s*)?(\#(thaiHour))\s*นาที)?"#
  }

  /// What may not stand before a part of the day that opens a clock time: "ทุก"
  /// (every), which makes "ทุกเย็น" a repeat and leaves "7 โมง" the time.
  private static let thaiNotAfterEvery = #"(?<!ทุก\s{0,2})(?<!ทุกๆ\s{0,2})"#

  private static func thaiFormPattern(_ form: ThaiClockForm) -> String {
    let parts = #"(เช้า|บ่าย|เย็น)"#
    let exact = #"(?:\s*ตรง(?![\p{L}\p{M}\p{N}]))?"#
    switch form {
    case .moong:
      // Groups: 1 the part before the hour, 2 its hour, 3 an hour with no part
      // before it, 4 "ครึ่ง", 5 the minutes, 6 the part after the time.
      return
        #"(?:\#(thaiNotAfterEvery)\#(parts)\s*(\#(thaiHour))?|(\#(thaiHour)))\s*โมง\#(thaiMinuteTail)(?:\s*(?:ตอน\s*)?\#(parts)\#(thaiPartEnd))?\#(exact)"#
    case .afternoon:
      // Groups: 1 hour, 2 "ครึ่ง", 3 the minutes.
      return
        #"\#(thaiNotAfterEvery)บ่าย\s*(\#(thaiHour))(?!\s*โมง)(?!\s*(?:\#(thaiCountedUnits)))\#(thaiMinuteTail)"#
    case .thum:
      // Groups: 1 hour, 2 "ครึ่ง", 3 the minutes.
      return
        #"(?:(\#(thaiHour))\s*ทุ่ม|ทุ่ม(?=\s*(?:ครึ่ง|ตรง)))\#(thaiMinuteTail)\#(exact)(?!เท)"#
    case .tee:
      // Groups: 1 hour, 2 "ครึ่ง", 3 the minutes.
      return
        #"ตี\s*(\#(thaiHour))(?!\s*(?:\#(thaiCountedUnits)))(?!เหลี่ยม|เส้น|แยก)\#(thaiMinuteTail)\#(exact)"#
    case .midnight:
      return #"เที่ยงคืน"#
    case .noon:
      // Groups: 1 "ครึ่ง" or "ตรง".
      return #"\#(thaiNoonStart)(?:เที่ยงวัน|เที่ยง)(?:\s*(ครึ่ง|ตรง))?\#(thaiPartEnd)"#
    case .unitColon:
      // Groups: 1 hour, 2 minutes.
      return #"(?<![\p{N}:.,])(\d{1,2})\s*[.:：]\s*(\d{2})\s*\#(thaiClockUnit)"#
    case .unitHours:
      // Groups: 1 hour, 2 "ครึ่ง", 3 the minutes.
      return #"(\#(thaiHour))\s*นาฬิกา(?!ข้อมือ|ปลุก|แขวน|ทราย|พก)\#(thaiMinuteTail)\#(exact)"#
    case .unitDot:
      // Groups: 1 hour.
      return #"(?<![\p{N}:.,])(\d{1,2})\s*น\."#
    case .leadColon:
      // Groups: 1 hour, 2 minutes.
      return
        #"(?:(?:ประมาณ|ราว(?:ๆ)?)\s*)?(?:ตอน|เวลา)\s*(\d{1,2})\s*[.:：]\s*(\d{2})(?![\p{N}])"#
    }
  }

  private static let thaiFormPatterns: [(form: ThaiClockForm, pattern: String)] =
    ThaiClockForm.allCases.map { ($0, thaiFormPattern($0)) }

  /// Every way a clock time is written, after the words that introduce it, as a
  /// pattern without groups.
  static let thaiClockAlternatives: String =
    "\(thaiTimeLead)(?:\(thaiFormPatterns.map { thaiNonCapturing($0.pattern) }.joined(separator: "|")))"

  // MARK: - Reading a clock time

  private static func thaiPart(_ text: String?) -> ThaiPart? {
    switch text {
    case "เช้า": .morning
    case "บ่าย": .afternoon
    case "เย็น": .evening
    default: nil
    }
  }

  /// The minutes a form's "ครึ่ง" and minute groups name: 30 for a half, the
  /// counted minutes, or 0 when neither is written. Nil for minutes that are no
  /// number from 0 to 59.
  private static func thaiMinutes(half: String?, minutes: String?) -> Int? {
    if half != nil { return 30 }
    guard let minutes else { return 0 }
    guard let value = thaiCount(minutes), (0...59).contains(value) else { return nil }
    return value
  }

  private static func thaiRead(_ form: ThaiClockForm, _ groups: [String?]) -> ThaiParsedClock? {
    func group(_ index: Int) -> String? { index < groups.count ? groups[index] : nil }
    switch form {
    case .moong:
      let hour: Int
      if let text = group(2) ?? group(3) {
        guard let value = thaiCount(text) else { return nil }
        hour = value
      } else if group(1) == "บ่าย" {
        hour = 1
      } else {
        return nil
      }
      guard let minute = thaiMinutes(half: group(4), minutes: group(5)) else { return nil }
      return ThaiParsedClock(unit: .moong, hour: hour, minute: minute, part: thaiPart(group(1) ?? group(6)))
    case .afternoon:
      guard let hour = group(1).flatMap(thaiCount), let minute = thaiMinutes(half: group(2), minutes: group(3)) else {
        return nil
      }
      return ThaiParsedClock(unit: .moong, hour: hour, minute: minute, part: .afternoon)
    case .thum:
      let hour = group(1).map { thaiCount($0) } ?? 1
      guard let hour, let minute = thaiMinutes(half: group(2), minutes: group(3)) else { return nil }
      return ThaiParsedClock(unit: .thum, hour: hour, minute: minute)
    case .tee:
      guard let hour = group(1).flatMap(thaiCount), let minute = thaiMinutes(half: group(2), minutes: group(3)) else {
        return nil
      }
      return ThaiParsedClock(unit: .tee, hour: hour, minute: minute)
    case .midnight:
      return ThaiParsedClock(unit: .midnight, hour: 0, minute: 0)
    case .noon:
      return ThaiParsedClock(unit: .noon, hour: 12, minute: group(1) == "ครึ่ง" ? 30 : 0)
    case .unitColon, .leadColon:
      guard let hourText = group(1), let hour = number(hourText), let minute = group(2).flatMap(number) else {
        return nil
      }
      return ThaiParsedClock(
        unit: form == .unitColon ? .clock24 : .bare, hour: hour, minute: minute,
        hasLeadingZero: startsWithZero(hourText))
    case .unitHours:
      guard let hour = group(1).flatMap(thaiCount), let minute = thaiMinutes(half: group(2), minutes: group(3)) else {
        return nil
      }
      return ThaiParsedClock(unit: .clock24, hour: hour, minute: minute)
    case .unitDot:
      guard let hourText = group(1), let hour = number(hourText) else { return nil }
      return ThaiParsedClock(unit: .clock24, hour: hour, minute: 0, hasLeadingZero: startsWithZero(hourText))
    }
  }

  /// The clock time a phrase spells, or nil when no form reads it.
  private static func thaiParseClock(_ text: String) -> ThaiParsedClock? {
    for (form, pattern) in thaiFormPatterns {
      guard let groups = thaiGroups("\(thaiTimeLead)(?:\(pattern))", in: text) else { continue }
      if let clock = thaiRead(form, groups) { return clock }
    }
    return nil
  }

  /// A side of a range written as a bare hour or a bare time ("9", "10:00",
  /// "3.30"), with the unit and the part of the day of the other side: "9-11
  /// โมงเช้า" is 9 to 11 in the morning and "10:00-11:00 น." is 10:00 to 11:00.
  private static func thaiBareSide(_ text: String, borrowing end: ThaiParsedClock) -> ThaiParsedClock? {
    guard let found = thaiGroups(#"(\d{1,2})(?:\s*[.:]\s*(\d{2}))?"#, in: text), let hourText = found[1],
      let hour = number(hourText)
    else { return nil }
    let minute = found[2].flatMap(number) ?? 0
    switch end.unit {
    case .moong, .thum, .clock24:
      return ThaiParsedClock(
        unit: end.unit, hour: hour, minute: minute, part: end.part, hasLeadingZero: startsWithZero(hourText))
    default:
      return nil
    }
  }

  // MARK: - The part of the day a line names

  /// A part of the day beside a day word anywhere in a line, as a pattern whose
  /// group 1, 2, or 3 is the part: "พรุ่งนี้เย็น", "ทุกเช้า", "เย็นวันศุกร์",
  /// "คืนนี้", and "เย็นนี้" (which a compound such as "ข้าวเย็นนี้" is not).
  private static var thaiLinePartPattern: String {
    let part = #"(เช้า|บ่าย|เย็น|ค่ำ|คืน|ดึก)"#
    let day = #"(?:วันนี้|พรุ[่้]งนี้|มะรืน(?:นี้)?|วัน(?:\#(thaiWeekdayNames))|ทุก(?:ๆ)?|สุดสัปดาห์|สัปดาห์หน้า)"#
    let named = #"(?:วันนี้|พรุ[่้]งนี้|มะรืน(?:นี้)?|วัน(?:\#(thaiWeekdayNames))|นี้)"#
    return
      #"\#(day)\s*(?:(?:ตอน|ช่วง)\s*)?\#(part)\#(thaiPartEnd)|(?<![\p{L}\p{M}\p{N}])(?:(?:ตอน|ช่วง)\s*)?\#(part)\s*(?:ของ\s*)?\#(named)|\#(thaiNotAfterCompound)(?:(?:ตอน|ช่วง)\s*)?\#(part)นี้"#
  }

  private static let thaiLinePartRegexPattern = thaiSaraAm(thaiLinePartPattern)

  /// The part of the day the line names beside `match` (within
  /// ``thaiContextLength`` characters of it), for an hour written without one:
  /// "พรุ่งนี้เย็น 7 โมง", "ทุกเย็น 7 โมง", and "คืนนี้ 8 โมง" are the evening
  /// hours where the hour alone would be 07:00 or 08:00. Nil when the line names
  /// no part of the day there, or names two that differ.
  private static func thaiLinePart(beside match: Match) -> String? {
    guard let regex = LorvexCapturePatterns.regex(thaiLinePartRegexPattern) else { return nil }
    let source = match.source
    let own = match.result.range
    let lower = max(0, own.location - thaiContextLength)
    let upper = min(source.utf16.count, NSMaxRange(own) + thaiContextLength)
    var named: String?
    for found in regex.matches(
      in: source, options: [.withTransparentBounds, .withoutAnchoringBounds],
      range: NSRange(location: lower, length: upper - lower))
    {
      guard NSIntersectionRange(found.range, own).length == 0 else { continue }
      let partRange = (1..<found.numberOfRanges).map { found.range(at: $0) }.first { $0.location != NSNotFound }
      guard let partRange, let range = Range(partRange, in: source) else { continue }
      let part = String(source[range])
      if let named, named != part { return nil }
      named = part
    }
    return named
  }

  /// The time an hour on the 12-hour clock names with a part of the day (the
  /// part an explicit phrase carries, or the one its line names elsewhere), or
  /// nil when the part has no such hour: the morning is 6 to 11 o'clock, the
  /// afternoon 1 to 6 (and noon), the evening 3 to 11, and the night 6 to 11
  /// (the small hours are written with ตี).
  private static func thaiTime(hour: Int, minute: Int, linePart part: String) -> ClockTime? {
    switch part {
    case "เช้า": return (6...11).contains(hour) ? partOfDayTime(hour: hour, minute: minute, part: .morning) : nil
    case "บ่าย": return partOfDayTime(hour: hour, minute: minute, part: .day)
    case "เย็น": return (3...11).contains(hour) ? partOfDayTime(hour: hour, minute: minute, part: .evening) : nil
    default: return (6...11).contains(hour) ? nightTime(hour: hour, minute: minute) : nil
    }
  }

  // MARK: - Placing a time on the clock

  /// The clock time a parsed phrase names, or nil for an hour its unit never
  /// carries.
  ///
  /// A bare hour of โมง (no part of the day) is the part the line names beside
  /// it ("พรุ่งนี้เย็น 7 โมง" is 19:00), else as
  /// ``bareTime(hour:minute:hasLeadingZero:)`` reads it: 1 to 6 o'clock is the
  /// afternoon, 7 to 11 the morning. With a part: เช้า takes 6 to 11, บ่าย 1 to
  /// 6, and เย็น 3 to 11, so "สี่โมงเย็น" is 16:00 and "หกโมงเช้า" 06:00; an hour
  /// the part never goes with ("สองโมงเช้า") is no time. ทุ่ม counts the evening
  /// from one (19:00) to five (23:00), ตี the small hours from one to five, and
  /// เที่ยงคืน is the midnight that ends the day, which puts the task on the
  /// next day. A time with น. or นาฬิกา is on the 24-hour clock: "3.30 น." is
  /// 03:30, the way a leading zero marks one in other languages. `isRangeSide`
  /// is true for a side of a range, whose bare hour the range reads against its
  /// other side.
  private static func thaiClockTime(_ clock: ThaiParsedClock, isRangeSide: Bool, match: Match) -> ClockTime? {
    let (hour, minute) = (clock.hour, clock.minute)
    guard (0...59).contains(minute) else { return nil }
    switch clock.unit {
    case .moong:
      guard (1...12).contains(hour) else { return nil }
      switch clock.part {
      case .morning: return thaiTime(hour: hour, minute: minute, linePart: "เช้า")
      case .afternoon: return partOfDayTime(hour: hour, minute: minute, part: .day)
      case .evening: return thaiTime(hour: hour, minute: minute, linePart: "เย็น")
      case nil:
        if let part = thaiLinePart(beside: match) { return thaiTime(hour: hour, minute: minute, linePart: part) }
        return bareTime(hour: hour, minute: minute, hasLeadingZero: false)
      }
    case .thum:
      return (1...5).contains(hour) ? ClockTime(minutes: (18 + hour) * 60 + minute) : nil
    case .tee:
      guard (1...5).contains(hour) else { return nil }
      return ClockTime(minutes: hour * 60 + minute, writtenHour: isRangeSide ? nil : hour)
    case .midnight:
      return ClockTime(minutes: 0, isAfterMidnight: true)
    case .noon:
      return ClockTime(minutes: 12 * 60 + minute)
    case .clock24:
      if hour == 24 { return minute == 0 ? ClockTime(minutes: 0, isAfterMidnight: true) : nil }
      guard (0...23).contains(hour) else { return nil }
      return ClockTime(minutes: hour * 60 + minute, writtenHour: isRangeSide || hour > 12 ? nil : hour)
    case .bare:
      if !clock.hasLeadingZero, (1...12).contains(hour), let part = thaiLinePart(beside: match) {
        return thaiTime(hour: hour, minute: minute, linePart: part)
      }
      return bareTime(hour: hour, minute: minute, hasLeadingZero: clock.hasLeadingZero)
    }
  }

  // MARK: - Clock time rule

  /// Every written clock time, with the words that introduce it: "บ่ายสามโมง",
  /// "สามโมงครึ่ง", "สี่โมงเย็น", "ตอนบ่ายสอง", "บ่ายสามครึ่ง", "สองทุ่ม", "ตีห้า",
  /// "เที่ยง", "เที่ยงคืน", "15:00 น.", "15.00 น.", "15 นาฬิกา", "เวลา 15:00". A
  /// time written with no Thai word or unit ("15:30", "3pm") is left to English.
  static var thaiTimePattern: String {
    #"\#(thaiStart)\#(thaiClockAlternatives)\#(thaiTimeEnd)"#
  }

  static func thaiTime(_ match: Match) -> ClockTime? {
    guard let clock = thaiParseClock(thaiMatched(match)) else { return nil }
    return thaiClockTime(clock, isRangeSide: false, match: match)
  }

  // MARK: - Time range

  /// The sides of a range: a time with its own unit, or on the first side a
  /// bare hour or time.
  private static var thaiRangeSide: String {
    thaiNonCapturing(thaiFormPatterns.filter { $0.form != .leadColon }.map(\.pattern).joined(separator: "|"))
  }

  /// The body of the range pattern, with its groups capturing: 1 the start, 2 a
  /// dash, 3 the word that means "to", 4 the end.
  private static var thaiTimeRangeBody: String {
    let side = thaiRangeSide
    let bare = #"(?<![\p{N}:.,/])\d{1,2}(?:\s*[.:]\s*\d{2})?"#
    return
      #"\#(thaiTimeLead)(?:(?:ตั้งแต่|จาก)\s*)?((?:\#(side)|\#(bare)))(?:\s*([-–—~])\s*|\s*(ถึง|จนถึง|จน)\s*)(\#(side))"#
  }

  /// "10:00-11:00 น.", "9-11 โมงเช้า", "บ่ายสองถึงสี่โมง", "ตั้งแต่ 9 โมงถึง 11
  /// โมง", "ตีหนึ่งถึงตีสอง", "10.00-12.00 น.", "สองโมงถึงสี่โมงเย็น". Groups: 1 the
  /// start, 2 a dash between the sides, 3 the word that means "to", 4 the end. The
  /// end carries a unit, and the start borrows it when it has none.
  static var thaiTimeRangePattern: String {
    #"\#(thaiStart)\#(thaiTimeRangeBody)\#(thaiTimeEnd)"#
  }

  static func thaiTimeRange(_ match: Match) -> ClockTime? {
    guard let startText = match.group(1), let endText = match.group(4), let endClock = thaiParseClock(endText),
      let startClock = thaiParseClock(startText) ?? thaiBareSide(startText, borrowing: endClock),
      let start = thaiClockTime(startClock, isRangeSide: true, match: match),
      let end = thaiClockTime(endClock, isRangeSide: true, match: match)
    else { return nil }
    return timeRange(from: start, to: end)
  }

  // MARK: - Deadline written as a clock time

  /// A clock time as a bound allows it: any written clock time, or a bare time
  /// with a colon or a dot ("17:00", "17.00").
  private static var thaiBoundClock: String {
    #"(?:\#(thaiClockAlternatives)|\d{1,2}\s*[.:：]\s*\d{2}(?![\p{N}]))"#
  }

  /// A clock time written as a bound ("ก่อน 5 โมงเย็น", "ภายใน 17:00", "ไม่เกินบ่ายสาม",
  /// "หลังเที่ยง", "หลังจาก 15.00 น.", "ตั้งแต่ 9 โมงเป็นต้นไป"), which names no
  /// start time. Group 1 is the bound, or nil for a range ("ตั้งแต่ 9 โมงถึง 11
  /// โมง"), which the range rule reads and this rule only steps over, so the
  /// "ถึง 11 โมง" inside it is not taken for a bound.
  static var thaiDeadlineClockPattern: String {
    let after =
      #"(?:ก่อน|หลังจาก|หลัง|ภายใน|ไม่เกิน|เกิน|ตั้งแต่)\s*(?:(?:เวลา|ตอน)\s*)?\#(thaiBoundClock)"#
    return
      #"\#(thaiStart)(?:\#(thaiNonCapturing(thaiTimeRangeBody))|(\#(after)))\#(thaiTimeEnd)"#
  }

  /// The bounds that make the day before them a due day: "พรุ่งนี้ก่อน 5 โมงเย็น"
  /// is due tomorrow. A "หลัง" bound makes no due day, as a lookahead pattern.
  static var thaiBeforeDeadlineClock: String {
    #"(?=\s*,?\s*(?:ก่อน|ภายใน|ไม่เกิน)\s*(?:(?:เวลา|ตอน)\s*)?\#(thaiBoundClock))"#
  }

  /// The clock after a deadline day ("ภายในวันศุกร์ 5 โมงเย็น", "ก่อนพรุ่งนี้ 17:00"),
  /// which is a deadline's clock and stays in the title with the rest of the
  /// line once the day is read as the due day.
  static var thaiDueClockPattern: String {
    #"\#(thaiStart)(?:\#(thaiClockAlternatives)|\d{1,2}\s*[.:：]\s*\d{2}(?![\p{N}]))\#(thaiTimeEnd)"#
  }

  /// The text before a deadline clock that makes it the clock of a due day: a
  /// word that introduces a due day and the day, with a comma or a space before
  /// the clock.
  private static let thaiAfterDueDayPattern =
    #"\#(thaiDueLead)(?:\#(thaiDaysAfterLead))\s*,?\s*$"#

  /// Whether the text before `match` ends with a word that introduces a due day
  /// and the day ("ภายในวันศุกร์", "ก่อนพรุ่งนี้").
  static func thaiIsClockAfterDueDay(_ match: Match) -> Bool {
    thaiMatches(thaiAfterDueDayPattern, thaiTextBefore(match))
  }
}

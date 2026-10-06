import Foundation

extension LorvexCaptureVocabulary {
  // The Turkish repeat rules: working days, weekends, a day of the month,
  // repeated weekdays, counted intervals, cadence phrases, and the adjectives
  // at the end of a line. The vocabulary's other words are in ``turkish``.

  /// The repeat rules in the order they are tried: the working days, the
  /// weekend, and a day of the month before the rules for every day and every
  /// month, which would leave "hafta içi her gün" or the day's number in the
  /// title; the counted intervals before the weekday rules, so "iki haftada
  /// bir cuma" takes its interval with its weekday; the weekday rules before
  /// "her hafta", so "her hafta cuma" is read whole.
  static let turkishRepeatRules: [Rule<Repeat>] = [
    Rule(pattern: turkishWorkdaysPattern) { _ in workdays },
    Rule(pattern: turkishWeekendRepeatPattern) { _ in weekly(every: nil, on: [6, 0]) },
    Rule(pattern: turkishMonthDayRepeatPattern, read: turkishMonthDayRepeat),
    Rule(pattern: turkishIntervalRepeatPattern, read: turkishIntervalRepeat),
    Rule(pattern: turkishWeekdayRepeatPattern, read: turkishWeekdayRepeat),
    Rule(pattern: turkishEveryUnitPattern, read: turkishEveryUnit),
    Rule(pattern: turkishAdverbPattern, read: turkishAdverb),
  ]

  // MARK: - Working days and weekends

  /// "hafta içi her gün", "her gün hafta içi", "her hafta içi", "hafta içi
  /// günleri", "hafta içleri", "iş günleri", "her iş günü", "pazartesi-cuma",
  /// "pazartesiden cumaya". "Hafta içi" alone is no repeat: it is "within the
  /// week" as often as "on weekdays".
  private static let turkishWorkdaysPattern =
    #"\#(turkishStart)(?:hafta\s+ici\s+her\s+gun|her\s+gun\s+hafta\s+ici|her\s+hafta\s+ici|hafta\s+ici\s+gunleri(?:nde)?|hafta\s+icleri(?:nde)?|is\s+gunleri(?:nde)?|her\s+is\s+gunu|(?:pazartesi|pzt)(?:\s*[-–—]\s*cuma|['’ʼ]?den\s+cuma(?:['’ʼ]?ya)?(?:\s+kadar)?))\#(turkishEnd)"#

  /// "hafta sonları", "hafta sonlarında", "her hafta sonu". "Hafta sonu" alone
  /// and "bu hafta sonu" name the coming weekend, a day.
  private static let turkishWeekendRepeatPattern =
    #"\#(turkishStart)(?:hafta\s*sonlari(?:nda)?|her\s+hafta\s*sonu)\#(turkishEnd)"#

  // MARK: - Day of the month

  /// "her ayın 15'inde", "her ayın 15'i", "her ay 15'inde": a day of every month.
  /// Group 1: the day of the month. The number is a day only where no unit or
  /// counted noun follows it ("her ay 15 TL").
  private static var turkishMonthDayRepeatPattern: String {
    #"\#(turkishStart)her\s+ay(?:in)?\s+(\d{1,2})(?:['’ʼ]?(?:s?[iu]nd[ae]|s?[iu]|nd[ae]))?\#(turkishNoCountedUnitAfter)\#(turkishEnd)"#
  }

  private static func turkishMonthDayRepeat(_ match: Match) -> Repeat? {
    match.group(1).flatMap(number).flatMap { monthly(every: nil, on: $0) }
  }

  // MARK: - Repeated weekdays

  /// The separator of a list of weekdays: a comma, "ve", "ile", or "&".
  private static let turkishListSeparator = #"(?:\s*,\s*|\s+ve\s+|\s+ile\s+|\s*&\s*)"#

  /// The weekday names of a list, as a pattern without groups: "pazartesi",
  /// "salı ve perşembe", "pazartesi, çarşamba ve cuma", each name maybe after
  /// its own "her".
  private static var turkishNamesList: String {
    let day = #"(?:\#(turkishWeekdayNames))"#
    return #"\#(day)(?:\#(turkishListSeparator)(?:her\s+)?\#(day)){0,6}"#
  }

  /// The plural forms of the weekday names, as a pattern without groups:
  /// "pazartesileri", "cumaları", "salılar", "perşembelerde", maybe in a list.
  private static var turkishPluralList: String {
    let stems = alternation(of: ["pazartesi", "pazar", "sali", "carsamba", "persembe", "cumartesi", "cuma"])
    let day = #"(?:\#(stems))(?:ler|lar)(?:i|de|da)?"#
    return #"\#(day)(?:\#(turkishListSeparator)\#(day)){0,6}"#
  }

  /// The weekdays a matched list names, 0 = Sunday.
  private static func turkishRepeatWeekdays(_ list: String) -> [Int] {
    letterWords(list).compactMap { turkishWeekdayIndex($0) }
  }

  /// "her pazartesi", "her hafta cuma", "her salı ve perşembe", "pazartesi
  /// günleri", "salı ve perşembe günleri", "pazartesileri", "cumaları", each
  /// maybe followed by the plural of a part of the day ("cumaları akşamları"),
  /// and "pazartesi akşamları". Groups: 1 the weekdays after "her", 2 the
  /// weekdays before "günleri", 3 the plural weekdays, 4 the weekdays before the
  /// plural of a part of the day.
  private static var turkishWeekdayRepeatPattern: String {
    let partPlural = #"(?:sabah|aksam|gece|oglen)(?:lari|leri)"#
    return
      #"\#(turkishStart)(?:her\s+(?:hafta\s+)?(\#(turkishNamesList))|(\#(turkishNamesList))\s+gunleri(?:nde)?|(\#(turkishPluralList))|(\#(turkishNamesList))\s+\#(partPlural))(?:\s+\#(partPlural))?\#(turkishEnd)"#
  }

  private static func turkishWeekdayRepeat(_ match: Match) -> Repeat? {
    let list = match.group(1) ?? match.group(2) ?? match.group(3) ?? match.group(4) ?? ""
    let days = turkishRepeatWeekdays(list)
    return days.isEmpty ? nil : weekly(every: nil, on: days)
  }

  // MARK: - Counted intervals

  /// The repeat every `every` (nil for each) of the unit a word names, by its
  /// first letters: days, weeks, months, or years. A whole number of weeks
  /// counted in days is a weekly repeat ("14 günde bir"), and a unit that is
  /// none returns nil.
  private static func turkishRepeat(unit: String, every: Int?) -> Repeat? {
    let key = turkishKey(unit)
    if key.hasPrefix("hafta") { return weekly(every: every, on: []) }
    if key.hasPrefix("ay") { return monthly(every: every, on: nil) }
    if key.hasPrefix("yil") || key.hasPrefix("sene") {
      return Repeat(rule: TaskRecurrenceRule(freq: .yearly, interval: every))
    }
    guard key.hasPrefix("gun") else { return nil }
    if let count = every, count % 7 == 0 { return weekly(every: count / 7 == 1 ? nil : count / 7, on: []) }
    return Repeat(rule: TaskRecurrenceRule(freq: .daily, interval: every))
  }

  /// "iki günde bir", "3 haftada bir", "her 2 günde bir", "her 3 hafta", "her
  /// ikinci gün", "gün aşırı", "haftada bir", "ayda bir", "yılda bir", each
  /// maybe before a weekday ("iki haftada bir cuma"). "Her iki gün" stays: it
  /// is "both days" as often as "every two days". Groups: 1 and 2 the count and
  /// the unit with its locative ending of "iki günde bir"; 3 and 4 the count and
  /// the unit after "her"; 5 the unit after "her ikinci"; 6 the unit before
  /// "aşırı"; 7 the unit with its locative ending of "haftada bir"; 8 the
  /// weekday names after the interval.
  private static var turkishIntervalRepeatPattern: String {
    let count = #"(\d{1,3}|\#(turkishCountWords))"#
    let unitLocative = #"(gunde|haftada|ayda|yilda|senede)"#
    let unit = #"(gun|hafta|ay|yil|sene)"#
    let weekdays = #"(?:\s+(?:her\s+)?(\#(turkishNamesList)))?"#
    return
      #"\#(turkishStart)(?:(?:her\s+)?\#(count)\s+\#(unitLocative)\s+bir|her\s+\#(count)\s+\#(unit)|her\s+ikinci\s+\#(unit)|\#(unit)\s*asiri|\#(unitLocative)\s+bir)\#(weekdays)\#(turkishEnd)"#
  }

  private static func turkishIntervalRepeat(_ match: Match) -> Repeat? {
    let weekdays = turkishRepeatWeekdays(match.group(8) ?? "")
    var base: Repeat?
    if let countText = match.group(1), let unit = match.group(2) {
      guard let count = turkishCount(countText), (1...99).contains(count) else { return nil }
      base = turkishRepeat(unit: unit, every: count == 1 ? nil : count)
    } else if let countText = match.group(3), let unit = match.group(4) {
      // "Her iki gün" is "both days" as often as "every two days", but "her 2
      // gün" and "her üç gün" count.
      guard let count = turkishCount(countText), (2...99).contains(count), number(countText) != nil || count > 2
      else { return nil }
      base = turkishRepeat(unit: unit, every: count)
    } else if let unit = match.group(5) ?? match.group(6) {
      base = turkishRepeat(unit: unit, every: 2)
    } else if let unit = match.group(7) {
      base = turkishRepeat(unit: unit, every: nil)
    }
    guard let base else { return nil }
    // A weekday after a weekly interval fixes the repeat's days.
    guard !weekdays.isEmpty else { return base }
    return base.rule.freq == .weekly ? weekly(every: base.rule.interval, on: weekdays) : nil
  }

  // MARK: - Cadence phrases

  /// "her gün", "hergün", "her hafta", "her ay", "her yıl", "her sene", "her
  /// sabah", "her akşam", "her gece". Group 1: the unit or the part of the day
  /// after "her". "Her ayın sonu" is no such phrase: the word after the unit
  /// goes on. "Her gün için" and "her gün gibi" are not either: they say "for
  /// every day" and "like every day".
  private static let turkishEveryUnitPattern =
    #"\#(turkishStart)her\s*(gun|hafta|ay|yil|sene|sabah|aksam|gece|oglen|ikindi)\#(turkishEnd)(?!\s+(?:icin|gibi)(?![\p{Latin}\p{M}]))"#

  private static func turkishEveryUnit(_ match: Match) -> Repeat? {
    guard let word = match.group(1).map(turkishKey) else { return nil }
    switch word {
    case "hafta": return weekly(every: nil, on: [])
    case "ay": return monthly(every: nil, on: nil)
    case "yil", "sene": return Repeat(rule: TaskRecurrenceRule(freq: .yearly))
    default: return Repeat(rule: TaskRecurrenceRule(freq: .daily))
    }
  }

  // MARK: - Adjectives

  /// "günlük", "haftalık", "aylık", "yıllık" at the end of the line, or opening
  /// the line before a colon or a comma, or followed by "olarak" anywhere. The
  /// word is an adjective too ("haftalık rapor", "yıllık izin"), and the end of
  /// the line is where it says how a task repeats. Groups: 1 the word at the
  /// end, 2 the word that opens the line, 3 the word before "olarak".
  private static let turkishAdverbPattern =
    #"\#(turkishStart)(gunluk|haftalik|aylik|yillik)\#(turkishEnd)(?=[\s.!]*$)|^\s*(gunluk|haftalik|aylik|yillik)\#(turkishEnd)(?=\s*[:,，：])|\#(turkishStart)(gunluk|haftalik|aylik|yillik)\s+olarak\#(turkishEnd)"#

  private static func turkishAdverb(_ match: Match) -> Repeat? {
    guard let word = (match.group(1) ?? match.group(2) ?? match.group(3)).map(turkishKey) else { return nil }
    switch word {
    case "gunluk": return Repeat(rule: TaskRecurrenceRule(freq: .daily))
    case "haftalik": return weekly(every: nil, on: [])
    case "aylik": return monthly(every: nil, on: nil)
    default: return Repeat(rule: TaskRecurrenceRule(freq: .yearly))
    }
  }
}

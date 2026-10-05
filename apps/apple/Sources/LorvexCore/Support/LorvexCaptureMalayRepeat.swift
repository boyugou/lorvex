import Foundation

extension LorvexCaptureVocabulary {
  // The Malay repeat rules: working days, weekends, a day of the month, counted
  // intervals, "once per" phrases, repeated weekdays, cadence phrases, and the
  // adjectives at the end of a line. The vocabulary's other words are in
  // ``malay``.

  /// The repeat rules in the order they are tried: the working days, the weekend,
  /// and a day of the month before the rules for every day and every month, which
  /// would leave "hari kerja" or the day's number in the title; the counted
  /// intervals before the weekday rules, so "setiap 2 minggu hari Khamis" takes
  /// its interval with its weekday; the span of weekdays before the list of them,
  /// so "setiap Isnin hingga Khamis" is read whole.
  static let malayRepeatRules: [Rule<Repeat>] = [
    Rule(pattern: malayWorkdaysPattern) { _ in workdays },
    Rule(pattern: malayWeekendRepeatPattern) { _ in weekly(every: nil, on: [6, 0]) },
    Rule(pattern: malayMonthDayRepeatPattern, read: malayMonthDayRepeat),
    Rule(pattern: malayIntervalRepeatPattern, read: malayIntervalRepeat),
    Rule(pattern: malayWeekdaySpanRepeatPattern, read: malayWeekdaySpanRepeat),
    Rule(pattern: malayWeekdayRepeatPattern, read: malayWeekdayRepeat),
    Rule(pattern: malayEveryUnitPattern, read: malayEveryUnit),
    Rule(pattern: malayAdjectivePattern, read: malayAdjective),
  ]

  /// "setiap", "tiap", and "tiap-tiap", the words that open a repeat, as a pattern
  /// without groups.
  private static let malayEvery = #"(?:setiap|tiap(?:[-\s]tiap)?)"#

  // MARK: - Working days and weekends

  /// "setiap hari bekerja", "setiap hari kerja", "tiap-tiap hari kerja", "pada hari
  /// bekerja", "pada hari-hari kerja". "Hari kerja" with no "setiap" or "pada" is a
  /// count of working days ("dalam 3 hari kerja"), and "pada hari kerja
  /// berikutnya" names one day.
  private static let malayWorkdaysPattern =
    #"\#(malayStart)(?:\#(malayEvery)\s+hari\s+(?:bekerja|kerja)|pada\s+hari(?:-hari)?\s+(?:bekerja|kerja)(?!\s+(?:berikutnya|depan|hadapan|terakhir|pertama|ini|itu|lepas|lalu|nanti)))\#(malayEnd)"#

  /// "setiap hujung minggu", "tiap-tiap weekend". "Hujung minggu" with no "setiap"
  /// names the coming weekend, a day.
  private static let malayWeekendRepeatPattern =
    #"\#(malayStart)\#(malayEvery)\s+(?:hujung\s+minggu|weekend)\#(malayEnd)"#

  // MARK: - Day of the month

  /// "setiap 5hb", "setiap tarikh 5", "tiap bulan pada 5hb", "setiap bulan pada
  /// tarikh 5", "tarikh 5 setiap bulan", "pada 5hb setiap bulan". The day may not
  /// go on as a list or a range of days ("5hb dan 20hb", "tarikh 5 hingga 7") or
  /// with a month ("5hb Oktober" is a date). Groups 1 and 2: the day of the month
  /// in each form.
  private static var malayMonthDayRepeatPattern: String {
    let notAList = #"(?!\s*(?:[-–—/,&]|hingga|sehingga|sampai|dan|atau)\s*\d)"#
    let notAMonth = #"(?!\s*(?:\#(malayMonthNames))(?![\p{Latin}\p{N}\p{M}]))"#
    let day = #"(?:tarikh\s*(\d{1,2})|(\d{1,2})(?-i:hb)\.?)(?![\p{Latin}\p{N}\p{M}%]|[.,:]\p{N})"#
    let dayAfter = #"(?:tarikh\s*(\d{1,2})|(\d{1,2})(?-i:hb)\.?)(?![\p{Latin}\p{N}\p{M}%]|[.,:]\p{N})"#
    return
      #"\#(malayStart)(?:\#(malayEvery)\s+(?:bulan\s+(?:pada\s+)?)?\#(day)\#(notAList)\#(notAMonth)|(?:pada\s+)?\#(dayAfter)\s+\#(malayEvery)\s+bulan)\#(malayEnd)"#
  }

  private static func malayMonthDayRepeat(_ match: Match) -> Repeat? {
    guard let text = [1, 2, 3, 4].lazy.compactMap({ match.group($0) }).first else { return nil }
    return number(text).flatMap { monthly(every: nil, on: $0) }
  }

  // MARK: - Repeated weekdays

  /// The separator of a list of weekdays: a comma, "dan", "serta", "atau", or "&".
  private static let malayRepeatSeparator = #"(?:\s*,\s*(?:dan\s+)?|\s+dan\s+|\s*&\s*|\s+serta\s+|\s+atau\s+)"#

  /// The weekday names a repeat lists, as a pattern without groups: "Isnin", "hari
  /// Isnin", "Isnin dan Khamis", "Isnin, Rabu, dan Jumaat".
  private static var malayRepeatList: String {
    let day = malayWeekdayWord
    return #"\#(day)(?:\#(malayRepeatSeparator)\#(day)){0,6}"#
  }

  /// The weekdays a matched list names, 0 = Sunday.
  private static func malayRepeatWeekdays(_ list: String) -> [Int] {
    letterWords(malayKey(list)).compactMap(malayWeekdayIndex)
  }

  /// "setiap Isnin", "tiap hari Isnin", "setiap Selasa dan Khamis", "setiap Isnin,
  /// Rabu, dan Jumaat", "setiap minggu pada hari Isnin", each maybe with a part of
  /// the day after the weekdays ("setiap Jumaat petang"), which is part of the
  /// phrase as it is in a day phrase. Groups: 1 the weekdays, 2 the part of the
  /// day.
  private static var malayWeekdayRepeatPattern: String {
    #"\#(malayStart)\#(malayEvery)\s+(?:minggu\s+(?:pada\s+)?)?(\#(malayRepeatList))(?:\s+(\#(malayDayParts)))?\#(malayEnd)"#
  }

  private static func malayWeekdayRepeat(_ match: Match) -> Repeat? {
    guard let list = match.group(1) else { return nil }
    let days = malayRepeatWeekdays(list)
    return days.isEmpty ? nil : weekly(every: nil, on: days)
  }

  /// "setiap Isnin hingga Khamis", "tiap Selasa - Jumaat", "setiap Jumaat sampai
  /// Ahad": a span of weekdays after "setiap" or "tiap". Groups: 1 the first
  /// weekday, 2 the last.
  private static var malayWeekdaySpanRepeatPattern: String {
    let day = malayWeekdayWord
    return
      #"\#(malayStart)\#(malayEvery)\s+(\#(day))\s*(?:[-–—]|hingga|sehingga|sampai)\s*(\#(day))\#(malayEnd)"#
  }

  private static func malayWeekdaySpanRepeat(_ match: Match) -> Repeat? {
    guard let firstText = match.group(1), let lastText = match.group(2), let first = malayWeekdayIndex(firstText),
      let last = malayWeekdayIndex(lastText), first != last
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

  /// The repeat every `every` (nil for each) of the unit a word names: days,
  /// weeks, months, or years, in their plain forms ("hari", "minggu", "bulan",
  /// "tahun") or with "se-" ("sehari", "seminggu", "sebulan", "setahun"). A whole
  /// number of weeks counted in days is a weekly repeat ("14 hari"), and a word
  /// that is no unit returns nil.
  private static func malayRepeat(unit: String, every: Int?) -> Repeat? {
    var key = malayKey(unit)
    if ["sehari", "seminggu", "sebulan", "setahun"].contains(key) { key.removeFirst(2) }
    switch key {
    case "hari":
      if let count = every, count % 7 == 0 { return weekly(every: count / 7 == 1 ? nil : count / 7, on: []) }
      return Repeat(rule: TaskRecurrenceRule(freq: .daily, interval: every))
    case "minggu": return weekly(every: every, on: [])
    case "bulan": return monthly(every: every, on: nil)
    case "tahun": return Repeat(rule: TaskRecurrenceRule(freq: .yearly, interval: every))
    default: return nil
    }
  }

  /// "setiap 2 hari", "setiap tiga minggu", "tiap-tiap 2 bulan", "2 hari sekali",
  /// "dua minggu sekali", "seminggu sekali", "sebulan sekali", "setahun sekali",
  /// "sekali seminggu", "sekali dalam 2 minggu", "1x seminggu", "1 kali per bulan",
  /// "satu kali sebulan", each maybe before weekdays after a weekly interval
  /// ("setiap 2 minggu hari Khamis"). A count of times in a period ("dua kali
  /// seminggu") is no repeat and an interval of hours ("setiap 2 jam") is a length,
  /// so both stay in the title; "hari kerja" after a count is a count of working
  /// days. Groups: 1 and 2 the count and the unit after "setiap"; 3 and 4 the count
  /// and the unit before "sekali"; 5 the "se-" unit before "sekali"; 6 and 7 the
  /// count and the unit after "sekali"; 8 the "se-" unit after it; 9 the unit and
  /// 10 the "se-" unit after "1x"; 11 the weekdays.
  private static var malayIntervalRepeatPattern: String {
    let count = #"(\d{1,3}|\#(malayNumberWords))"#
    let units = #"(hari|minggu|bulan|tahun)"#
    let seUnits = #"(sehari|seminggu|sebulan|setahun)"#
    let per = #"(?:(?:dalam|per|tiap|setiap)\s+)?"#
    let weekdays = #"(?:\s+(?:pada\s+)?(\#(malayRepeatList)))?"#
    return
      #"\#(malayStart)(?:\#(malayEvery)\s+\#(count)\s+\#(units)(?!\s+(?:bekerja|kerja))|\#(count)\s+\#(units)\s+sekali|\#(seUnits)\s+sekali|sekali\s+\#(per)(?:\#(count)\s+\#(units)|\#(seUnits))|(?:1\s*x|(?:1|satu)\s+kali)\s+\#(per)(?:\#(units)|\#(seUnits)))\#(weekdays)\#(malayEnd)"#
  }

  private static func malayIntervalRepeat(_ match: Match) -> Repeat? {
    let base: Repeat?
    if let countText = match.group(1), let unit = match.group(2) {
      base = malayCounted(countText, unit)
    } else if let countText = match.group(3), let unit = match.group(4) {
      base = malayCounted(countText, unit)
    } else if let unit = match.group(5) {
      base = malayRepeat(unit: unit, every: nil)
    } else if let countText = match.group(6), let unit = match.group(7) {
      base = malayCounted(countText, unit)
    } else if let unit = match.group(8) ?? match.group(9) ?? match.group(10) {
      base = malayRepeat(unit: unit, every: nil)
    } else {
      return nil
    }
    guard let base else { return nil }
    guard let list = match.group(11) else { return base }
    // A weekday after a weekly interval fixes the repeat's days.
    let days = malayRepeatWeekdays(list)
    return base.rule.freq == .weekly && !days.isEmpty ? weekly(every: base.rule.interval, on: days) : nil
  }

  /// The repeat every `count` of `unit`, for a count from 1 to 99.
  private static func malayCounted(_ countText: String, _ unit: String) -> Repeat? {
    guard let count = malayCount(countText), (1...99).contains(count) else { return nil }
    return malayRepeat(unit: unit, every: count == 1 ? nil : count)
  }

  // MARK: - Cadence phrases

  /// "setiap hari", "tiap-tiap hari", "setiap pagi", "setiap petang", "setiap
  /// malam", "setiap minggu", "setiap bulan", "setiap tahun", "setiap suku tahun".
  /// "Hari" before a holiday, a name, or an exception ("setiap hari cuti",
  /// "setiap hari raya", "setiap hari kecuali Ahad"), "minggu" before an ordinal
  /// ("setiap minggu pertama"), and "bulan" before a month ("setiap bulan
  /// Oktober", "setiap bulan Ramadan") name no cadence the app can set and stay in
  /// the title. Group 1: the unit or the part of the day after "setiap".
  private static var malayEveryUnitPattern: String {
    let names = malayWeekdayNames
    let months = malayMonthNames
    let notADay =
      #"(?!\s+(?:cuti|raya|besar|kebangsaan|lahir|jadi|gaji|pertama|terakhir|bekerja|kerja|biasa|ini|itu|keluarga|sukan|guru|ibu|bapa|ulang|kecuali|selain|tanpa|\#(names))(?![\p{Latin}\p{M}]))"#
    let notAWeek = #"(?!\s+(?:ke|pertama|kedua|ketiga|keempat|terakhir|depan|hadapan|ini|lepas|lalu)(?![\p{Latin}\p{M}]))"#
    let notAMonth =
      #"(?!\s+(?:ke|pertama|terakhir|depan|hadapan|ini|lepas|lalu|ramadan|ramadhan|syawal|muharram|rejab|syaaban|zulhijjah|puasa|\#(months))(?![\p{Latin}\p{N}\p{M}]))"#
    return
      #"\#(malayStart)\#(malayEvery)\s+(hari\#(notADay)|pagi|petang|malam|minggu\#(notAWeek)|bulan\#(notAMonth)|tahun|suku\s+tahun)\#(malayEnd)"#
  }

  private static func malayEveryUnit(_ match: Match) -> Repeat? {
    guard let word = match.group(1).map(malayPhrase) else { return nil }
    switch word {
    case "minggu": return weekly(every: nil, on: [])
    case "bulan": return monthly(every: nil, on: nil)
    case "tahun": return Repeat(rule: TaskRecurrenceRule(freq: .yearly))
    case "suku tahun": return monthly(every: 3, on: nil)
    default: return Repeat(rule: TaskRecurrenceRule(freq: .daily))
    }
  }

  // MARK: - Adjectives

  /// "harian", "mingguan", "bulanan", "tahunan" at the end of the line, or
  /// "harian", "mingguan", "bulanan", "tahunan" opening the line before a colon or a
  /// comma. The word is an adjective after its noun ("Laporan mingguan") and the end
  /// of the line is where it says how a task repeats; "buku harian" (a diary),
  /// "Berita Harian" (a newspaper), and "cuti tahunan" (annual leave) name no
  /// repeat. Groups: 1 the word at the end, 2 the word that opens the line.
  private static let malayAdjectivePattern =
    #"\#(malayStart)(?<!(?:buku|akhbar|majalah|tabloid|berita|cuti)\s{1,3})(harian|mingguan|bulanan|tahunan)\#(malayEnd)(?=[\s.!]*$)|^\s*(harian|mingguan|bulanan|tahunan)\#(malayEnd)(?=\s*[:,，：])"#

  private static func malayAdjective(_ match: Match) -> Repeat? {
    guard let word = (match.group(1) ?? match.group(2)).map(malayKey) else { return nil }
    switch word {
    case "harian": return Repeat(rule: TaskRecurrenceRule(freq: .daily))
    case "mingguan": return weekly(every: nil, on: [])
    case "bulanan": return monthly(every: nil, on: nil)
    case "tahunan": return Repeat(rule: TaskRecurrenceRule(freq: .yearly))
    default: return nil
    }
  }
}

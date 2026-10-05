import Foundation

extension LorvexCaptureVocabulary {
  // The Indonesian repeat rules: working days, weekends, a day of the month,
  // counted intervals, "once per" phrases, repeated weekdays, cadence phrases,
  // and the adjectives at the end of a line. The vocabulary's other words are in
  // ``indonesian``.

  /// The repeat rules in the order they are tried: the working days, the
  /// weekend, and a day of the month before the rules for every day and every
  /// month, which would leave "hari kerja" or the day's number in the title; the
  /// counted intervals before the weekday rules, so "setiap 2 minggu hari Kamis"
  /// takes its interval with its weekday; the span of weekdays before the list of
  /// them, so "setiap Senin sampai Kamis" is read whole.
  static let indonesianRepeatRules: [Rule<Repeat>] = [
    Rule(pattern: indonesianWorkdaysPattern) { _ in workdays },
    Rule(pattern: indonesianWeekendRepeatPattern) { _ in weekly(every: nil, on: [6, 0]) },
    Rule(pattern: indonesianMonthDayRepeatPattern, read: indonesianMonthDayRepeat),
    Rule(pattern: indonesianIntervalRepeatPattern, read: indonesianIntervalRepeat),
    Rule(pattern: indonesianWeekdaySpanRepeatPattern, read: indonesianWeekdaySpanRepeat),
    Rule(pattern: indonesianWeekdayRepeatPattern, read: indonesianWeekdayRepeat),
    Rule(pattern: indonesianEveryUnitPattern, read: indonesianEveryUnit),
    Rule(pattern: indonesianAdjectivePattern, read: indonesianAdjective),
  ]

  /// "setiap" and "tiap", the words that open a repeat, as a pattern without
  /// groups.
  private static let indonesianEvery = #"(?:setiap|tiap(?:-tiap)?)"#

  // MARK: - Working days and weekends

  /// "setiap hari kerja", "tiap hari kerja", "pada hari kerja", "pada hari-hari
  /// kerja". "Hari kerja" with no "setiap" or "pada" is a count of working days
  /// ("dalam 3 hari kerja"), and "pada hari kerja berikutnya" names one day.
  private static let indonesianWorkdaysPattern =
    #"\#(indonesianStart)(?:\#(indonesianEvery)\s+hari\s+kerja|pada\s+hari(?:-hari)?\s+kerja(?!\s+(?:berikutnya|depan|selanjutnya|terakhir|pertama|ini|itu|lalu|kemarin|nanti)))\#(indonesianEnd)"#

  /// "setiap akhir pekan", "tiap weekend". "Akhir pekan" with no "setiap" names
  /// the coming weekend, a day.
  private static let indonesianWeekendRepeatPattern =
    #"\#(indonesianStart)\#(indonesianEvery)\s+(?:akhir\s+pekan|weekend)\#(indonesianEnd)"#

  // MARK: - Day of the month

  /// "setiap tanggal 5", "tiap tgl. 5", "setiap bulan tanggal 5", "setiap bulan
  /// pada tanggal 5", "tanggal 5 setiap bulan". The day may not go on as a list
  /// or a range of days ("tanggal 5 dan 20", "tanggal 5 sampai 7") or with a
  /// month ("tanggal 5 Oktober" is a date). Groups 1 and 2: the day of the month
  /// in each form.
  private static var indonesianMonthDayRepeatPattern: String {
    let notAList = #"(?!\s*(?:[-–—/,&]|sampai|hingga|s/d|dan|atau)\s*\d)"#
    let notAMonth = #"(?!\s*(?:\#(indonesianMonthNames))(?![\p{Latin}\p{N}\p{M}]))"#
    let day = #"(?:tanggal|tgl\.?)\s*(\d{1,2})\#(indonesianNoMoreDigits)"#
    return
      #"\#(indonesianStart)(?:\#(indonesianEvery)\s+(?:bulan\s+(?:pada\s+)?)?\#(day)\#(notAList)\#(notAMonth)|(?:tanggal|tgl\.?)\s*(\d{1,2})\#(indonesianNoMoreDigits)\s+\#(indonesianEvery)\s+bulan)\#(indonesianEnd)"#
  }

  private static func indonesianMonthDayRepeat(_ match: Match) -> Repeat? {
    guard let text = match.group(1) ?? match.group(2) else { return nil }
    return number(text).flatMap { monthly(every: nil, on: $0) }
  }

  // MARK: - Repeated weekdays

  /// The separator of a list of weekdays: a comma, "dan", "serta", "atau", or
  /// "&".
  private static let indonesianRepeatSeparator = #"(?:\s*,\s*(?:dan\s+)?|\s+dan\s+|\s*&\s*|\s+serta\s+|\s+atau\s+)"#

  /// The weekday names a repeat lists, as a pattern without groups: "Senin",
  /// "hari Senin", "Senin dan Kamis", "Senin, Rabu, dan Jumat". "Minggu" beside
  /// another weekday is Sunday; alone it is read by ``indonesianRepeatWeekdays(_:isSundayAlone:)``.
  private static var indonesianRepeatList: String {
    let day = indonesianWeekdayWordOrSunday
    return #"\#(day)(?:\#(indonesianRepeatSeparator)\#(day)){0,6}"#
  }

  /// The weekdays a matched list names, 0 = Sunday, or an empty list when it is
  /// the one word "minggu" with no "hari" before it and no part of the day after
  /// it, which is the week ("setiap minggu"), not Sunday.
  private static func indonesianRepeatWeekdays(_ list: String, isSundayAlone: Bool) -> [Int] {
    var days: [(weekday: Int, hasHari: Bool)] = []
    var hasHari = false
    for word in letterWords(indonesianKey(list)) {
      if word == "hari" {
        hasHari = true
        continue
      }
      if let weekday = indonesianWeekdayIndex(word) { days.append((weekday, hasHari)) }
      hasHari = false
    }
    if days.count == 1, days[0].weekday == 0, !days[0].hasHari, !isSundayAlone { return [] }
    return days.map(\.weekday)
  }

  /// "setiap Senin", "tiap hari Senin", "setiap Selasa dan Kamis", "setiap Senin,
  /// Rabu, dan Jumat", "setiap minggu pada hari Senin", "setiap Minggu pagi",
  /// each maybe with a part of the day after the weekdays ("setiap Jumat malam"),
  /// which is part of the phrase as it is in a day phrase. "Setiap minggu" is
  /// every week, "setiap hari Minggu" and "setiap Minggu pagi" every Sunday.
  /// Groups: 1 the weekdays, 2 the part of the day.
  private static var indonesianWeekdayRepeatPattern: String {
    #"\#(indonesianStart)\#(indonesianEvery)\s+(?:minggu\s+(?:pada\s+)?)?(\#(indonesianRepeatList))(?:\s+(\#(indonesianDayParts)))?\#(indonesianEnd)"#
  }

  private static func indonesianWeekdayRepeat(_ match: Match) -> Repeat? {
    guard let list = match.group(1) else { return nil }
    let days = indonesianRepeatWeekdays(list, isSundayAlone: match.group(2) != nil)
    return days.isEmpty ? nil : weekly(every: nil, on: days)
  }

  /// "setiap Senin sampai Kamis", "tiap Selasa - Jumat", "setiap Jumat sampai
  /// Minggu": a span of weekdays after "setiap" or "tiap". The first weekday
  /// needs its own name ("Minggu" alone is the week); the last may be "Minggu".
  /// Groups: 1 the first weekday, 2 the last.
  private static var indonesianWeekdaySpanRepeatPattern: String {
    let first = #"(?:hari\s+)?(?:\#(indonesianWeekdayNames)|hari\s+minggu)"#
    return
      #"\#(indonesianStart)\#(indonesianEvery)\s+(\#(first))\s*(?:[-–—]|sampai(?:\s+dengan)?|hingga|s/d|s\.d\.)\s*(\#(indonesianWeekdayWordOrSunday))\#(indonesianEnd)"#
  }

  private static func indonesianWeekdaySpanRepeat(_ match: Match) -> Repeat? {
    guard let firstText = match.group(1), let lastText = match.group(2),
      let first = indonesianWeekdayIndex(firstText), let last = indonesianWeekdayIndex(lastText), first != last
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
  /// weeks, months, or years, in their plain forms ("hari", "minggu", "pekan",
  /// "bulan", "tahun") or with "se-" ("sehari", "seminggu", "sepekan", "sebulan",
  /// "setahun"). A whole number of weeks counted in days is a weekly repeat ("14
  /// hari"), and a word that is no unit returns nil.
  private static func indonesianRepeat(unit: String, every: Int?) -> Repeat? {
    var key = indonesianKey(unit)
    if ["sehari", "seminggu", "sepekan", "sebulan", "setahun"].contains(key) { key.removeFirst(2) }
    switch key {
    case "hari":
      if let count = every, count % 7 == 0 { return weekly(every: count / 7 == 1 ? nil : count / 7, on: []) }
      return Repeat(rule: TaskRecurrenceRule(freq: .daily, interval: every))
    case "minggu", "pekan": return weekly(every: every, on: [])
    case "bulan": return monthly(every: every, on: nil)
    case "tahun": return Repeat(rule: TaskRecurrenceRule(freq: .yearly, interval: every))
    default: return nil
    }
  }

  /// "setiap 2 hari", "setiap tiga minggu", "tiap 2 bulan", "2 hari sekali",
  /// "dua minggu sekali", "seminggu sekali", "sebulan sekali", "setahun sekali",
  /// "sekali seminggu", "sekali dalam 2 minggu", "1x seminggu", "1 kali per
  /// bulan", "satu kali sebulan", each maybe before weekdays after a weekly
  /// interval ("setiap 2 minggu hari Kamis"). A count of times in a period ("dua
  /// kali seminggu") is no repeat and an interval of hours ("setiap 2 jam") is a
  /// length, so both stay in the title; "hari kerja" after a count is a count of
  /// working days. Groups: 1 and 2 the count and the unit after "setiap"; 3 and 4
  /// the count and the unit before "sekali"; 5 the "se-" unit before "sekali"; 6
  /// and 7 the count and the unit after "sekali"; 8 the "se-" unit after it; 9 the
  /// unit and 10 the "se-" unit after "1x"; 11 the weekdays.
  private static var indonesianIntervalRepeatPattern: String {
    let count = #"(\d{1,3}|\#(indonesianNumberWords))"#
    let units = #"(hari|minggu|pekan|bulan|tahun)"#
    let seUnits = #"(sehari|seminggu|sepekan|sebulan|setahun)"#
    let per = #"(?:(?:dalam|per|tiap|setiap)\s+)?"#
    let weekdays = #"(?:\s+(?:pada\s+)?(\#(indonesianRepeatNamesOnly)))?"#
    return
      #"\#(indonesianStart)(?:\#(indonesianEvery)\s+\#(count)\s+\#(units)(?!\s+kerja)|\#(count)\s+\#(units)\s+sekali|\#(seUnits)\s+sekali|sekali\s+\#(per)(?:\#(count)\s+\#(units)|\#(seUnits))|(?:1\s*x|(?:1|satu)\s+kali)\s+\#(per)(?:\#(units)|\#(seUnits)))\#(weekdays)\#(indonesianEnd)"#
  }

  /// The weekday names of a list that names Sunday only with "hari" before it, as
  /// a pattern without groups.
  private static var indonesianRepeatNamesOnly: String {
    let day = #"(?:hari\s+)?(?:\#(indonesianWeekdayNames)|hari\s+minggu)"#
    return #"\#(day)(?:\#(indonesianRepeatSeparator)\#(day)){0,6}"#
  }

  private static func indonesianIntervalRepeat(_ match: Match) -> Repeat? {
    let base: Repeat?
    if let countText = match.group(1), let unit = match.group(2) {
      base = indonesianCounted(countText, unit)
    } else if let countText = match.group(3), let unit = match.group(4) {
      base = indonesianCounted(countText, unit)
    } else if let unit = match.group(5) {
      base = indonesianRepeat(unit: unit, every: nil)
    } else if let countText = match.group(6), let unit = match.group(7) {
      base = indonesianCounted(countText, unit)
    } else if let unit = match.group(8) ?? match.group(9) ?? match.group(10) {
      base = indonesianRepeat(unit: unit, every: nil)
    } else {
      return nil
    }
    guard let base else { return nil }
    guard let list = match.group(11) else { return base }
    // A weekday after a weekly interval fixes the repeat's days.
    let days = indonesianRepeatWeekdays(list, isSundayAlone: true)
    return base.rule.freq == .weekly && !days.isEmpty ? weekly(every: base.rule.interval, on: days) : nil
  }

  /// The repeat every `count` of `unit`, for a count from 1 to 99.
  private static func indonesianCounted(_ countText: String, _ unit: String) -> Repeat? {
    guard let count = indonesianCount(countText), (1...99).contains(count) else { return nil }
    return indonesianRepeat(unit: unit, every: count == 1 ? nil : count)
  }

  // MARK: - Cadence phrases

  /// "setiap hari", "tiap pagi", "setiap malam", "setiap minggu", "setiap
  /// pekan", "setiap bulan", "setiap tahun", "setiap triwulan", "setiap
  /// kuartal", "setiap semester". "Hari" before a holiday, a name, or an
  /// exception ("setiap hari libur", "setiap hari Natal", "setiap hari kecuali
  /// Minggu"), "minggu" before an ordinal ("setiap minggu pertama"), and "bulan"
  /// before a month ("setiap bulan Oktober") name no cadence the app can set and
  /// stay in the title. Group 1: the unit or the part of the day after "setiap".
  private static var indonesianEveryUnitPattern: String {
    let names = indonesianWeekdayNames
    let months = indonesianMonthNames
    let notADay =
      #"(?!\s+(?:libur|raya|besar|natal|lebaran|nasional|ulang|gajian|pertama|terakhir|kerja|biasa|ini|itu|minggu|kecuali|selain|tanpa|\#(names))(?![\p{Latin}\p{M}]))"#
    let notAWeek = #"(?!\s+(?:ke|pertama|kedua|ketiga|keempat|terakhir|depan|ini|lalu|kemarin)(?![\p{Latin}\p{M}]))"#
    let notAMonth = #"(?!\s+(?:ke|pertama|terakhir|depan|ini|lalu|\#(months))(?![\p{Latin}\p{N}\p{M}]))"#
    return
      #"\#(indonesianStart)\#(indonesianEvery)\s+(hari\#(notADay)|pagi|siang|sore|malam|(?:minggu|pekan)\#(notAWeek)|bulan\#(notAMonth)|tahun|triwulan|kuartal|semester|caturwulan)\#(indonesianEnd)"#
  }

  private static func indonesianEveryUnit(_ match: Match) -> Repeat? {
    guard let word = match.group(1).map(indonesianKey) else { return nil }
    switch word {
    case "minggu", "pekan": return weekly(every: nil, on: [])
    case "bulan": return monthly(every: nil, on: nil)
    case "tahun": return Repeat(rule: TaskRecurrenceRule(freq: .yearly))
    case "triwulan", "kuartal": return monthly(every: 3, on: nil)
    case "semester": return monthly(every: 6, on: nil)
    case "caturwulan": return monthly(every: 4, on: nil)
    default: return Repeat(rule: TaskRecurrenceRule(freq: .daily))
    }
  }

  // MARK: - Adjectives

  /// "harian", "mingguan", "bulanan", "tahunan", "triwulanan" at the end of the
  /// line, or "harian", "mingguan", "bulanan", "tahunan" opening the line before a
  /// colon or a comma. The word is an adjective after its noun ("Laporan
  /// mingguan") and the end of the line is where it says how a task repeats; "buku
  /// harian" (a diary) and the other nouns the word makes ("koran harian") name no
  /// repeat. Groups: 1 the word at the end, 2 the word that opens the line.
  private static let indonesianAdjectivePattern =
    #"\#(indonesianStart)(?<!(?:buku|koran|majalah|tabloid|kabar)\s{1,3})(harian|mingguan|bulanan|tahunan|triwulanan)\#(indonesianEnd)(?=[\s.!]*$)|^\s*(harian|mingguan|bulanan|tahunan)\#(indonesianEnd)(?=\s*[:,，：])"#

  private static func indonesianAdjective(_ match: Match) -> Repeat? {
    guard let word = (match.group(1) ?? match.group(2)).map(indonesianKey) else { return nil }
    switch word {
    case "harian": return Repeat(rule: TaskRecurrenceRule(freq: .daily))
    case "mingguan": return weekly(every: nil, on: [])
    case "bulanan": return monthly(every: nil, on: nil)
    case "tahunan": return Repeat(rule: TaskRecurrenceRule(freq: .yearly))
    case "triwulanan": return monthly(every: 3, on: nil)
    default: return nil
    }
  }
}

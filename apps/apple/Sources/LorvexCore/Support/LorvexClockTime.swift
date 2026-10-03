import Foundation

/// Locale-aware display label for a stored `HH:MM` time-of-day string.
///
/// Storage and the domain layer use 24-hour `HH:MM`; the UI shows the clock
/// the user chose (``LorvexClockFormat``), by default the system's — "9:00 AM"
/// where the clock is 12-hour, "09:00" where it is 24-hour. Every event and task time display on
/// every surface (macOS and mobile) goes through this one helper so the format
/// is consistent and native everywhere. Returns the input unchanged if it is
/// not a parseable `HH:MM`.
public func lorvexClockTimeLabel(_ hourMinute: String) -> String {
  let trimmed = hourMinute.trimmingCharacters(in: .whitespaces)
  guard let date = LorvexDateFormatters.hourMinute.date(from: trimmed) else {
    return hourMinute
  }
  return LorvexDateFormatters.clockTime(date)
}

/// Locale-aware clock label for a minutes-since-midnight value, through
/// ``lorvexClockTimeLabel(_:)``. Values outside one day wrap onto the clock, so
/// 1440 (a block ending at midnight) reads as "12:00 AM".
public func lorvexClockTimeLabel(minutes: Int) -> String {
  let wrapped = ((minutes % 1440) + 1440) % 1440
  return lorvexClockTimeLabel(String(format: "%02d:%02d", wrapped / 60, wrapped % 60))
}

/// Locale-aware label for a span between two minutes-since-midnight values
/// ("9:45 – 10:30 AM" where the device is 12-hour, "09:45 – 10:30" where it is
/// 24-hour), naming the day period once when both ends share it. A span that
/// does not run forward within one day (it ends at or past midnight, or before
/// it starts) reads as the two clock labels joined by an en dash.
///
/// A Japanese span joins its two clock labels with a wave dash ("15:00～16:30",
/// "午後3:00～4:30"): the Japanese span pattern spells the times out
/// ("15時00分～16時30分") where a single time reads "15:00", so a span and the
/// times beside it would disagree, and the spelled-out span takes twice the
/// width.
public func lorvexClockRangeLabel(
  startMinutes: Int, endMinutes: Int, locale: Locale = LorvexClockFormat.displayLocale
) -> String {
  func date(_ minutes: Int) -> Date? {
    let wrapped = ((minutes % 1440) + 1440) % 1440
    return LorvexDateFormatters.hourMinute.date(from: String(format: "%02d:%02d", wrapped / 60, wrapped % 60))
  }
  func label(_ minutes: Int) -> String {
    date(minutes).map { LorvexDateFormatters.clockTime($0, locale: locale) } ?? lorvexClockTimeLabel(minutes: minutes)
  }
  let isJapanese = locale.language.languageCode == .japanese
  guard (0..<1440).contains(startMinutes), endMinutes > startMinutes, endMinutes < 1440,
    let start = date(startMinutes), let end = date(endMinutes), start < end
  else {
    return "\(label(startMinutes))\(isJapanese ? "～" : " – ")\(label(endMinutes))"
  }
  guard isJapanese else {
    return (start..<end).formatted(Date.IntervalFormatStyle(time: .shortened, locale: locale))
  }
  let isTwelveHour = [.oneToTwelve, .zeroToEleven].contains(locale.hourCycle)
  guard isTwelveHour, (startMinutes < 720) == (endMinutes < 720) else {
    return "\(label(startMinutes))～\(label(endMinutes))"
  }
  var withoutPeriod = Date.FormatStyle(locale: locale).hour(.defaultDigits(amPM: .omitted)).minute()
  withoutPeriod.timeZone = LorvexDateFormatters.hourMinute.timeZone
  return "\(label(startMinutes))～\(end.formatted(withoutPeriod))"
}

/// Locale-aware label for an event's stored `HH:MM` start and end: the span
/// through ``lorvexClockRangeLabel(startMinutes:endMinutes:)`` ("9:00 – 9:30 AM"),
/// with an end of `24:00` read as midnight at the end of the day. The start
/// alone, through ``lorvexClockTimeLabel(_:)``, when there is no end, the end
/// is the start, or either is not a parseable `HH:MM`.
public func lorvexClockRangeLabel(start: String, end: String?) -> String {
  guard let startMinutes = lorvexMinutesSinceMidnight(start),
    let endMinutes = lorvexEndMinutesSinceMidnight(end), endMinutes != startMinutes
  else { return lorvexClockTimeLabel(start) }
  return lorvexClockRangeLabel(startMinutes: startMinutes, endMinutes: endMinutes)
}

/// A `yyyy-MM-dd` product day spelled out without the year ("Tuesday,
/// September 22"), in the user's locale; the input unchanged when it is not a
/// day key. The day key names a calendar day, not an instant, so it is parsed
/// and formatted in UTC and never shifts across the device timezone.
public func lorvexDayLine(logicalDay: String) -> String {
  guard let date = LorvexDateFormatters.ymdUTC.date(from: logicalDay) else { return logicalDay }
  var style = Date.FormatStyle(date: .complete, time: .omitted)
  style.timeZone = .gmt
  return date.formatted(style.year(.omitted))
}

/// Minutes since midnight for a stored `HH:MM` time-of-day string, or `nil` when
/// it is not a parseable clock time.
///
/// Ordering key for anything that interleaves clock times from different
/// sources: calendar events store `HH:MM`, and comparing integers keeps a
/// single sort free of formatter and timezone concerns. Deliberately not a
/// `Date`: these are wall-clock times within one already-chosen day, so
/// anchoring them to a calendar would invent a precision they do not have.
public func lorvexMinutesSinceMidnight(_ hourMinute: String?) -> Int? {
  guard let hourMinute else { return nil }
  let parts = hourMinute.trimmingCharacters(in: .whitespaces).split(separator: ":")
  guard parts.count >= 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
    (0...23).contains(hour), (0...59).contains(minute)
  else { return nil }
  return hour * 60 + minute
}

/// Minutes since midnight for a stored `HH:MM` time that ends a span: as
/// ``lorvexMinutesSinceMidnight(_:)``, with `24:00` read as 1440, a span that
/// runs to midnight at the end of the day.
public func lorvexEndMinutesSinceMidnight(_ hourMinute: String?) -> Int? {
  if hourMinute?.trimmingCharacters(in: .whitespaces) == "24:00" { return 1440 }
  return lorvexMinutesSinceMidnight(hourMinute)
}

/// The stored `HH:MM` form of a minutes-since-midnight value, clamped to one
/// day, as task times travel in tool payloads and glance snapshots. 1440, a
/// span that runs to midnight at the end of the day, is `24:00`.
public func lorvexStoredClockTime(minutes: Int) -> String {
  let bounded = min(max(minutes, 0), 1440)
  return String(format: "%02d:%02d", bounded / 60, bounded % 60)
}

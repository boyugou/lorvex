import Foundation
import LorvexDomain

/// Shared daily-review write date resolution.
///
/// Daily reviews are intentionally backdateable only within a short window:
/// a stale draft from weeks ago should not overwrite history, and a far-future
/// date is almost certainly timezone drift or bad input. Keeping the policy in
/// one place lets App, MCP, and CLI write surfaces accept and reject the same
/// dates.
public enum DailyReviewDate {
  /// Most days a daily-review date may lag behind today before being rejected
  /// as a stale write.
  public static let maxStalenessDays: Int = 7

  /// Most days a daily-review date may lead today before being rejected as
  /// future drift.
  public static let futureSlackDays: Int = 1

  /// Rejection reason for a proposed daily-review write date. Each case's
  /// wording is a stable contract; keep it byte-identical across surfaces.
  public enum DateError: Error, Equatable, CustomStringConvertible {
    case invalidDate(field: String, value: String)
    case tooStale(date: String, today: String)
    case tooFarFuture(date: String, today: String)

    public var description: String {
      switch self {
      case .invalidDate(let field, let value):
        return "\(field) '\(value)' is not a valid YYYY-MM-DD calendar date"
      case .tooStale(let date, let today):
        return
          "daily review date '\(date)' is more than \(maxStalenessDays) days before today (\(today)); refusing to write a stale daily review."
      case .tooFarFuture(let date, let today):
        return
          "daily review date '\(date)' is more than \(futureSlackDays) day in the future of today (\(today)); refusing to write."
      }
    }
  }

  private static func parseYmd(field: String, value: String) -> Result<IsoDate.YMD, DateError> {
    guard case .success(let ymd) = IsoDate.parseIsoDate(value) else {
      return .failure(.invalidDate(field: field, value: value))
    }
    return .success(ymd)
  }

  /// Resolve the date a daily-review write should land on.
  ///
  /// `requestedDate` defaults to `today` when `nil`. Both inputs must be
  /// canonical `YYYY-MM-DD`. The resolved date must lie within
  /// `[today - maxStalenessDays, today + futureSlackDays]`; outside that band
  /// the write is rejected with ``DateError/tooStale(date:today:)`` or
  /// ``DateError/tooFarFuture(date:today:)``.
  public static func resolveDailyReviewWriteDate(
    requestedDate: String?, today: String
  ) -> Result<String, DateError> {
    let todayDate: IsoDate.YMD
    switch parseYmd(field: "today", value: today) {
    case .success(let v): todayDate = v
    case .failure(let e): return .failure(e)
    }
    let raw = requestedDate ?? today
    let parsed: IsoDate.YMD
    switch parseYmd(field: "daily review date", value: raw) {
    case .success(let v): parsed = v
    case .failure(let e): return .failure(e)
    }
    let diff = IsoDate.dayNumber(todayDate) - IsoDate.dayNumber(parsed)
    if diff < -futureSlackDays {
      return .failure(.tooFarFuture(date: raw, today: today))
    }
    if diff > maxStalenessDays {
      return .failure(.tooStale(date: raw, today: today))
    }
    return .success(parsed.canonicalString)
  }
}

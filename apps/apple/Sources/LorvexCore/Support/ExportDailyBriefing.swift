import Foundation

/// One day's briefing in an export: the assistant's note on that day, keyed by
/// its `YYYY-MM-DD` date. A day without a briefing has no record.
public struct ExportDailyBriefing: Codable, Sendable, Equatable {
  public var date: String
  public var briefing: String
  public var timezone: String?
  public var createdAt: String?
  public var updatedAt: String?

  public init(
    date: String,
    briefing: String,
    timezone: String? = nil,
    createdAt: String? = nil,
    updatedAt: String? = nil
  ) {
    self.date = date
    self.briefing = briefing
    self.timezone = timezone
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  static let columns = ["date", "briefing", "timezone", "createdAt", "updatedAt"]
  var csvRow: [String] {
    [date, briefing, timezone ?? "", createdAt ?? "", updatedAt ?? ""]
  }
}

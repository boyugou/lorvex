import Foundation

/// Flat DTO for a daily review row in the v1 backup wire. Non-optional fields
/// are required on decode; only fields modeled as optional may be absent.
public struct ExportDailyReview: Codable, Sendable {
  enum CodingKeys: String, CodingKey {
    case date
    case summary
    case mood
    case energyLevel
    case wins
    case blockers
    case learnings
    case timezone
    case updatedAt
    case linkedTaskIDs
    case linkedListIDs
  }

  public var date: String
  public var summary: String
  public var mood: Int?
  public var energyLevel: Int?
  public var wins: String
  public var blockers: String
  public var learnings: String
  public var timezone: String?
  public var updatedAt: String?
  public var linkedTaskIDs: [String]
  public var linkedListIDs: [String]

  public init(
    date: String,
    summary: String,
    mood: Int?,
    energyLevel: Int?,
    wins: String,
    blockers: String,
    learnings: String,
    timezone: String? = nil,
    updatedAt: String? = nil,
    linkedTaskIDs: [String] = [],
    linkedListIDs: [String] = []
  ) {
    self.date = date
    self.summary = summary
    self.mood = mood
    self.energyLevel = energyLevel
    self.wins = wins
    self.blockers = blockers
    self.learnings = learnings
    self.timezone = timezone
    self.updatedAt = updatedAt
    self.linkedTaskIDs = linkedTaskIDs
    self.linkedListIDs = linkedListIDs
  }

  public init(from review: DailyReviewEntry) {
    date = review.date
    summary = review.summary
    mood = review.mood
    energyLevel = review.energyLevel
    wins = review.wins ?? ""
    blockers = review.blockers ?? ""
    learnings = review.learnings ?? ""
    timezone = review.timezone
    updatedAt = review.updatedAt
    linkedTaskIDs = review.linkedTaskIDs
    linkedListIDs = review.linkedListIDs
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    date = try container.decode(String.self, forKey: .date)
    summary = try container.decode(String.self, forKey: .summary)
    mood = try container.decodeIfPresent(Int.self, forKey: .mood)
    energyLevel = try container.decodeIfPresent(Int.self, forKey: .energyLevel)
    wins = try container.decode(String.self, forKey: .wins)
    blockers = try container.decode(String.self, forKey: .blockers)
    learnings = try container.decode(String.self, forKey: .learnings)
    timezone = try container.decodeIfPresent(String.self, forKey: .timezone)
    updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
    linkedTaskIDs = try container.decode([String].self, forKey: .linkedTaskIDs)
    linkedListIDs = try container.decode([String].self, forKey: .linkedListIDs)
  }

  static let columns = [
    "date", "summary", "mood", "energyLevel", "wins", "blockers", "learnings",
    "timezone", "updatedAt", "linkedTaskIDs", "linkedListIDs",
  ]
  var csvRow: [String] {
    [
      date, summary, mood.map(String.init) ?? "", energyLevel.map(String.init) ?? "",
      wins, blockers, learnings, timezone ?? "", updatedAt ?? "",
      linkedTaskIDs.joined(separator: "|"), linkedListIDs.joined(separator: "|"),
    ]
  }
}

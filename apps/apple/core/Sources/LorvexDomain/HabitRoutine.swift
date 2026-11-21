import Foundation

/// A routine orders references to existing habits. A habit can belong to both
/// routines and still has just one completion record for a given day.
public struct HabitRoutine: Codable, Equatable, Sendable {
  public var startMinutes: Int
  public var habitIDs: [String]

  public init(startMinutes: Int, habitIDs: [String] = []) {
    self.startMinutes = startMinutes
    self.habitIDs = habitIDs
  }

  static func validate(_ value: JSONValue) -> Result<JSONValue, ValidationError> {
    guard case .object(let fields) = value, Set(fields.keys) == ["startMinutes", "habitIDs"],
      case .int(let start)? = fields["startMinutes"], (0..<1440).contains(start),
      case .array(let ids)? = fields["habitIDs"]
    else {
      return .failure(.message("a routine requires startMinutes (0–1439) and ordered habitIDs"))
    }
    var seen = Set<String>()
    for id in ids {
      guard case .string(let raw) = id, SyncEntityId.isCanonicalUuid(raw), seen.insert(raw).inserted
      else {
        return .failure(.message("habitIDs must be distinct canonical habit UUIDs"))
      }
    }
    return .success(value)
  }
}

public enum HabitRoutinePeriod: String, CaseIterable, Identifiable, Sendable {
  case morning, evening
  public var id: Self { self }

  public var preferenceKey: String {
    self == .morning ? PreferenceKeys.prefMorningRoutine : PreferenceKeys.prefEveningRoutine
  }

  public var defaultRoutine: HabitRoutine {
    HabitRoutine(startMinutes: self == .morning ? 360 : 1080)
  }
}

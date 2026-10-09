import Foundation
import LorvexDomain

/// Flat DTO for a habit row in an export. Carries the full typed cadence so
/// every rhythm — not just daily — round-trips through import: `frequencyType`
/// (`daily` / `weekly` / `monthly` / `times_per_week`), the `weekly` weekday set
/// (Monday-first 0=Mon … 6=Sun), the `times_per_week` count, and the `monthly`
/// day-of-month. `targetCount` is the per-day accumulative goal, decoupled from
/// the cadence.
public struct ExportHabit: Codable, Sendable {
  public var id: String
  public var name: String
  public var cue: String
  public var frequencyType: String
  public var weekdays: [Int]
  public var perPeriodTarget: Int?
  public var dayOfMonth: Int?
  public var targetCount: Int
  /// Optional user-set milestone goal; nil (absent in older exports) when unset.
  public var milestoneTarget: Int?
  public var icon: String?
  public var color: String?
  public var archived: Bool
  public var position: Int64
  /// The habit's creation instant, absent in archives written before the field
  /// existed. Import stamps the row with the import instant when it is absent,
  /// so a restored habit's 30-day adherence window starts on the restore day
  /// instead of its real creation day.
  public var createdAt: String?
  public var completions: [ExportHabitCompletion]
  /// The days the user set the habit aside (skipped days). Empty when there are
  /// none, and absent from archives written before skipped days existed.
  public var skips: [ExportHabitSkip]
  public var reminderPolicies: [ExportHabitReminderPolicy]

  public init(
    id: String,
    name: String,
    cue: String,
    icon: String? = nil,
    color: String? = nil,
    frequencyType: String,
    weekdays: [Int] = [],
    perPeriodTarget: Int? = nil,
    dayOfMonth: Int? = nil,
    targetCount: Int,
    milestoneTarget: Int? = nil,
    archived: Bool = false,
    position: Int64 = 0,
    createdAt: String? = nil,
    completions: [ExportHabitCompletion] = [],
    skips: [ExportHabitSkip] = [],
    reminderPolicies: [ExportHabitReminderPolicy] = []
  ) {
    self.id = id
    self.name = name
    self.cue = cue
    self.icon = icon
    self.color = color
    self.frequencyType = frequencyType
    self.weekdays = weekdays
    self.perPeriodTarget = perPeriodTarget
    self.dayOfMonth = dayOfMonth
    self.targetCount = targetCount
    self.milestoneTarget = milestoneTarget
    self.archived = archived
    self.position = position
    self.createdAt = createdAt
    self.completions = completions
    self.skips = skips
    self.reminderPolicies = reminderPolicies
  }

  /// `createdAt` is passed in rather than read from `habit`: ``LorvexHabit`` is
  /// the display projection and does not carry the row's creation instant.
  public init(
    from habit: LorvexHabit,
    createdAt: String? = nil,
    completions: [ExportHabitCompletion] = [],
    skips: [ExportHabitSkip] = [],
    reminderPolicies: [ExportHabitReminderPolicy] = []
  ) {
    id = habit.id
    name = habit.name
    cue = habit.cue ?? ""
    icon = habit.icon
    color = habit.color
    frequencyType = habit.frequencyType
    weekdays = habit.weekdays ?? []
    perPeriodTarget = habit.perPeriodTarget
    dayOfMonth = habit.dayOfMonth
    targetCount = habit.targetCount
    milestoneTarget = habit.milestoneTarget
    archived = habit.archived
    position = habit.position
    self.createdAt = createdAt
    self.completions = completions
    self.skips = skips
    self.reminderPolicies = reminderPolicies
  }

  enum CodingKeys: String, CodingKey {
    case id, name, cue, icon, color, frequencyType, weekdays, perPeriodTarget, dayOfMonth
    case targetCount, milestoneTarget, archived, position, createdAt, completions, skips
    case reminderPolicies
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    cue = try container.decode(String.self, forKey: .cue)
    icon = try container.decodeIfPresent(String.self, forKey: .icon)
    color = try container.decodeIfPresent(String.self, forKey: .color)
    frequencyType = try container.decode(String.self, forKey: .frequencyType)
    weekdays = try container.decode([Int].self, forKey: .weekdays)
    perPeriodTarget = try container.decodeIfPresent(Int.self, forKey: .perPeriodTarget)
    dayOfMonth = try container.decodeIfPresent(Int.self, forKey: .dayOfMonth)
    targetCount = try container.decode(Int.self, forKey: .targetCount)
    milestoneTarget = try container.decodeIfPresent(Int.self, forKey: .milestoneTarget)
    archived = try container.decode(Bool.self, forKey: .archived)
    position = try container.decode(Int64.self, forKey: .position)
    createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
    completions = try container.decode([ExportHabitCompletion].self, forKey: .completions)
    skips = try container.decodeIfPresent([ExportHabitSkip].self, forKey: .skips) ?? []
    reminderPolicies = try container.decode(
      [ExportHabitReminderPolicy].self, forKey: .reminderPolicies)
  }

  /// `skips` is written only when the habit has skipped days, so an archive of a
  /// habit without any is the same as one written before skipped days existed.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(name, forKey: .name)
    try container.encode(cue, forKey: .cue)
    try container.encodeIfPresent(icon, forKey: .icon)
    try container.encodeIfPresent(color, forKey: .color)
    try container.encode(frequencyType, forKey: .frequencyType)
    try container.encode(weekdays, forKey: .weekdays)
    try container.encodeIfPresent(perPeriodTarget, forKey: .perPeriodTarget)
    try container.encodeIfPresent(dayOfMonth, forKey: .dayOfMonth)
    try container.encode(targetCount, forKey: .targetCount)
    try container.encodeIfPresent(milestoneTarget, forKey: .milestoneTarget)
    try container.encode(archived, forKey: .archived)
    try container.encode(position, forKey: .position)
    try container.encodeIfPresent(createdAt, forKey: .createdAt)
    try container.encode(completions, forKey: .completions)
    if !skips.isEmpty { try container.encode(skips, forKey: .skips) }
    try container.encode(reminderPolicies, forKey: .reminderPolicies)
  }

  /// Bridge an export/import cadence back into the domain ``HabitCadence``.
  /// The v1 backup wire is canonical and fail-fast: invalid weekdays, duplicate
  /// pins, out-of-range month days, missing weekly targets, and detail fields
  /// that contradict the selected cadence are rejected rather than normalized.
  public static func cadence(
    frequencyType: String, weekdays: [Int], perPeriodTarget: Int?, dayOfMonth: Int?
  ) throws -> HabitCadence {
    guard weekdays.allSatisfy({ (0...6).contains($0) }) else {
      throw ValidationError.message("weekdays must contain only Monday-first values 0...6")
    }
    guard Set(weekdays).count == weekdays.count else {
      throw ValidationError.message("weekdays must not contain duplicates")
    }
    let parsedWeekdays = weekdays.compactMap(WeekDay.init(rawValue:))
    guard let parsedFrequency = HabitFrequencyType(rawValue: frequencyType) else {
      throw ValidationError.message("unsupported frequency_type '\(frequencyType)'")
    }
    switch parsedFrequency {
    case .daily:
      guard weekdays.isEmpty, perPeriodTarget == nil, dayOfMonth == nil else {
        throw ValidationError.message("daily cadence must not carry cadence detail fields")
      }
    case .weekly:
      guard perPeriodTarget == nil, dayOfMonth == nil else {
        throw ValidationError.message("weekly cadence only accepts weekday detail")
      }
    case .monthly:
      guard weekdays.isEmpty, perPeriodTarget == nil else {
        throw ValidationError.message("monthly cadence only accepts day_of_month detail")
      }
      if let dayOfMonth, !(1...31).contains(dayOfMonth) {
        throw ValidationError.message("day_of_month must be between 1 and 31")
      }
    case .timesPerWeek:
      guard weekdays.isEmpty, dayOfMonth == nil, let perPeriodTarget, perPeriodTarget > 0 else {
        throw ValidationError.message(
          "times_per_week cadence requires a positive per_period_target and no day pins")
      }
    }
    return try HabitCadence.fromFields(
      HabitFrequencyFields(
        frequencyType: frequencyType,
        weekdays: parsedWeekdays,
        perPeriodTarget: perPeriodTarget.map { Int64($0) } ?? 1,
        dayOfMonth: dayOfMonth))
  }

  static let columns = [
    "id", "name", "cue", "icon", "color", "frequencyType", "weekdays", "perPeriodTarget",
    "dayOfMonth", "targetCount", "milestoneTarget", "archived", "position", "createdAt",
    "completions", "skips", "reminderPolicies",
  ]

  /// CSV row. `weekdays` is a hyphen-joined list of Monday-first ints (empty
  /// string when none); the optional counts (`perPeriodTarget`, `dayOfMonth`,
  /// `milestoneTarget`) and `createdAt` render as "" when absent.
  var csvRow: [String] {
    [
      id, name, cue, icon ?? "", color ?? "", frequencyType,
      weekdays.map(String.init).joined(separator: "-"),
      perPeriodTarget.map(String.init) ?? "", dayOfMonth.map(String.init) ?? "",
      String(targetCount), milestoneTarget.map(String.init) ?? "", archived ? "true" : "false",
      String(position), createdAt ?? "", Self.encode(completions), Self.encode(skips),
      Self.encode(reminderPolicies),
    ]
  }

  private static func encode<T: Encodable>(_ values: [T]) -> String {
    guard !values.isEmpty,
      let data = try? JSONEncoder().encode(values),
      let string = String(data: data, encoding: .utf8)
    else { return "" }
    return string
  }
}

/// One synced `habit_completions` edge row embedded under its parent habit in
/// ordinary data exports.
public struct ExportHabitCompletion: Codable, Sendable, Equatable {
  public var completedDate: String
  public var value: Int
  public var note: String?
  public var createdAt: String
  public var updatedAt: String

  public init(
    completedDate: String,
    value: Int,
    note: String?,
    createdAt: String,
    updatedAt: String
  ) {
    self.completedDate = completedDate
    self.value = value
    self.note = note
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  public init(from entry: HabitCompletionEntry) {
    completedDate = entry.completedDate
    value = entry.value
    note = entry.note
    createdAt = entry.createdAt
    updatedAt = entry.updatedAt
  }
}

/// One synced `habit_skips` edge row embedded under its parent habit in ordinary
/// data exports: a day the user set the habit aside.
public struct ExportHabitSkip: Codable, Sendable, Equatable {
  public var skippedDate: String
  public var createdAt: String
  public var updatedAt: String

  public init(skippedDate: String, createdAt: String, updatedAt: String) {
    self.skippedDate = skippedDate
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

/// One synced `habit_reminder_policies` child row embedded under its parent
/// habit in ordinary data exports.
public struct ExportHabitReminderPolicy: Codable, Sendable, Equatable {
  public var id: String
  public var reminderTime: String
  public var enabled: Bool
  public var createdAt: String
  public var updatedAt: String

  public init(
    id: String,
    reminderTime: String,
    enabled: Bool,
    createdAt: String,
    updatedAt: String
  ) {
    self.id = id
    self.reminderTime = reminderTime
    self.enabled = enabled
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  public init(from policy: HabitReminderPolicy) {
    id = policy.id
    reminderTime = policy.reminderTime
    enabled = policy.enabled
    createdAt = policy.createdAt
    updatedAt = policy.updatedAt
  }
}

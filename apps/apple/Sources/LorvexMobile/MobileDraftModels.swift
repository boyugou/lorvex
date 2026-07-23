import Foundation
import LorvexCore

public struct MobileCaptureDraft: Equatable, Sendable {
  public var title: String
  public var notes: String

  public init(title: String = "", notes: String = "") {
    self.title = title
    self.notes = notes
  }

  public var trimmedTitle: String {
    title.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public var canSubmit: Bool {
    !trimmedTitle.isEmpty
  }

  public var parsedTitles: [String] {
    CaptureTitleParser.titles(from: title)
  }
}

public struct MobileListDraft: Equatable, Sendable {
  public var name: String
  public var description: String
  /// Lorvex hex color (e.g. "#34C759"); nil falls back to the accent.
  public var color: String?
  /// SF Symbol name; nil falls back to the tray glyph.
  public var icon: String?

  public init(
    name: String = "", description: String = "", color: String? = nil, icon: String? = nil
  ) {
    self.name = name
    self.description = description
    self.color = color
    self.icon = icon
  }

  public init(list: LorvexList) {
    self.name = list.name
    self.description = list.description ?? ""
    self.color = list.color
    self.icon = list.icon
  }

  public var trimmedName: String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public var trimmedDescription: String {
    description.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public var canSubmit: Bool {
    !trimmedName.isEmpty
  }
}

/// The top-level rhythm segment shown in the habit cadence editor. Projects the
/// four wire cadences onto three segments: `weekly` covers both weekday-pinned
/// ("weekly") and count-per-week ("times_per_week") styles, disambiguated by
/// ``MobileHabitWeeklyStyle``.
public enum MobileHabitCadenceMode: String, CaseIterable, Sendable {
  case daily
  case weekly
  case monthly
}

/// The weekly sub-style: pin to specific weekdays, or a target count of any days
/// per week.
public enum MobileHabitWeeklyStyle: String, CaseIterable, Sendable {
  case specificDays
  case timesPerWeek
}

public struct MobileHabitDraft: Equatable, Sendable {
  public var name: String
  /// The product concept is an *encouragement* — a motivating line, not a
  /// when-to-do cue. Stored in the Apple schema's `cue` column (cross-surface
  /// contract); only the Apple-facing label + intent are "encouragement".
  public var cue: String
  public var targetCountText: String
  /// The optional milestone goal as typed text: a positive integer sets the
  /// goal, an empty / non-positive field means "no goal" (an optional personal
  /// target the habit continues past). Parsed by ``milestoneTarget``.
  public var milestoneTargetText: String
  public var color: String?
  public var icon: String?
  // Cadence editor state. `cadenceInput` assembles these into the typed
  // `HabitCadenceInput` the core's create/update habit calls take; `init(habit:)`
  // maps a stored habit's flat cadence fields back onto them.
  public var cadenceMode: MobileHabitCadenceMode
  public var weeklyStyle: MobileHabitWeeklyStyle
  /// Selected weekdays for the weekly-specific-days cadence, Monday-first
  /// (0=Mon … 6=Sun).
  public var weekdays: Set<Int>
  public var timesPerWeek: Int
  public var dayOfMonth: Int

  public init(
    name: String = "", cue: String = "", targetCountText: String = "1",
    milestoneTargetText: String = "", color: String? = nil, icon: String? = nil,
    cadenceMode: MobileHabitCadenceMode = .daily,
    weeklyStyle: MobileHabitWeeklyStyle = .specificDays,
    weekdays: Set<Int> = [0, 1, 2, 3, 4, 5, 6],
    timesPerWeek: Int = 3,
    dayOfMonth: Int = 1
  ) {
    self.name = name
    self.cue = cue
    self.targetCountText = targetCountText
    self.milestoneTargetText = milestoneTargetText
    self.color = color
    self.icon = icon
    self.cadenceMode = cadenceMode
    self.weeklyStyle = weeklyStyle
    self.weekdays = weekdays
    self.timesPerWeek = timesPerWeek
    self.dayOfMonth = dayOfMonth
  }

  public init(habit: LorvexHabit) {
    self.name = habit.name
    self.cue = habit.cue ?? ""
    self.targetCountText = "\(habit.targetCount)"
    self.milestoneTargetText = habit.milestoneTarget.map { "\($0)" } ?? ""
    self.color = habit.color
    self.icon = habit.icon
    // Map the stored cadence back onto the editor. A weekly habit with no pinned
    // weekdays is a weekly-every-day, which reads as Daily; an unrecognized type
    // falls back to Daily.
    switch habit.frequencyType {
    case "weekly":
      let days = Set(habit.weekdays ?? [])
      if days.isEmpty {
        self.cadenceMode = .daily
        self.weeklyStyle = .specificDays
        self.weekdays = [0, 1, 2, 3, 4, 5, 6]
      } else {
        self.cadenceMode = .weekly
        self.weeklyStyle = .specificDays
        self.weekdays = days
      }
      self.timesPerWeek = 3
      self.dayOfMonth = 1
    case "times_per_week":
      self.cadenceMode = .weekly
      self.weeklyStyle = .timesPerWeek
      self.weekdays = [0, 1, 2, 3, 4, 5, 6]
      self.timesPerWeek = max(1, min(7, habit.perPeriodTarget ?? 3))
      self.dayOfMonth = 1
    case "monthly":
      self.cadenceMode = .monthly
      self.weeklyStyle = .specificDays
      self.weekdays = [0, 1, 2, 3, 4, 5, 6]
      self.timesPerWeek = 3
      self.dayOfMonth = max(1, min(31, habit.dayOfMonth ?? 1))
    default:
      self.cadenceMode = .daily
      self.weeklyStyle = .specificDays
      self.weekdays = [0, 1, 2, 3, 4, 5, 6]
      self.timesPerWeek = 3
      self.dayOfMonth = 1
    }
  }

  /// The wire `frequency_type` the current editor selections resolve to — used
  /// to key the milestone-goal hint (streak vs. count) to the chosen cadence.
  public var frequencyType: String {
    switch cadenceMode {
    case .daily: return "daily"
    case .weekly: return weeklyStyle == .timesPerWeek ? "times_per_week" : "weekly"
    case .monthly: return "monthly"
    }
  }

  /// Whether a per-day target field applies. The count-per-week and monthly
  /// cadences carry their goal in the cadence itself (a fixed one-per-day
  /// target), so the per-day field is hidden and the saved target is forced to 1.
  public var showsPerDayTarget: Bool {
    frequencyType == "daily" || frequencyType == "weekly"
  }

  /// The `target_count` to persist: the typed per-day goal for the cadences that
  /// use it, or 1 for the count-per-week / monthly cadences.
  public var resolvedTargetCount: Int? {
    guard showsPerDayTarget else { return 1 }
    return targetCount
  }

  /// The typed cadence to persist, assembled from the editor selections. An
  /// empty weekly weekday set is normalized to every-day by the core.
  public var cadenceInput: HabitCadenceInput {
    switch cadenceMode {
    case .daily:
      return .daily
    case .weekly:
      switch weeklyStyle {
      case .specificDays:
        return HabitCadenceInput(
          frequencyType: "weekly",
          weekdays: weekdays.isEmpty ? nil : weekdays.sorted())
      case .timesPerWeek:
        return HabitCadenceInput(
          frequencyType: "times_per_week", perPeriodTarget: max(1, min(7, timesPerWeek)))
      }
    case .monthly:
      return HabitCadenceInput(frequencyType: "monthly", dayOfMonth: max(1, min(31, dayOfMonth)))
    }
  }

  public var trimmedName: String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public var trimmedCue: String {
    cue.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public var targetCount: Int? {
    Int(targetCountText.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  /// The parsed milestone goal: a positive integer, or nil when the field is
  /// empty or not a positive number (an optional personal goal, so a blank or
  /// invalid field simply means "no goal").
  public var milestoneTarget: Int? {
    let text = milestoneTargetText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let value = Int(text), value > 0 else { return nil }
    return value
  }

  public var canSubmit: Bool {
    guard let count = resolvedTargetCount, count > 0 else { return false }
    return !trimmedName.isEmpty
  }
}

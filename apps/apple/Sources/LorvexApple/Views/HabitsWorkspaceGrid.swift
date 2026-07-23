import Foundation
import LorvexCore

extension HabitsWorkspaceView {
  /// The visible habits grouped by cadence bucket, non-empty buckets only, in
  /// Daily → Weekly → Monthly order. Order within a bucket follows the stored
  /// habit order.
  func habitGroups(_ habits: [LorvexHabit]) -> [(bucket: HabitCadenceBucket, habits: [LorvexHabit])] {
    let grouped = Dictionary(grouping: habits) {
      HabitCadenceBucket(frequencyType: $0.frequencyType)
    }
    return HabitCadenceBucket.allCases.compactMap { bucket in
      guard let habits = grouped[bucket], !habits.isEmpty else { return nil }
      return (bucket, habits)
    }
  }
}

/// The three cadence buckets the habit board groups by. Derived from a habit's
/// `frequency_type` via the same mapping as the card's rhythm strip, so a
/// "specific weekdays" or "N times a week" habit groups under Weekly.
enum HabitCadenceBucket: Int, CaseIterable, Hashable {
  case daily = 0
  case weekly = 1
  case monthly = 2

  init(frequencyType: String) {
    switch HabitRhythmStrip.granularity(forFrequencyType: frequencyType) {
    case .day: self = .daily
    case .week: self = .weekly
    case .month: self = .monthly
    }
  }

  var title: String {
    switch self {
    case .daily:
      String(localized: "habits.frequency.daily", defaultValue: "Daily", table: "Localizable", bundle: LorvexL10n.bundle)
    case .weekly:
      String(localized: "habits.frequency.weekly", defaultValue: "Weekly", table: "Localizable", bundle: LorvexL10n.bundle)
    case .monthly:
      String(localized: "habits.frequency.monthly", defaultValue: "Monthly", table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }
}

public extension TaskRecurrenceRule {
  func displaySummary(exceptions: [String] = []) -> String {
    var parts: [String] = []
    if let interval, interval > 1 {
      parts.append("Every \(interval) \(freq.intervalUnit)s")
    } else {
      parts.append(freq.displayName)
    }
    if let byDay, !byDay.isEmpty {
      parts.append(byDay.joined(separator: ", "))
    }
    if let count {
      parts.append("\(count) times")
    } else if let until {
      parts.append("until \(until)")
    }
    if !exceptions.isEmpty {
      parts.append("\(exceptions.count) skipped")
    }
    return parts.joined(separator: " · ")
  }
}

public extension TaskRecurrenceRule.Frequency {
  var displayName: String {
    switch self {
    case .daily: "Daily"
    case .weekly: "Weekly"
    case .monthly: "Monthly"
    case .yearly: "Yearly"
    }
  }

  var intervalUnit: String {
    switch self {
    case .daily: "day"
    case .weekly: "week"
    case .monthly: "month"
    case .yearly: "year"
    }
  }
}

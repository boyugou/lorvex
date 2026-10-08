import Foundation
import LorvexCore

extension LorvexList {
  /// What VoiceOver reads for the list: "Work: 4 open tasks, 10 total", or
  /// "Work: no tasks" for a list that holds none. The sidebar row and the
  /// Lists catalog card both read it, so a list is spoken the same way in
  /// both.
  var spokenSummary: String {
    guard totalCount > 0 else {
      return String(
        localized: "a11y.list.empty", defaultValue: "\(displayName): no tasks",
        table: "Localizable", bundle: LorvexL10n.bundle)
    }
    return String(
      localized: "a11y.list.format",
      defaultValue: "\(displayName): \(openCount) open tasks, \(totalCount) total",
      table: "Localizable", bundle: LorvexL10n.bundle)
  }
}

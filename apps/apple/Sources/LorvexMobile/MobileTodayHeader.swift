import Foundation

/// The date line under Today's navigation title on every layout: localized
/// "Weekday, Month Day" (e.g. "Monday, June 29") in the app's chosen locale.
/// Today draws no in-content header — the tab bar or sidebar already says
/// "Today", and an open-task count would only restate the list beneath it.
enum MobileTodayHeader {
  static func dateText() -> String {
    let formatter = DateFormatter()
    formatter.locale = MobileL10n.locale
    formatter.setLocalizedDateFormatFromTemplate("EEEEMMMMd")
    return formatter.string(from: Date())
  }
}

import Foundation

/// A short, localized minutes label ("90 min" / "90 分钟") for task estimates
/// and the lengths of planned times: the one minutes form shared by task rows,
/// the task table, the estimate pills, and Today's schedule, and the same
/// words Today, the widgets, and the watch use for a length.
func lorvexMinutesLabel(_ minutes: Int) -> String {
  String(
    format: String(localized: "common.duration.minutes_short", defaultValue: "%lld min", table: "Localizable", bundle: LorvexL10n.bundle),
    minutes
  )
}

import LorvexCore
import SwiftUI

/// The composed Today header — today's date and, when a focus plan exists, a
/// compact "In Focus" pill. Sits on a cleared list-row background at the top of
/// the Today list. VoiceOver reads the date together with the day's task summary
/// (open / focus counts + next task) via ``MobileHomeSummary/taskStatusText``,
/// since that glanceable count is intentionally not shown visually here.
struct MobileTodayHeader: View {
  let summary: MobileHomeSummary

  var body: some View {
    // Deliberately minimal: the tab bar already says "Today" (no giant title
    // needed) and the open-task count just duplicated the list right below it.
    // Keep the date for orientation and a compact focus pill when there's a plan.
    let dateText = Self.dateText()
    return HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.s) {
      Text(dateText)
        .font(.title3.weight(.semibold))
        .foregroundStyle(.primary)
        .accessibilityLabel(Self.accessibilityLabel(date: dateText, status: summary.taskStatusText))
      Spacer(minLength: 0)
      if summary.focusTaskCount > 0 {
        focusPill
      }
    }
    .padding(.top, LorvexDesign.Spacing.xs)
  }

  private var focusPill: some View {
    HStack(spacing: 5) {
      Image(systemName: "scope")
      Text(Self.focusCountText(summary.focusTaskCount))
    }
    .font(.footnote.weight(.semibold))
    .foregroundStyle(LorvexDesign.Palette.focus)
    .padding(.horizontal, 10)
    .padding(.vertical, 5)
    .background(LorvexDesign.Palette.focus.opacity(0.14), in: Capsule())
    .accessibilityElement(children: .combine)
  }

  /// Localized "Weekday, Month Day" (e.g. "Monday, June 29").
  static func dateText() -> String {
    let formatter = DateFormatter()
    formatter.locale = MobileL10n.locale
    formatter.setLocalizedDateFormatFromTemplate("EEEEMMMMd")
    return formatter.string(from: Date())
  }

  static func focusCountText(_ count: Int) -> String {
    String(
      localized: "today.metric.focus", defaultValue: "\(count) in focus",
      table: "Localizable", bundle: MobileL10n.bundle)
  }

  static func accessibilityLabel(date: String, status: String) -> String {
    String(
      format: String(
        localized: "today.header.a11y", defaultValue: "%1$@. %2$@",
        table: "Localizable", bundle: MobileL10n.bundle),
      date,
      status
    )
  }
}

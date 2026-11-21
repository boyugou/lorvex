import SwiftUI

extension LorvexCalmToday.Overbooked {
  public var planningRows: [ReviewTaskSummary] {
    (candidates + alternatives).map { task in
      ReviewTaskSummary(id: task.id, title: task.title, status: task.status.rawValue,
        deferCount: task.deferCount, dueDate: task.dueDate.map(LorvexDateFormatters.ymdUTC.string(from:)),
        plannedDate: task.plannedDate.map(LorvexDateFormatters.ymdUTC.string(from:)),
        estimatedMinutes: task.estimatedMinutes)
    }
  }
}

/// Shows what each day would gain or give up if the current selection moved.
public struct LorvexDayTransferForecast: View {
  private let todayRemaining: Int
  private let load: ReviewTomorrowLoad
  private let window: Range<Int>

  public init(todayRemaining: Int, tomorrow: ReviewTomorrowLoad, window: Range<Int>) {
    self.todayRemaining = todayRemaining
    load = tomorrow
    self.window = window
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
      row(String(localized: "day_phrase.today", defaultValue: "Today", table: "Localizable", bundle: CoreL10n.bundle),
        before: todayRemaining, after: todayRemaining + load.selectedMinutes)
      Divider()
      let remaining = window.count - load.plannedMinutes
      row(String(localized: "day_phrase.tomorrow", defaultValue: "Tomorrow", table: "Localizable", bundle: CoreL10n.bundle),
        before: remaining + load.selectedMinutes, after: remaining)
    }
  }

  private func row(_ label: String, before: Int, after: Int) -> some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
      Text(label).font(LorvexDesign.Typography.pageLabel).foregroundStyle(.secondary)
      let result = Text(balance(after)).font(LorvexDesign.Typography.sectionHeader)
      if before == after {
        result
      } else {
        let original = Text(balance(before)).font(LorvexDesign.Typography.secondaryText).foregroundStyle(.secondary)
        ViewThatFits(in: .horizontal) {
          HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.s) {
            original
            Image(systemName: "arrow.forward").foregroundStyle(.secondary).accessibilityHidden(true)
            result
          }
          .fixedSize(horizontal: true, vertical: false)
          VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
            original
            HStack(alignment: .firstTextBaseline) {
              Image(systemName: "arrow.turn.down.forward").foregroundStyle(.secondary).accessibilityHidden(true)
              result
            }
          }
        }
      }
    }
    .accessibilityElement(children: .combine)
  }

  private func balance(_ minutes: Int) -> String {
    let duration = lorvexUnbreakable(LorvexDurationFormat.hoursAndMinutes(abs(minutes)))
    return minutes < 0
      ? String(localized: "calendar.week.load.over", defaultValue: "\(duration) over", table: "Localizable", bundle: CoreL10n.bundle)
      : String(localized: "review.plan.available", defaultValue: "\(duration) free", table: "Localizable", bundle: CoreL10n.bundle)
  }
}

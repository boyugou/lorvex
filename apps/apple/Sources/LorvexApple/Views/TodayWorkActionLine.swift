import LorvexCore
import SwiftUI

struct TodayWorkActionLine: View {
  let store: AppStore
  let task: LorvexTask
  let cue: TodayWorkCue

  var body: some View {
    let showButton = cue.action == .start || store.selectedTaskID != cue.taskID
    if showButton || detail != nil {
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
        if showButton, cue.action == .resume,
          let step = task.checklistItems.first(where: { $0.completedAt == nil }) {
          Label {
            Text(userContent: step.text).lineLimit(2)
          } icon: {
            Image(systemName: "checklist")
          }
          .accessibilityLabel(String(localized: "task_detail.checklist.item_a11y", defaultValue: "Checklist item",
            table: "Localizable", bundle: LorvexL10n.bundle))
          .accessibilityValue(Text(userContent: step.text))
          .accessibilityIdentifier("today.work.nextStep")
        }
        ViewThatFits(in: .horizontal) {
          HStack(spacing: LorvexDesign.Spacing.s) {
            if showButton { action }
            if let detail { Text(verbatim: detail).lineLimit(1).fixedSize() }
          }
          VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
            if showButton { action }
            if let detail { Text(verbatim: detail).lineLimit(2).fixedSize(horizontal: false, vertical: true) }
          }
        }
      }
      .font(LorvexDesign.Typography.secondaryText)
      .foregroundStyle(.secondary)
      .padding(.leading, LorvexTaskRow.titleInset)
      .padding(.bottom, LorvexDesign.Spacing.s)
    }
  }

  private var action: some View {
    Button {
      Task { await store.performTodayWorkAction(cue) }
    } label: {
      Label(title, systemImage: cue.bringsTaskToTop ? "play.fill" : "calendar")
    }
    .buttonStyle(.bordered)
    .controlSize(.small)
    .accessibilityIdentifier("today.work.action.\(cue.taskID)")
  }

  private var title: String {
    switch cue.action {
    case .start:
      String(localized: "task.action.start", defaultValue: "Start", table: "Localizable", bundle: LorvexL10n.bundle)
    case .resume:
      String(localized: "today.work.continue", defaultValue: "Continue", table: "Localizable", bundle: LorvexL10n.bundle)
    case .reviewConflict:
      TodayCalmCopy.openDetails
    }
  }

  private var detail: String? {
    if case .reviewConflict(let event) = cue.action {
      return String(localized: "today.work.conflict", defaultValue: "Overlaps \(event)",
        table: "Localizable", bundle: LorvexL10n.bundle)
    }
    guard let next = cue.upcoming else { return nil }
    let duration = LorvexDurationFormat.hoursAndMinutes(next.minutesAway)
    return String(localized: "today.work.before_event", defaultValue: "\(duration) until \(next.title)",
      table: "Localizable", bundle: LorvexL10n.bundle)
  }
}

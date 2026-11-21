import LorvexCore
import SwiftUI

/// Appears below the one task the person can work on now. Each control has
/// its own list row so tapping Start never also activates the task's link.
struct MobileTodayWorkAction: View {
  let store: MobileStore
  let item: LorvexCalmToday.Item
  let cue: TodayWorkCue
  let showsCountdown: Bool
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
      if cue.action == .resume, let step = item.task.checklistItems.first(where: { $0.completedAt == nil }) {
        Label {
          Text(userContent: step.text).lineLimit(typeSize.isAccessibilitySize ? nil : 2)
        } icon: {
          Image(systemName: "checklist")
        }
        .accessibilityIdentifier("today.work.nextStep")
      }
      if showsCountdown, let next = cue.upcoming {
        let duration = LorvexDurationFormat.hoursAndMinutes(next.minutesAway)
        Text(String(localized: "today.work.before_event", defaultValue: "\(duration) until \(next.title)",
          table: "Localizable", bundle: MobileL10n.bundle))
          .accessibilityIdentifier("today.work.upcoming")
      }
      Button {
        Task { await store.openTodayWork(cue) }
      } label: {
        Text(verbatim: title)
          .padding(.horizontal, LorvexDesign.Spacing.s)
          .frame(minHeight: 32)
      }
      .buttonStyle(.borderedProminent)
      .buttonBorderShape(.capsule)
      .tint(LorvexDesign.Palette.accent)
      .font(LorvexDesign.Typography.primaryText.weight(.semibold))
      .accessibilityValue(Text(userContent: item.task.title))
      .accessibilityIdentifier("today.work.action.\(item.id)")
      .disabled(store.taskIsMutating(item.id))
    }
    .font(LorvexDesign.Typography.secondaryText)
  }

  private var title: String {
    if cue.action == .start {
      String(localized: "action.start", defaultValue: "Start", table: "Localizable", bundle: MobileL10n.bundle)
    } else {
      String(localized: "today.work.continue", defaultValue: "Continue", table: "Localizable", bundle: MobileL10n.bundle)
    }
  }
}

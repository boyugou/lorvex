import LorvexCore
import SwiftUI

/// Suggested times the user is deciding on, in a panel above the day's
/// timeline and drawn in its columns (``LorvexProposedScheduleRows``), so the
/// two read against each other. The two answers stand beside the panel's
/// title, where a long proposal cannot push them out of view: use the times,
/// which saves them and can be undone with ⌘Z, or dismiss them. Tasks that
/// did not fit can be moved to tomorrow from a button under the panel.
struct TodaySuggestedTimesSection: View {
  let proposal: DayTimesProposal
  /// The day's timeline, where an event finds its calendar's color.
  let dayRows: [LorvexTodayTimelineItem]
  let accept: () -> Void
  let dismiss: () -> Void
  /// Defers the tasks that did not fit to tomorrow.
  let moveUnscheduledToTomorrow: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
      HStack(spacing: LorvexDesign.Spacing.s) {
        WorkspaceTaskSectionHeader(
          title: TodayCalmCopy.suggestionTitle,
          systemImage: "calendar.badge.clock",
          tint: .accentColor,
          topSpacing: 0,
          bottomSpacing: 0
        )
        answers
      }
      // Inset like the Current Schedule label below; the panel and its
      // buttons share the briefing card's edges.
      .padding(.horizontal, LorvexDesign.Spacing.s)
      .padding(.top, LorvexDesign.Spacing.s)
      .padding(.bottom, LorvexDesign.Spacing.xs)

      if proposal.placesNothing {
        Text(TodayCalmCopy.noTimeLeft(workingHours: proposal.workingHours))
          .font(LorvexDesign.Typography.secondaryText)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.horizontal, LorvexDesign.Spacing.l)
          .accessibilityIdentifier("today.suggestion.noTimeLeft")
      }

      // No inner inset: the rows carry the timeline's own padding, so their
      // time column lines up with the timeline's below the panel.
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
        LorvexProposedScheduleRows(
          proposal: proposal, dayRows: dayRows, wontFitLabel: TodayCalmCopy.wontFit,
          busyLabel: TodayCalmCopy.busy, durationLabel: { LorvexDurationFormat.minutes($0) })
      }
      .padding(.vertical, LorvexDesign.Spacing.xs)
      .lorvexInsetPanel(padding: 0)

      // What did not fit has somewhere to go: tomorrow, one click away, under
      // the rows that say what did not fit.
      if !proposal.unscheduled.isEmpty {
        HStack(spacing: 0) {
          Button(TodayCalmCopy.overbookedAction, action: moveUnscheduledToTomorrow)
            .help(TodayCalmCopy.moveUnscheduledHelp(proposal.unscheduled.count))
            .accessibilityIdentifier("today.suggestion.moveToTomorrow")
          Spacer(minLength: 0)
        }
        .controlSize(.small)
        // Clear of the panel's edge, which the button otherwise appears to hang from.
        .padding(.top, LorvexDesign.Spacing.xs)
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("today.suggestion")
  }

  /// Dismiss, then Use These Times: the prominent button is the answer the
  /// suggestion asks for, and the one Return takes.
  private var answers: some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      Button(TodayCalmCopy.dismissSuggestion, action: dismiss)
        .accessibilityIdentifier("today.suggestion.dismiss")
      if !proposal.placements.isEmpty {
        Button(TodayCalmCopy.useSuggestion, action: accept)
          .buttonStyle(.borderedProminent)
          .keyboardShortcut(.defaultAction)
          .accessibilityIdentifier("today.suggestion.use")
      }
    }
    .controlSize(.small)
  }
}

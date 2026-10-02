import LorvexCore
import SwiftUI

/// Suggested times the user is deciding on, in a panel above the day's
/// timeline and drawn in its columns (``LorvexProposedScheduleRows``), so the
/// two read against each other. The panel closes with the two answers: use
/// the times, which saves them and can be undone with ⌘Z, or dismiss them.
/// Tasks that did not fit can be moved to tomorrow from the same row.
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
      WorkspaceTaskSectionHeader(
        title: TodayCalmCopy.suggestionTitle,
        systemImage: "calendar.badge.clock",
        tint: .accentColor,
        topSpacing: LorvexDesign.Spacing.s
      )
      // Inset like the Current Schedule label below; the panel and its
      // buttons share the briefing card's edges.
      .padding(.horizontal, LorvexDesign.Spacing.s)

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

      HStack(spacing: LorvexDesign.Spacing.s) {
        // What did not fit has somewhere to go: tomorrow, one click away.
        if !proposal.unscheduled.isEmpty {
          Button(TodayCalmCopy.overbookedAction, action: moveUnscheduledToTomorrow)
            .help(TodayCalmCopy.moveUnscheduledHelp(proposal.unscheduled.count))
            .accessibilityIdentifier("today.suggestion.moveToTomorrow")
        }
        Spacer(minLength: 0)
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
      // Clear of the panel's edge, which the buttons otherwise appear to hang from.
      .padding(.top, LorvexDesign.Spacing.xs)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("today.suggestion")
  }
}

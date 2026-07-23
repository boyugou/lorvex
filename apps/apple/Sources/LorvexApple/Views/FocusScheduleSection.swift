import LorvexCore
import SwiftUI

struct FocusScheduleSection: View {
  let title: String
  let schedule: FocusSchedule

  private var scheduleItemCount: Int {
    schedule.blocks.count + schedule.unscheduled.count
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      WorkspaceTaskSectionHeader(
        title: title,
        count: scheduleItemCount,
        systemImage: "calendar.badge.clock",
        tint: .accentColor,
        topSpacing: LorvexDesign.Spacing.s
      )
      .padding(.horizontal, LorvexDesign.Spacing.l)

      VStack(spacing: 0) {
        ForEach(Array(schedule.blocks.enumerated()), id: \.offset) { _, block in
          FocusScheduleBlockRow(block: block)
        }

        if !schedule.unscheduled.isEmpty {
          ForEach(schedule.unscheduled) { task in
            FocusScheduleUnscheduledRow(task: task)
          }
        }
      }
      .padding(.horizontal, LorvexDesign.Spacing.m)
      .padding(.vertical, LorvexDesign.Spacing.s)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.quaternary.opacity(0.08), in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.s))
      .overlay {
        RoundedRectangle(cornerRadius: LorvexDesign.Radius.s)
          .stroke(.separator.opacity(0.18), lineWidth: 0.5)
      }
      .padding(.horizontal, LorvexDesign.Spacing.m)
      .accessibilityIdentifier("focus.schedule.panel")
    }
  }
}

private struct FocusScheduleBlockRow: View {
  let block: FocusScheduleBlock

  var body: some View {
    HStack(spacing: 12) {
      Text(timeRange)
        .font(LorvexDesign.Typography.tertiaryText.monospacedDigit().weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary, in: Capsule())
        .accessibilityLabel(timeAccessibilityLabel)

      Image(systemName: iconName)
        .foregroundStyle(block.kind == .task ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        .frame(width: 18)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .lineLimit(1)
        Text(kindLabel)
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
    }
    .padding(.vertical, 3)
  }

  /// Glyph by block kind: focus work, a calendar hold, or a transition break.
  private var iconName: String {
    switch block.kind {
    case .task: return "scope"
    case .buffer: return "cup.and.saucer"
    case .calendarEvent, .unknown: return "calendar"
    }
  }

  private var title: String {
    if let title = block.title, !title.isEmpty { return title }
    if block.kind == .buffer {
      return String(
        localized: "focus.schedule.block.buffer_title", defaultValue: "Break",
        table: "Localizable",
        bundle: LorvexL10n.bundle)
    }
    return block.taskID ?? block.calendarEventID ?? String(
      localized: "focus.schedule.block.fallback_title",
      defaultValue: "Focus block",
      table: "Localizable",
      bundle: LorvexL10n.bundle
    )
  }

  private var timeRange: String {
    "\(lorvexClockTimeLabel(block.startTime))–\(lorvexClockTimeLabel(block.endTime))"
  }

  private var timeAccessibilityLabel: String {
    String(
      format: String(
        localized: "focus.schedule.block.time_accessibility",
        defaultValue: "%@ to %@",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      ),
      lorvexClockTimeLabel(block.startTime),
      lorvexClockTimeLabel(block.endTime)
    )
  }

  private var kindLabel: LocalizedStringResource {
    switch block.kind {
    case .task:
      return LocalizedStringResource("focus.schedule.block.kind.task", defaultValue: "Focus task", table: "Localizable", bundle: LorvexL10n.bundle)
    case .buffer:
      return LocalizedStringResource("focus.schedule.block.kind.buffer", defaultValue: "Buffer", table: "Localizable", bundle: LorvexL10n.bundle)
    case .calendarEvent, .unknown:
      return LocalizedStringResource("focus.schedule.block.kind.calendar", defaultValue: "Calendar hold", table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }
}

private struct FocusScheduleUnscheduledRow: View {
  let task: FocusScheduleTask

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "exclamationmark.triangle")
        .foregroundStyle(.orange)
        .frame(width: 18)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 2) {
        Text(task.title)
          .lineLimit(1)
        Text(detailLabel)
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
    }
    .padding(.vertical, 3)
  }

  private var detailLabel: String {
    guard let minutes = task.estimatedMinutes else {
      return String(
        localized: "focus.schedule.unscheduled.no_estimate",
        defaultValue: "Not scheduled",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      )
    }
    return String(
      format: String(
        localized: "focus.schedule.unscheduled.estimated",
        defaultValue: "Not scheduled, %@",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      ),
      lorvexMinutesLabel(minutes)
    )
  }
}

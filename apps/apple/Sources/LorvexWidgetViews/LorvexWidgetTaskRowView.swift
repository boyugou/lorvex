import AppIntents
import Foundation
import LorvexCore
import LorvexWidgetIntents
import LorvexWidgetKitSupport
import SwiftUI

struct WidgetActionButton<Intent: AppIntent>: View {
  let intent: Intent
  let systemName: String
  let accessibilityLabel: String
  var tint: Color = .secondary

  var body: some View {
    Button(intent: intent) {
      Image(systemName: systemName)
        .imageScale(.medium)
        .frame(minWidth: 32, minHeight: 32)
        .contentShape(Rectangle())
    }
    .buttonStyle(.borderless)
    .foregroundStyle(tint)
    .accessibilityLabel(accessibilityLabel)
  }
}

/// A task row that links to the task deep-link URL and, when `interactive` is
/// true, shows a trailing complete checkbox powered by a widget intent. Pass
/// `interactive: true` only for medium and large families. `compactActions`
/// (medium) shows complete alone; large adds a secondary defer. Destructive
/// actions (cancel / remove-from-focus) are deliberately absent — they belong in
/// the app, not on a glanceable widget.
struct LinkedTaskRowView: View {
  let row: WidgetTaskRenderRow
  var interactive: Bool = false
  var compactActions: Bool = false

  var body: some View {
    HStack(spacing: 4) {
      rowContent
      if interactive {
        Spacer(minLength: 0)
        taskActionButtons
      }
    }
  }

  private var taskActionButtons: some View {
    HStack(spacing: 6) {
      if !compactActions {
        WidgetActionButton(
          intent: WidgetDeferTaskIntent(taskID: row.id, title: row.title),
          systemName: "calendar.badge.clock",
          accessibilityLabel: String(
            localized: "widget.action.defer.a11y",
            defaultValue: "Defer \(row.title) until tomorrow",
            table: "Localizable",
            bundle: WidgetL10n.bundle)
        )
      }

      WidgetActionButton(
        intent: WidgetCompleteTaskIntent(taskID: row.id, title: row.title),
        systemName: "checkmark.circle.fill",
        accessibilityLabel: String(
          localized: "widget.action.complete.a11y",
          defaultValue: "Complete \(row.title)",
          table: "Localizable",
          bundle: WidgetL10n.bundle),
        tint: LorvexDesign.Palette.done
      )
    }
  }

  @ViewBuilder
  private var rowContent: some View {
    if let url = row.url {
      Link(destination: url) {
        TaskRowView(row: row)
      }
    } else {
      TaskRowView(row: row)
    }
  }
}

struct TaskRowView: View {
  let row: WidgetTaskRenderRow

  var body: some View {
    HStack(alignment: .top, spacing: 7) {
      // A colored priority dot replaces the old gray "Priority N" text: it color-
      // codes urgency at a glance (canonical `priorityTint`, matching every task
      // row) without spending a word of width. Width is reserved even when absent
      // so titles stay aligned.
      WidgetPriorityDot(color: row.priorityTintColor)
      VStack(alignment: .leading, spacing: 1) {
        // Absolute `Color.primary`/`.secondary`, not the hierarchical styles: the
        // enclosing `Link` sets the foreground to the accent, so the hierarchical
        // levels would resolve to shades of blue instead of label colors.
        Text(row.title)
          .font(.caption.weight(.medium))
          .foregroundStyle(Color.primary)
          .lineLimit(1)
          // The task title is the user's private content on a Home Screen /
          // StandBy surface; redact it when the device locks.
          .privacySensitive()
        if let metadata = row.metadata {
          Text(metadata)
            .font(.caption2)
            .foregroundStyle(Color.secondary)
            .lineLimit(1)
        }
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      [row.priorityLabel, row.title, row.metadata].compactMap { $0 }.joined(separator: ", "))
  }
}

extension WidgetTaskRenderRow {
  var url: URL? {
    guard let urlString else { return nil }
    return URL(string: urlString)
  }

  /// The row's priority color from the canonical `priorityTint` ramp (P1 red,
  /// P2 orange, P3 quiet), or nil when the row carries no priority. Shared by the
  /// system rows and the small widget's purpose-built layout.
  var priorityTintColor: Color? { lorvexWidgetPriorityDotTint(tier: priorityTier) }
}

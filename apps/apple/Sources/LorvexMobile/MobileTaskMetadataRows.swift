import LorvexCore
import SwiftUI

struct MobileChecklistItemRow: View {
  let item: TaskChecklistItem
  let toggleChecklistItem: ((TaskChecklistItem) async -> Void)?
  let removeChecklistItem: ((TaskChecklistItem) async -> Void)?

  var body: some View {
    Group {
      if let toggleChecklistItem {
        Button {
          Task { await toggleChecklistItem(item) }
        } label: {
          rowLabel
        }
      } else {
        rowLabel
      }
    }
    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
      if let removeChecklistItem {
        Button(role: .destructive) {
          Task { await removeChecklistItem(item) }
        } label: {
          Label(
            String(
              localized: "common.delete", defaultValue: "Delete", table: "Localizable",
              bundle: MobileL10n.bundle), systemImage: "trash")
        }
      }
    }
  }

  private var rowLabel: some View {
    Label {
      Text(item.text)
        .font(LorvexDesign.Typography.primaryText)
        .strikethrough(item.completedAt != nil)
        .foregroundStyle(item.completedAt == nil ? Color.primary : Color.secondary)
    } icon: {
      Image(systemName: item.completedAt == nil ? "circle" : "checkmark.circle.fill")
        .font(LorvexDesign.Typography.primaryText)
        .foregroundStyle(item.completedAt == nil ? Color.secondary : Color.green)
    }
    .padding(.vertical, LorvexDesign.Spacing.xs)
  }
}

struct MobileReminderRow: View {
  let reminder: TaskReminder
  let timeZone: TimeZone
  let removeReminder: ((TaskReminder) async -> Void)?

  var body: some View {
    Label {
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
        Text(reminder.displaySummary(timeZone: timeZone))
          .font(LorvexDesign.Typography.primaryText)
        if let status = reminder.status, !status.isEmpty {
          Text(MobileTaskDisplayText.reminderStatus(status))
            .font(LorvexDesign.Typography.secondaryText)
            .foregroundStyle(.secondary)
        }
      }
    } icon: {
      Image(systemName: "bell")
        .font(LorvexDesign.Typography.primaryText)
        .foregroundStyle(.orange)
    }
    .padding(.vertical, LorvexDesign.Spacing.xs)
    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
      if let removeReminder {
        Button(role: .destructive) {
          Task { await removeReminder(reminder) }
        } label: {
          Label(
            String(
              localized: "common.delete", defaultValue: "Delete", table: "Localizable",
              bundle: MobileL10n.bundle), systemImage: "trash")
        }
      }
    }
  }
}

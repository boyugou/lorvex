import LorvexCore
import SwiftUI

struct MobileHabitBatchActionBar: View {
  let selectedCount: Int
  let canComplete: Bool
  let canReset: Bool
  let canDelete: Bool
  let isMutating: Bool
  let complete: () -> Void
  let reset: () -> Void
  let delete: () -> Void
  let clear: () -> Void

  var body: some View {
    VStack(spacing: LorvexDesign.Spacing.s) {
      HStack {
        Text(
          String(
            format: String(localized: "habits.batch.selected_count", defaultValue: "%lld selected", table: "Localizable", bundle: MobileL10n.bundle),
            selectedCount)
        )
        .font(LorvexDesign.Typography.secondaryText)
        .foregroundStyle(.secondary)
        Spacer()
        Button(String(localized: "common.clear", defaultValue: "Clear", table: "Localizable", bundle: MobileL10n.bundle), action: clear)
          .disabled(selectedCount == 0 || isMutating)
      }

      HStack(spacing: LorvexDesign.Spacing.s) {
        Button(action: complete) {
          Label(
            String(localized: "habits.batch.complete", defaultValue: "Complete", table: "Localizable", bundle: MobileL10n.bundle),
            systemImage: "checkmark.circle"
          )
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!canComplete || isMutating)

        Button(action: reset) {
          Label(
            String(localized: "habits.batch.reset", defaultValue: "Reset", table: "Localizable", bundle: MobileL10n.bundle),
            systemImage: "arrow.counterclockwise"
          )
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(!canReset || isMutating)

        Button(role: .destructive, action: delete) {
          Label(
            String(localized: "habits.batch.delete", defaultValue: "Delete", table: "Localizable", bundle: MobileL10n.bundle),
            systemImage: "trash"
          )
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(!canDelete || isMutating)
      }
    }
    .padding(.horizontal, LorvexDesign.Spacing.m)
    .padding(.vertical, LorvexDesign.Spacing.s)
    .background(.regularMaterial)
    .overlay(alignment: .top) {
      Divider()
    }
    .accessibilityIdentifier("mobileHabits.batchActionBar")
  }
}

import LorvexCore
import SwiftUI

struct MobileMemoryDetailPanel: View {
  let entry: MemoryEntry
  let isSaving: Bool
  let edit: () -> Void
  let delete: () -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xl) {
        header
        content
        metadata
        actions
      }
      .frame(maxWidth: 760, alignment: .leading)
      .padding(LorvexDesign.Spacing.xl)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(.background)
    .accessibilityIdentifier("mobileMemory.detailPanel")
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
      Image(systemName: "sparkles")
        .font(LorvexDesign.Typography.screenTitle)
        .foregroundStyle(.tint)
        .frame(width: 56, height: 56)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityHidden(true)

      Text(entry.key)
        .font(LorvexDesign.Typography.sectionHeader)
        .textSelection(.enabled)
    }
  }

  private var content: some View {
    Text(entry.content)
      .font(LorvexDesign.Typography.primaryText)
      .textSelection(.enabled)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(LorvexDesign.Spacing.l)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
  }

  private var metadata: some View {
    metric(
      title: String(
        localized: "memory.detail.updated", defaultValue: "Updated", table: "Localizable",
        bundle: MobileL10n.bundle),
      value: entry.updatedAt,
      systemImage: "calendar")
  }

  private func metric(title: String, value: String, systemImage: String) -> some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
      Label(title, systemImage: systemImage)
        .font(LorvexDesign.Typography.secondaryText)
        .foregroundStyle(.secondary)
      Text(value)
        .font(LorvexDesign.Typography.primaryEmphasis)
        .monospacedDigit()
        .lineLimit(2)
        .minimumScaleFactor(0.8)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(LorvexDesign.Spacing.l)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
  }

  private var actions: some View {
    HStack(spacing: LorvexDesign.Spacing.m) {
      Button {
        edit()
      } label: {
        Label(
          String(
            localized: "common.edit", defaultValue: "Edit", table: "Localizable",
            bundle: MobileL10n.bundle), systemImage: "pencil")
      }
      .buttonStyle(.borderedProminent)
      .disabled(isSaving)
      .accessibilityIdentifier("mobileMemory.detail.edit")

      Button(role: .destructive) {
        delete()
      } label: {
        Label(
          String(
            localized: "common.delete", defaultValue: "Delete", table: "Localizable",
            bundle: MobileL10n.bundle), systemImage: "trash")
      }
      .buttonStyle(.bordered)
      .disabled(isSaving)
      .accessibilityIdentifier("mobileMemory.detail.delete")
    }
  }
}

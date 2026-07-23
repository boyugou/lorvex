import AppKit
import LorvexCore
import SwiftUI

/// One memory entry as a native macOS list row: an AI glyph, the key, the
/// remembered content, and a last-updated footer. Edit and Delete appear on hover
/// and in the row's context menu, and the whole row taps to edit. Memory is
/// AI-managed context the assistant keeps about the user; the app edits it as the
/// AI actor.
struct MemoryEntryRow: View {
  let entry: MemoryEntry
  let edit: () -> Void
  let delete: () -> Void

  @State private var isHovering = false

  var body: some View {
    HStack(alignment: .top, spacing: LorvexDesign.Spacing.m) {
      icon
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
        headerLine
        Text(entry.content)
          .font(LorvexDesign.Typography.secondaryText)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .textSelection(.enabled)
        footerLine
      }
    }
    .padding(.vertical, LorvexDesign.Spacing.xs)
    .contentShape(Rectangle())
    .onTapGesture(perform: edit)
    .onHover { hovering in
      lorvexAnimated(.easeOut(duration: 0.12)) { isHovering = hovering }
      if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
    }
    .help(String(localized: "memory.edit", defaultValue: "Edit", table: "Localizable", bundle: LorvexL10n.bundle))
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityIdentifier("memory.row.\(entry.key)")
    .accessibilityAction(
      named: Text(String(localized: "memory.edit", defaultValue: "Edit", table: "Localizable", bundle: LorvexL10n.bundle)),
      edit)
    .contextMenu { contextMenu }
  }

  private var icon: some View {
    Image(systemName: "sparkles")
      .symbolRenderingMode(.hierarchical)
      .font(.system(size: 15))
      .foregroundStyle(.tint)
      .frame(width: 20)
      .padding(.top, 1)
      .accessibilityHidden(true)
  }

  private var headerLine: some View {
    HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.s) {
      Text(entry.key)
        .font(LorvexDesign.Typography.primaryEmphasis)
        .lineLimit(1)
      Spacer(minLength: LorvexDesign.Spacing.s)
    }
  }

  private var footerLine: some View {
    HStack(spacing: LorvexDesign.Spacing.m) {
      Text(Self.formattedDay(entry.updatedAt))
        .font(LorvexDesign.Typography.tertiaryText)
        .foregroundStyle(.tertiary)

      Spacer(minLength: 0)

      // Edit / Delete reveal on hover; every action is also in the context menu.
      if isHovering {
        hoverActions
          .transition(.opacity)
      }
    }
  }

  private var hoverActions: some View {
    HStack(spacing: LorvexDesign.Spacing.xs) {
      Button(action: edit) {
        Image(systemName: "pencil").frame(width: 16, height: 16)
      }
      .buttonStyle(.borderless)
      .help(String(localized: "memory.edit", defaultValue: "Edit", table: "Localizable", bundle: LorvexL10n.bundle))
      .accessibilityLabel(String(localized: "memory.edit", defaultValue: "Edit", table: "Localizable", bundle: LorvexL10n.bundle))
      .accessibilityIdentifier("memory.row.edit.\(entry.key)")

      Button(role: .destructive, action: delete) {
        Image(systemName: "trash").frame(width: 16, height: 16)
      }
      .buttonStyle(.borderless)
      .help(String(localized: "common.delete", defaultValue: "Delete", table: "Localizable", bundle: LorvexL10n.bundle))
      .accessibilityLabel(String(localized: "common.delete", defaultValue: "Delete", table: "Localizable", bundle: LorvexL10n.bundle))
      .accessibilityIdentifier("memory.row.delete.\(entry.key)")
    }
  }

  @ViewBuilder
  private var contextMenu: some View {
    Button(
      String(localized: "memory.edit", defaultValue: "Edit", table: "Localizable", bundle: LorvexL10n.bundle),
      systemImage: "pencil",
      action: edit)
    Divider()
    Button(
      String(localized: "common.delete", defaultValue: "Delete", table: "Localizable", bundle: LorvexL10n.bundle),
      systemImage: "trash",
      role: .destructive,
      action: delete)
  }

  private var accessibilityLabel: String {
    "\(entry.key). \(entry.content)"
  }

  /// A readable absolute day (e.g. "May 22, 2026") for the row footer, falling
  /// back to the raw string if it can't be parsed.
  private static func formattedDay(_ timestamp: String) -> String {
    guard let date = LorvexDateFormatters.iso8601.date(from: timestamp) else {
      return timestamp
    }
    return date.formatted(date: .abbreviated, time: .omitted)
  }
}

import LorvexCore
import SwiftUI

private enum ListCatalogRowMetrics {
  static let iconSize: CGFloat = 24
  static let iconFontSize: CGFloat = 15
  static let cornerRadius: CGFloat = 7
  static let horizontalPadding: CGFloat = LorvexDesign.Spacing.m
  static let verticalPadding: CGFloat = 9
  static let progressMaxWidth: CGFloat = 76
}

struct ListCatalogRow: View {
  let list: LorvexList
  let select: () -> Void
  let edit: () -> Void
  let delete: () -> Void
  let archive: () -> Void
  let canMoveUp: Bool
  let canMoveDown: Bool
  let moveUp: () -> Void
  let moveDown: () -> Void
  @State private var isShowingDeleteConfirmation = false
  @State private var isShowingActions = false
  @Environment(\.openWindow) private var openWindow

  private var tint: Color {
    Color(lorvexHex: list.color) ?? .accentColor
  }

  var body: some View {
    rowContent
    .contentShape(Rectangle())
    .onTapGesture(perform: select)
    // Full Keyboard Access: a keyboard-only user tabbing through the catalog
    // needs a focus ring and a way to trigger the row's primary open action,
    // matching the pattern already used on task rows and habit cards
    // (`WorkspaceSelectableTaskRow`, `HabitMomentumCard`).
    .focusable()
    .onKeyPress(.return) { select(); return .handled }
    .onKeyPress(.space) { select(); return .handled }
    .padding(.horizontal, ListCatalogRowMetrics.horizontalPadding)
    .padding(.vertical, ListCatalogRowMetrics.verticalPadding)
    .background {
      RoundedRectangle(cornerRadius: ListCatalogRowMetrics.cornerRadius, style: .continuous)
        .fill(rowBackground)
    }
    .overlay(alignment: .trailing) {
      if isShowingActions {
        actions
          .padding(.trailing, LorvexDesign.Spacing.s)
          .transition(.opacity)
      }
    }
    .reduceMotionAnimation(.easeInOut(duration: 0.12), value: isShowingActions)
    .onHover { isShowingActions = $0 }
    .help(String(localized: "list_row.open_scope.help", defaultValue: "Open Tasks in This List", table: "Localizable", bundle: LorvexL10n.bundle))
    .accessibilityElement(children: .combine)
    .accessibilityLabel(listAccessibilityLabel(
      list,
      format: String(
        localized: "a11y.list.format", defaultValue: "%1$@: %2$lld open tasks, %3$lld total",
        table: "Localizable",
        bundle: LorvexL10n.bundle)))
    // The row opens its Tasks scope on tap / Return / Space, but a raw
    // `.onTapGesture` is invisible to VoiceOver. Announce it as a button and
    // expose the same open affordance as the default accessibility action so VO
    // users can activate it, mirroring `HabitMomentumCard`.
    .accessibilityAddTraits(.isButton)
    .accessibilityAction { select() }
    .accessibilityIdentifier("list.row.\(list.id)")
    .contextMenu {
      Button(String(localized: "list_row.move_up", defaultValue: "Move Up", table: "Localizable", bundle: LorvexL10n.bundle), systemImage: "chevron.up") {
        moveUp()
      }
      .disabled(!canMoveUp)

      Button(String(localized: "list_row.move_down", defaultValue: "Move Down", table: "Localizable", bundle: LorvexL10n.bundle), systemImage: "chevron.down") {
        moveDown()
      }
      .disabled(!canMoveDown)

      Divider()

      Button(String(localized: "list_row.edit.action", defaultValue: "Edit", table: "Localizable", bundle: LorvexL10n.bundle), systemImage: "pencil", action: edit)
      Button(String(localized: "list_row.open_new_window", defaultValue: "Open in New Window", table: "Localizable", bundle: LorvexL10n.bundle), systemImage: "macwindow.on.rectangle") {
        openWindow(value: list.id)
      }
      Divider()
      Button(String(localized: "list_row.archive.action", defaultValue: "Archive List", table: "Localizable", bundle: LorvexL10n.bundle), systemImage: "archivebox", action: archive)
      Button(String(localized: "list_row.delete.action", defaultValue: "Delete", table: "Localizable", bundle: LorvexL10n.bundle), systemImage: "trash", role: .destructive) {
        isShowingDeleteConfirmation = true
      }
    }
    .confirmationDialog(
      deleteDialogTitle,
      isPresented: $isShowingDeleteConfirmation,
      titleVisibility: .visible
    ) {
      // Empty lists delete outright; a list still holding tasks can't be
      // deleted (delete hard-blocks), so the forward action is to archive it.
      if list.totalCount == 0 {
        Button(String(localized: "list_row.delete.confirm", defaultValue: "Delete List", table: "Localizable", bundle: LorvexL10n.bundle), role: .destructive, action: delete)
        Button(String(localized: "list_row.delete.keep", defaultValue: "Keep", table: "Localizable", bundle: LorvexL10n.bundle), role: .cancel) {}
      } else {
        Button(String(localized: "list_row.archive.confirm", defaultValue: "Archive List", table: "Localizable", bundle: LorvexL10n.bundle), action: archive)
        Button(String(localized: "list_row.delete.keep", defaultValue: "Keep", table: "Localizable", bundle: LorvexL10n.bundle), role: .cancel) {}
      }
    } message: {
      Text(deleteDialogMessage)
    }
  }

  private var rowContent: some View {
    HStack(alignment: .center, spacing: LorvexDesign.Spacing.m) {
      LorvexListIconView(
        icon: list.icon,
        tint: tint,
        size: ListCatalogRowMetrics.iconSize,
        font: .system(size: ListCatalogRowMetrics.iconFontSize, weight: .medium),
        background: .roundedSquare(
          size: ListCatalogRowMetrics.iconSize,
          opacity: 0.07,
          cornerRadius: 6
        )
      )

      VStack(alignment: .leading, spacing: 4) {
        Text(list.name)
          .font(LorvexDesign.Typography.primaryEmphasis)
          .foregroundStyle(.primary)
          .lineLimit(1)

        listProgress
      }

      Spacer(minLength: LorvexDesign.Spacing.m)
    }
  }

  private var rowBackground: AnyShapeStyle {
    if isShowingActions {
      return AnyShapeStyle(.quaternary.opacity(0.22))
    }
    return AnyShapeStyle(Color.clear)
  }

  @ViewBuilder
  private var listProgress: some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      Text(countSummaryText)
        .font(LorvexDesign.Typography.tertiaryText)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)

      if let fraction = list.progressFraction {
        LorvexProgressBar(value: fraction, tint: tint)
          .frame(maxWidth: ListCatalogRowMetrics.progressMaxWidth)
          .accessibilityHidden(true)
      }
    }
  }

  private var actions: some View {
    HStack(spacing: LorvexDesign.Spacing.xs) {
      Button(action: edit) {
        Image(systemName: "pencil")
          .frame(width: 18, height: 18)
      }
      .buttonStyle(.borderless)
      .help(String(localized: "list_row.edit.help", defaultValue: "Edit list", table: "Localizable", bundle: LorvexL10n.bundle))
      .accessibilityLabel(
        String(
          format: String(localized: "list_row.edit.a11y", defaultValue: "Edit %@", table: "Localizable", bundle: LorvexL10n.bundle),
          list.name
        ))
      .accessibilityIdentifier("list.action.edit")

      Button(role: .destructive) {
        isShowingDeleteConfirmation = true
      } label: {
        Image(systemName: "trash")
          .frame(width: 18, height: 18)
      }
      .buttonStyle(.borderless)
      .help(String(localized: "list_row.delete.help", defaultValue: "Delete list", table: "Localizable", bundle: LorvexL10n.bundle))
      .accessibilityLabel(
        String(
          format: String(localized: "list_row.delete.a11y", defaultValue: "Delete %@", table: "Localizable", bundle: LorvexL10n.bundle),
          list.name
        ))
      .accessibilityIdentifier("list.action.delete")
    }
  }

  private var countSummaryText: String {
    String(
      format: String(localized: "list_row.counts", defaultValue: "%lld open · %lld total", table: "Localizable", bundle: LorvexL10n.bundle),
      list.openCount,
      list.totalCount
    )
  }

  private var deleteDialogTitle: String {
    if list.totalCount == 0 {
      return String(
        format: String(localized: "list_row.delete.title", defaultValue: "Delete list “%@”?", table: "Localizable", bundle: LorvexL10n.bundle),
        list.name
      )
    }
    return String(
      format: String(localized: "list_row.archive.title", defaultValue: "Archive list “%@”?", table: "Localizable", bundle: LorvexL10n.bundle),
      list.name
    )
  }

  private var deleteDialogMessage: String {
    if list.totalCount == 0 {
      return String(
        localized: "list_row.delete.empty_message",
        defaultValue: "The list is empty and will be removed.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      )
    }
    return String(
      localized: "list_row.archive.nonempty_count_message",
      defaultValue: "\(list.totalCount) tasks remain in \"\(list.name)\". Archive the list to retire it while keeping its tasks and history; you can unarchive it later.",
      table: "Localizable",
      bundle: LorvexL10n.bundle)
  }
}

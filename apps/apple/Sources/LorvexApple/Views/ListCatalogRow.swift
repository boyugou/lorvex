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

/// One list in the Lists catalog as a card: its icon, name, counts, and
/// progress, then its first open tasks in the canonical order with a count of
/// the rest, so the catalog shows what each list holds next. Clicking the card
/// opens the list's Tasks scope; clicking a previewed task opens that task
/// there. Edit and Delete appear on hover at the card's top edge. The Inbox is
/// the list every task falls back to, so its card offers Edit only: no Delete,
/// no Archive.
struct ListCatalogRow: View {
  let list: LorvexList
  /// The list's first open tasks; empty shows the counts alone.
  var previewTasks: [LorvexTask] = []
  var openTask: (LorvexTask.ID) -> Void = { _ in }
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
          // Level with the header line, not the middle of a tall card.
          .padding(.top, ListCatalogRowMetrics.verticalPadding)
          .frame(maxHeight: .infinity, alignment: .top)
          .transition(.opacity)
      }
    }
    .reduceMotionAnimation(.easeInOut(duration: 0.12), value: isShowingActions)
    .onHover { isShowingActions = $0 }
    .help(String(localized: "list_row.open_scope.help", defaultValue: "Open Tasks in This List", table: "Localizable", bundle: LorvexL10n.bundle))
    .accessibilityElement(children: .contain)
    .accessibilityLabel(list.spokenSummary)
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
      if !list.isInbox {
        Divider()
        Button(String(localized: "list_row.archive.action", defaultValue: "Archive List", table: "Localizable", bundle: LorvexL10n.bundle), systemImage: "archivebox", action: archive)
        Button(String(localized: "list_row.delete.action", defaultValue: "Delete", table: "Localizable", bundle: LorvexL10n.bundle), systemImage: "trash", role: .destructive) {
          isShowingDeleteConfirmation = true
        }
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
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
      header
      if !previewTasks.isEmpty {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(previewTasks) { task in
            ListCatalogPreviewTaskRow(task: task) { openTask(task.id) }
          }
          if list.openCount > previewTasks.count {
            Text(moreText(list.openCount - previewTasks.count))
              .font(LorvexDesign.Typography.tertiaryText)
              .foregroundStyle(.secondary)
              .padding(.vertical, LorvexDesign.Spacing.xxs)
          }
        }
        // Under the name, past the icon column.
        .padding(.leading, ListCatalogRowMetrics.iconSize + LorvexDesign.Spacing.m)
      }
    }
  }

  private func moreText(_ count: Int) -> String {
    String(localized: "list_row.more_open", defaultValue: "\(count) more open", table: "Localizable", bundle: LorvexL10n.bundle)
  }

  private var header: some View {
    HStack(alignment: .center, spacing: LorvexDesign.Spacing.m) {
      LorvexListIconView(
        icon: list.icon,
        tint: tint,
        size: ListCatalogRowMetrics.iconSize,
        font: .system(size: ListCatalogRowMetrics.iconFontSize, weight: .medium),
        background: .roundedSquare(
          size: ListCatalogRowMetrics.iconSize,
          opacity: 0.07,
          cornerRadius: LorvexDesign.Radius.s
        )
      )

      VStack(alignment: .leading, spacing: 4) {
        Text(list.displayName)
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
      return AnyShapeStyle(LorvexDesign.Palette.hoverFill)
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

      // Only once something is done. An empty bar restates "N open · N total"
      // in a vaguer form and, being a flat tinted capsule, reads as a loading
      // placeholder; the bar earns its place when it shows a proportion the
      // count line cannot show at a glance.
      if let fraction = list.progressFraction, fraction > 0 {
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
          list.displayName
        ))
      .accessibilityIdentifier("list.action.edit")

      if !list.isInbox {
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
            list.displayName
          ))
        .accessibilityIdentifier("list.action.delete")
      }
    }
  }

  /// The line under the name: the open and total counts, or "No tasks" for a
  /// list that holds no task at all.
  private var countSummaryText: String {
    guard list.totalCount > 0 else {
      return String(localized: "list_row.no_tasks", defaultValue: "No tasks", table: "Localizable", bundle: LorvexL10n.bundle)
    }
    return String(
      localized: "list_row.counts",
      defaultValue: "\(list.openCount) open · \(list.totalCount) total",
      table: "Localizable", bundle: LorvexL10n.bundle)
  }

  private var deleteDialogTitle: String {
    if list.totalCount == 0 {
      return String(
        format: String(localized: "list_row.delete.title", defaultValue: "Delete list “%@”?", table: "Localizable", bundle: LorvexL10n.bundle),
        list.displayName
      )
    }
    return String(
      format: String(localized: "list_row.archive.title", defaultValue: "Archive list “%@”?", table: "Localizable", bundle: LorvexL10n.bundle),
      list.displayName
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
      defaultValue: "“\(list.displayName)” can’t be deleted while it still holds \(list.totalCount) tasks. Archive it instead to retire it while keeping its tasks and history. You can unarchive it later.",
      table: "Localizable",
      bundle: LorvexL10n.bundle)
  }
}

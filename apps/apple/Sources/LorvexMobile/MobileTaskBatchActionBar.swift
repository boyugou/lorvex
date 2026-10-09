import LorvexCore
import SwiftUI

/// A single, light contextual action row (Photos-style) shown while batch
/// selecting. Each action is an equal-width icon-over-label control that tints
/// when enabled and dims when not; the selection count lives in the nav title.
/// At accessibility text sizes the four actions take two rows of two, so a
/// translated label keeps its word on one line instead of breaking mid-word.
///
/// Complete, Defer, and Reopen act on the tasks of the selection they fit. List
/// opens a menu of the lists the selection can be filed into.
struct MobileTaskBatchActionBar: View {
  let canCompleteOrDefer: Bool
  let canReopen: Bool
  /// Whether the selection holds any task; filing needs nothing more.
  let canMove: Bool
  /// The lists the List menu offers.
  let moveTargets: [LorvexList]
  let isMutating: Bool
  let complete: () -> Void
  let deferTask: () -> Void
  let reopen: () -> Void
  let move: (LorvexList.ID) -> Void

  /// The widest the actions spread. The bar's background spans the screen, but
  /// on an iPad the actions stay within reach of one another instead of
  /// sitting a quarter of the width apart.
  private static let maxActionsWidth: CGFloat = 560

  /// The height every icon is centered in, so the labels beneath share one
  /// baseline whatever each symbol's own height is.
  @ScaledMetric(relativeTo: .title3) private var iconHeight: CGFloat = 22
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
          GridRow(alignment: .top) {
            completeAction
            deferAction
          }
          GridRow(alignment: .top) {
            reopenAction
            listMenu
          }
        }
      } else {
        HStack(alignment: .top, spacing: 0) {
          completeAction
          deferAction
          reopenAction
          listMenu
        }
      }
    }
    .frame(maxWidth: Self.maxActionsWidth)
    .frame(maxWidth: .infinity)
    .padding(.top, LorvexDesign.Spacing.xs)
    .background(.bar)
    .overlay(alignment: .top) { Divider() }
    .accessibilityIdentifier("mobileTasks.batchActionBar")
  }

  private var completeAction: some View {
    action(
      label: LocalizedStringResource(
        "action.complete", defaultValue: "Complete",
        table: "Localizable", bundle: MobileL10n.bundle),
      identifier: "complete",
      systemImage: "checkmark.circle.fill", tint: LorvexDesign.Palette.done,
      enabled: canCompleteOrDefer, action: complete)
  }

  private var deferAction: some View {
    action(
      label: LocalizedStringResource(
        "action.defer", defaultValue: "Defer",
        table: "Localizable", bundle: MobileL10n.bundle),
      identifier: "defer",
      systemImage: "clock", tint: LorvexDesign.Palette.dueSoon,
      enabled: canCompleteOrDefer, action: deferTask)
  }

  private var reopenAction: some View {
    action(
      label: LocalizedStringResource(
        "action.reopen", defaultValue: "Reopen",
        table: "Localizable", bundle: MobileL10n.bundle),
      identifier: "reopen",
      systemImage: "arrow.uturn.backward", tint: .accentColor,
      enabled: canReopen, action: reopen)
  }

  private var listMenu: some View {
    let enabled = canMove && !moveTargets.isEmpty && !isMutating
    return Menu {
      ForEach(moveTargets) { list in
        Button {
          move(list.id)
        } label: {
          MobileListMenuLabel(list: list)
        }
      }
    } label: {
      actionLabel(
        LocalizedStringResource(
          "task_detail.picker.list", defaultValue: "List",
          table: "Localizable", bundle: MobileL10n.bundle),
        systemImage: "folder"
      )
      .foregroundStyle(enabled ? Color.accentColor : Color.secondary)
    }
    .disabled(!enabled)
    .accessibilityIdentifier("mobileTasks.batch.list")
  }

  private func action(
    label: LocalizedStringResource,
    identifier: String,
    systemImage: String,
    tint: Color,
    enabled: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      actionLabel(label, systemImage: systemImage)
    }
    .buttonStyle(.plain)
    .foregroundStyle(enabled && !isMutating ? tint : Color.secondary)
    .disabled(!enabled || isMutating)
    .accessibilityIdentifier("mobileTasks.batch.\(identifier)")
  }

  private func actionLabel(_ label: LocalizedStringResource, systemImage: String) -> some View {
    VStack(spacing: 3) {
      Image(systemName: systemImage)
        .font(.title3)
        .frame(height: iconHeight)
      Text(label)
        .font(.caption2)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, LorvexDesign.Spacing.xs)
    .contentShape(Rectangle())
  }
}

/// A list as a menu item: its symbol beside its name, or its emoji before the
/// name, since a menu item draws only an image as its icon.
private struct MobileListMenuLabel: View {
  let list: LorvexList

  var body: some View {
    if let emoji = list.icon, !emoji.isEmpty, !emoji.unicodeScalars.allSatisfy(\.isASCII) {
      Text(userContent: "\(emoji) \(list.displayName)")
    } else {
      Label {
        Text(userContent: list.displayName)
      } icon: {
        Image(systemName: LorvexSymbol.name(for: list.icon, fallback: "tray.fill"))
      }
    }
  }
}

import LorvexCore
import SwiftUI

/// The secondary actions under a task's detail, as one row of equal tiles in
/// the style of a contact card's actions: an icon over a short name. The
/// status transition itself (Complete / Reopen / Move to Open) is the
/// detail's prominent action (in the toolbar of a screen, in the header row of
/// a split's pane), so the tiles carry the rest: start or pause, defer (a menu
/// of days), someday, and cancel in the destructive tint. A parked (someday)
/// task's toolbar action is Move to Open, so it gets a Complete tile to finish
/// in one tap. Only actions the task's status allows are shown, and a task
/// that allows none (completed or cancelled) shows no tiles. At the
/// accessibility text sizes the tiles wrap two to a row.
struct MobileTaskActionSection: View {
  let task: LorvexTask
  let isMutating: Bool
  let actions: MobileTaskRowActions
  let markSomeday: () async -> Void
  let cancel: () async -> Void

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  enum Tile: Hashable {
    case start, pause, complete, deferTask, someday, cancel
  }

  /// The tiles `status` allows, in order.
  static func tiles(for status: LorvexTask.Status) -> [Tile] {
    switch status {
    case .open: [.start, .deferTask, .someday, .cancel]
    case .inProgress: [.pause, .deferTask, .cancel]
    case .someday: [.complete, .deferTask, .cancel]
    case .completed, .cancelled: []
    }
  }

  var body: some View {
    let tiles = Self.tiles(for: task.status)
    if !tiles.isEmpty {
      Section {
        LazyVGrid(
          columns: Array(
            repeating: GridItem(.flexible(), spacing: LorvexDesign.Spacing.s),
            count: dynamicTypeSize.isAccessibilitySize ? 2 : tiles.count),
          spacing: LorvexDesign.Spacing.s
        ) {
          ForEach(tiles, id: \.self) { tile in
            view(for: tile)
          }
        }
        .disabled(isMutating)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
      }
    }
  }

  @ViewBuilder
  private func view(for tile: Tile) -> some View {
    switch tile {
    case .start:
      button(MobileTaskActionCopy.start, "play.fill", id: "task.detail.start") {
        await actions.start()
      }
    case .pause:
      button(MobileTaskActionCopy.pause, "pause.fill", id: "task.detail.pause") {
        await actions.pause()
      }
    case .complete:
      button(MobileTaskActionCopy.complete, "checkmark", id: "task.detail.completeParked") {
        await actions.complete()
      }
    case .deferTask:
      MobileDeferMenu(deferByDays: actions.deferByDays) {
        MobileTaskActionTile(title: MobileTaskActionCopy.deferTask, systemImage: "clock.arrow.circlepath")
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("task.detail.defer")
    case .someday:
      button(
        String(
          localized: "task_detail.tile.someday", defaultValue: "Someday", table: "Localizable",
          bundle: MobileL10n.bundle),
        "moon", id: "task.detail.moveToSomeday"
      ) { await markSomeday() }
    case .cancel:
      button(
        String(
          localized: "action.cancel_task", defaultValue: "Cancel", table: "Localizable",
          bundle: MobileL10n.bundle),
        "xmark", id: "task.detail.cancel", tint: LorvexDesign.Palette.destructive
      ) { await cancel() }
    }
  }

  private func button(
    _ title: String, _ systemImage: String, id: String,
    tint: Color = LorvexDesign.Palette.accent, action: @escaping () async -> Void
  ) -> some View {
    Button {
      Task { await action() }
    } label: {
      MobileTaskActionTile(title: title, systemImage: systemImage, tint: tint)
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier(id)
  }
}

/// One action tile: the symbol over its name in the tile's tint, on the card
/// surface, the full width of its grid cell.
struct MobileTaskActionTile: View {
  let title: String
  let systemImage: String
  var tint: Color = LorvexDesign.Palette.accent

  @Environment(\.isEnabled) private var isEnabled

  var body: some View {
    VStack(spacing: LorvexDesign.Spacing.xs) {
      Image(systemName: systemImage)
        .font(LorvexDesign.Typography.primaryText.weight(.semibold))
        .frame(height: 22)
      Text(title)
        .font(LorvexDesign.Typography.tertiaryText.weight(.medium))
        .lineLimit(2)
        .multilineTextAlignment(.center)
    }
    .foregroundStyle(tint)
    .frame(maxWidth: .infinity, minHeight: 64)
    .padding(.horizontal, LorvexDesign.Spacing.xs)
    .padding(.vertical, LorvexDesign.Spacing.s)
    .background(LorvexDesign.Palette.card, in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.m, style: .continuous))
    .opacity(isEnabled ? 1 : 0.45)
    .contentShape(RoundedRectangle(cornerRadius: LorvexDesign.Radius.m, style: .continuous))
  }
}

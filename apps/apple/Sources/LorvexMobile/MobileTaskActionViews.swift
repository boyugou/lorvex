import LorvexCore
import SwiftUI
#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// The secondary actions under a task's detail, as one row of equal tiles in
/// the style of a contact card's actions: an icon over a short name. The
/// status transition itself (Complete / Reopen / Move to Open) is the
/// detail's prominent action (in the toolbar of a screen, in the header row of
/// a split's pane), so the tiles carry the rest: start or pause, defer (a menu
/// of days), someday, and cancel in the destructive tint. A parked (someday)
/// task's toolbar action is Move to Open, so it gets a Complete tile to finish
/// in one tap. Only actions the task's status allows are shown, and a task
/// that allows none (completed or cancelled) shows no tiles. At the
/// accessibility text sizes the tiles wrap two to a row. The tiles' names
/// share one size, fitted to the row by ``MobileTaskActionLabelFit``, and when
/// any name wraps onto a second line every tile keeps room for one, so the
/// symbols stay on one line across the row.
///
/// While a task the task waits on is unfinished (`isHeldUp`), Start stays in
/// its place but is unavailable, and the section's footer says why: the core
/// would refuse the start, so the tile does not offer it.
struct MobileTaskActionSection: View {
  let task: LorvexTask
  let isMutating: Bool
  var isHeldUp = false
  let actions: MobileTaskRowActions
  let markSomeday: () async -> Void
  let cancel: () async -> Void

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  /// The row's width, measured, which the tiles' names are fitted to.
  @State private var rowWidth: CGFloat = 0
  /// The tiles' name size at the default text size (the footnote style's),
  /// scaled with the text.
  @ScaledMetric(relativeTo: .footnote) private var labelBaseSize: CGFloat = 13

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
      let columns = dynamicTypeSize.isAccessibilitySize ? 2 : tiles.count
      let titles = tiles.map(title(for:))
      let textWidth = MobileTaskActionLabelFit.textWidth(rowWidth: rowWidth, columns: columns)
      let size =
        labelBaseSize
        * MobileTaskActionLabelFit.scale(titles: titles, size: labelBaseSize, width: textWidth)
      let label = MobileTaskActionLabelStyle(
        size: size,
        reservesSecondLine: MobileTaskActionLabelFit.wraps(
          titles: titles, size: size, width: textWidth))
      Section {
        LazyVGrid(
          columns: Array(
            repeating: GridItem(.flexible(), spacing: LorvexDesign.Spacing.s), count: columns),
          spacing: LorvexDesign.Spacing.s
        ) {
          ForEach(tiles, id: \.self) { tile in
            view(for: tile, label: label)
          }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
        .disabled(isMutating)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
      } footer: {
        if isStartHeldUp(tiles) {
          Text(Self.heldUpReason)
            .accessibilityIdentifier("task.detail.start.heldUpReason")
        }
      }
    }
  }

  /// Why Start is unavailable, in the wording the app shows when the core
  /// refuses such a start.
  private static var heldUpReason: String {
    UserFacingError.Reason.taskStartBlocked.localizedMessage
  }

  private func isStartHeldUp(_ tiles: [Tile]) -> Bool {
    isHeldUp && tiles.contains(.start)
  }

  /// The name `tile` shows.
  private func title(for tile: Tile) -> String {
    switch tile {
    case .start: MobileTaskActionCopy.start
    case .pause: MobileTaskActionCopy.pause
    case .complete: MobileTaskActionCopy.complete
    case .deferTask: MobileTaskActionCopy.deferTask
    case .someday:
      String(
        localized: "task_detail.tile.someday", defaultValue: "Someday", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .cancel:
      String(
        localized: "action.cancel_task", defaultValue: "Cancel", table: "Localizable",
        bundle: MobileL10n.bundle)
    }
  }

  @ViewBuilder
  private func view(for tile: Tile, label: MobileTaskActionLabelStyle) -> some View {
    switch tile {
    case .start:
      button(tile, "play.fill", id: "task.detail.start", label: label) {
        await actions.start()
      }
      .disabled(isHeldUp)
      .accessibilityHint(isHeldUp ? Self.heldUpReason : "")
    case .pause:
      button(tile, "pause.fill", id: "task.detail.pause", label: label) {
        await actions.pause()
      }
    case .complete:
      button(tile, "checkmark", id: "task.detail.completeParked", label: label) {
        await actions.complete()
      }
    case .deferTask:
      MobileDeferMenu(deferByDays: actions.deferByDays) {
        MobileTaskActionTile(
          title: title(for: tile), systemImage: "clock.arrow.circlepath", label: label)
      }
      .menuStyle(.button)
      .buttonStyle(LorvexTileButtonStyle())
      .accessibilityIdentifier("task.detail.defer")
    case .someday:
      button(tile, "moon", id: "task.detail.moveToSomeday", label: label) {
        await markSomeday()
      }
    case .cancel:
      button(
        tile, "xmark", id: "task.detail.cancel", label: label,
        tint: LorvexDesign.Palette.destructive
      ) { await cancel() }
    }
  }

  private func button(
    _ tile: Tile, _ systemImage: String, id: String, label: MobileTaskActionLabelStyle,
    tint: Color = LorvexDesign.Palette.accent, action: @escaping () async -> Void
  ) -> some View {
    Button {
      Task { await action() }
    } label: {
      MobileTaskActionTile(
        title: title(for: tile), systemImage: systemImage, label: label, tint: tint)
    }
    .buttonStyle(LorvexTileButtonStyle())
    .accessibilityIdentifier(id)
  }
}

/// The one size the action tiles' names share: the text's own size while
/// every word of every name fits a tile's width on one line, otherwise the
/// size at which the widest word fits, down to ``minimumScale``. A name of
/// one word ("Когда-нибудь") then stays whole on one line at the row's size,
/// rather than shrinking alone beside names drawn larger, and a name of
/// several words wraps between them.
enum MobileTaskActionLabelFit {
  /// The smallest scale the row's names take. A word still too wide at this
  /// size shrinks further on its own tile, through the tile's own minimum
  /// scale, rather than breaking.
  static let minimumScale: CGFloat = 0.7

  /// Points of a tile's text width the measurement leaves to the text
  /// layout's own line padding and rounding, so a word measured to fit does
  /// fit.
  static let layoutAllowance: CGFloat = 2

  /// The width a name has in one of `columns` equal tiles across a row
  /// `rowWidth` wide: the tile's share of the row, less the grid spacing and
  /// the tile's horizontal padding. An unmeasured (zero) row gives zero.
  static func textWidth(rowWidth: CGFloat, columns: Int) -> CGFloat {
    guard rowWidth > 0, columns > 0 else { return 0 }
    let spacing = LorvexDesign.Spacing.s * CGFloat(columns - 1)
    return (rowWidth - spacing) / CGFloat(columns) - 2 * LorvexDesign.Spacing.xs
  }

  /// 1 while the widest word of `titles` fits `width` at `size`, otherwise
  /// the scale that makes it fit, no smaller than ``minimumScale``. A zero
  /// width (not yet measured) keeps the full size.
  static func scale(titles: [String], size: CGFloat, width: CGFloat) -> CGFloat {
    guard width > 0 else { return 1 }
    let room = width - layoutAllowance
    let widest =
      titles
      .flatMap { $0.split(whereSeparator: \.isWhitespace) }
      .map { extent(of: String($0), size: size) }
      .max() ?? 0
    guard widest > room else { return 1 }
    return max(minimumScale, room / widest)
  }

  /// Whether a name takes a second line: some name of several words is wider
  /// than `width` at `size`. A name of one word never wraps (it stays whole
  /// and shrinks), and an unmeasured (zero) width reports false.
  static func wraps(titles: [String], size: CGFloat, width: CGFloat) -> Bool {
    guard width > 0 else { return false }
    let room = width - layoutAllowance
    return titles.contains { title in
      title.contains(where: \.isWhitespace) && extent(of: title, size: size) > room
    }
  }

  /// The height `lines` lines of a name take at `size`.
  static func height(lines: Int, size: CGFloat) -> CGFloat {
    #if canImport(UIKit)
      let lineHeight = UIFont.systemFont(ofSize: size, weight: .medium).lineHeight
    #else
      let font = NSFont.systemFont(ofSize: size, weight: .medium)
      let lineHeight = font.ascender - font.descender + font.leading
    #endif
    return ceil(lineHeight) * CGFloat(lines)
  }

  private static func extent(of text: String, size: CGFloat) -> CGFloat {
    #if canImport(UIKit)
      let font = UIFont.systemFont(ofSize: size, weight: .medium)
    #else
      let font = NSFont.systemFont(ofSize: size, weight: .medium)
    #endif
    return ceil((text as NSString).size(withAttributes: [.font: font]).width)
  }
}

/// How a row of action tiles draws its names: the one size they share, and
/// whether every tile keeps room for a second line because one name wraps.
struct MobileTaskActionLabelStyle: Equatable {
  var size: CGFloat
  var reservesSecondLine = false
}

/// One action tile: the symbol over its name in the tile's tint, on the card
/// surface, the full width of its grid cell. The name is drawn at
/// `label.size`, the size its row fits every tile's name to. A name of several
/// words wraps between them onto a second line, and the row then gives every
/// name two lines of room, top aligned, so the symbols stay level
/// (`label.reservesSecondLine`); a name of one word, hyphenated or not
/// ("Когда-нибудь"), stays on one line, shrinking further only if it still
/// does not fit at that size, rather than breaking inside the word. An
/// unavailable tile keeps its card and draws its symbol and name in the
/// tertiary gray, the way a contact card shows an action it can't take, so
/// the row keeps its shape.
struct MobileTaskActionTile: View {
  let title: String
  let systemImage: String
  let label: MobileTaskActionLabelStyle
  var tint: Color = LorvexDesign.Palette.accent

  @Environment(\.isEnabled) private var isEnabled

  private var isOneWord: Bool { !title.contains(where: \.isWhitespace) }

  var body: some View {
    VStack(spacing: LorvexDesign.Spacing.xs) {
      Image(systemName: systemImage)
        .font(LorvexDesign.Typography.primaryText.weight(.semibold))
        .frame(height: 22)
      Text(title)
        // The footnote style scaled with the text, then fitted to the row.
        .font(.system(size: label.size, weight: .medium))  // lorvex-design-token: allow
        .lineLimit(isOneWord ? 1 : 2)
        .minimumScaleFactor(isOneWord ? 0.7 : 1)
        .multilineTextAlignment(.center)
        .frame(
          minHeight: label.reservesSecondLine
            ? MobileTaskActionLabelFit.height(lines: 2, size: label.size) : nil,
          alignment: .top)
    }
    .foregroundStyle(isEnabled ? AnyShapeStyle(tint) : AnyShapeStyle(.tertiary))
    .frame(maxWidth: .infinity, minHeight: 64)
    .padding(.horizontal, LorvexDesign.Spacing.xs)
    .padding(.vertical, LorvexDesign.Spacing.s)
    .background(LorvexDesign.Palette.card, in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.m, style: .continuous))
    .contentShape(RoundedRectangle(cornerRadius: LorvexDesign.Radius.m, style: .continuous))
  }
}

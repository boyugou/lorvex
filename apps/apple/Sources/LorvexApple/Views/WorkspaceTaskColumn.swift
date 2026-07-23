import AppKit
import LorvexCore
import SwiftUI

enum WorkspaceReviewLaneMetrics {
  /// Upper bound on the reading lane's width. The lane fills the window up to
  /// this cap, so a task list uses a large desktop window instead of sitting
  /// marooned in a narrow centered column; past the cap the surplus becomes
  /// balanced side margins so a row's due and tag signals never drift an arm's
  /// length from its title on an ultra-wide display.
  ///
  /// The dashboard lane shares this cap so every primary workspace (reading
  /// lists and card dashboards alike) centers at the same width — a title or
  /// row therefore keeps its left edge when switching tabs, instead of shifting
  /// because each surface centered a differently-sized column.
  static let maxWidth: CGFloat = 1180
}

enum WorkspaceDashboardLaneMetrics {
  static let maxWidth: CGFloat = WorkspaceReviewLaneMetrics.maxWidth
}

enum WorkspaceAuditLaneMetrics {
  static let maxWidth: CGFloat = 1320
}

/// Shared horizontal frame for task-review surfaces.
///
/// Use this for headers and row columns that should share one visual axis. The
/// lane fills the available width up to ``WorkspaceReviewLaneMetrics/maxWidth``
/// and then centers, so the list grows with the window on common desktop sizes
/// instead of sitting marooned in a narrow column, while the cap still bounds
/// the reading measure on ultra-wide displays. Table and calendar geometry use
/// their own wider lanes.
struct WorkspaceReviewLane<Content: View>: View {
  var alignment: Alignment = .leading
  @ViewBuilder let content: () -> Content

  var body: some View {
    content()
      .frame(maxWidth: WorkspaceReviewLaneMetrics.maxWidth, alignment: alignment)
      .frame(maxWidth: .infinity, alignment: .center)
  }
}

/// Shared chrome for task-review and result headers.
///
/// Use this when a workspace header should align with `WorkspaceTaskColumn` and
/// carry the same quiet bar material as the primary Plan surfaces. It keeps
/// task-review pages from accumulating private header padding/background rules.
struct WorkspaceReviewHeaderChrome<Content: View>: View {
  @ViewBuilder let content: () -> Content

  var body: some View {
    WorkspaceReviewLane {
      content()
    }
    .padding(.horizontal, LorvexDesign.Spacing.l)
    .padding(.vertical, LorvexDesign.Spacing.m)
    .background(.bar)
  }
}

/// Shared chrome for primary Plan-surface headers.
///
/// Today, Tasks, and Calendar have different content, but their identity,
/// signals, and low-frequency controls should sit on one shared axis with the
/// same bar material and spacing. Calendar's grid can still use full width; this
/// primitive only governs the header chrome.
struct WorkspacePlanHeaderChrome<Content: View>: View {
  @ViewBuilder let content: () -> Content

  var body: some View {
    WorkspaceReviewHeaderChrome {
      content()
    }
  }
}

/// Shared title/subtitle identity block for workspace headers.
///
/// The section name is a prominent large title here, not a small OS titlebar
/// string — the window's titlebar text
/// is suppressed so the name shows once, big, in the content. An optional
/// leading SF Symbol mirrors the sidebar icon.
///
/// Plan surfaces should not each tune their own title font, subtitle styling, or
/// reading width; route the common identity hierarchy through here. Keep
/// page-specific scope chips and actions outside this primitive.
struct WorkspaceHeaderIdentity<Accessory: View>: View {
  let title: String
  let subtitle: String
  let systemImage: String?
  let accessibilityIdentifier: String
  let subtitleAccessibilityIdentifier: String?
  @ViewBuilder let accessory: () -> Accessory

  init(
    title: String,
    subtitle: String,
    systemImage: String? = nil,
    accessibilityIdentifier: String,
    subtitleAccessibilityIdentifier: String? = nil,
    @ViewBuilder accessory: @escaping () -> Accessory
  ) {
    self.title = title
    self.subtitle = subtitle
    self.systemImage = systemImage
    self.accessibilityIdentifier = accessibilityIdentifier
    self.subtitleAccessibilityIdentifier = subtitleAccessibilityIdentifier
    self.accessory = accessory
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(alignment: .center, spacing: LorvexDesign.Spacing.s) {
        if let systemImage {
          Image(systemName: systemImage)
            .font(LorvexDesign.Typography.sectionHeader)
            .foregroundStyle(.tint)
            .accessibilityHidden(true)
        }

        Text(title)
          .font(LorvexDesign.Typography.screenTitle)
          .lineLimit(1)
          .layoutPriority(1)

        accessory()
      }

      // A title-only header (e.g. Calendar, where the chip + picker already
      // carry the date context) passes an empty subtitle and renders no caption
      // line rather than a blank gap.
      if !subtitle.isEmpty {
        Text(subtitle)
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .accessibilityIdentifier(subtitleAccessibilityIdentifier ?? "\(accessibilityIdentifier).subtitle")
      }
    }
    .frame(minWidth: 240, idealWidth: 360, maxWidth: 560, alignment: .leading)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier(accessibilityIdentifier)
  }
}

extension WorkspaceHeaderIdentity where Accessory == EmptyView {
  init(
    title: String,
    subtitle: String,
    systemImage: String? = nil,
    accessibilityIdentifier: String,
    subtitleAccessibilityIdentifier: String? = nil
  ) {
    self.init(
      title: title,
      subtitle: subtitle,
      systemImage: systemImage,
      accessibilityIdentifier: accessibilityIdentifier,
      subtitleAccessibilityIdentifier: subtitleAccessibilityIdentifier
    ) {
      EmptyView()
    }
  }
}

enum WorkspaceHeaderSummaryTone {
  case primary
  case secondary

  var foregroundStyle: AnyShapeStyle {
    switch self {
    case .primary:
      AnyShapeStyle(.primary)
    case .secondary:
      AnyShapeStyle(.secondary)
    }
  }
}

/// Shared descriptive text for workspace headers.
///
/// Keep header summaries quiet and bounded. Use `.primary` for the short
/// assistant/day explanation below a Plan identity, and `.secondary` for
/// review-result subtitles that sit directly under a smaller section title.
struct WorkspaceHeaderSummary: View {
  let text: String
  let accessibilityIdentifier: String
  var tone: WorkspaceHeaderSummaryTone = .primary
  var lineLimit: Int? = 2
  var expandsVertically = true

  var body: some View {
    summaryText
      .accessibilityIdentifier(accessibilityIdentifier)
  }

  private var summaryText: some View {
    Text(text)
      .font(LorvexDesign.Typography.secondaryText)
      .foregroundStyle(tone.foregroundStyle)
      .lineLimit(lineLimit)
      .fixedSize(horizontal: false, vertical: expandsVertically)
  }
}

/// Shared visual treatment for quiet header actions.
///
/// Use this for secondary actions in Plan/Review/Dashboard headers: view
/// options, save/share/export, create, and batch-action menus. Primary CTAs
/// such as Today's focus start can keep their stronger button style.
struct WorkspaceHeaderActionStyle: ViewModifier {
  func body(content: Content) -> some View {
    content
      .buttonStyle(.lorvexNeutral)
      .labelStyle(.iconOnly)
  }
}

/// Header-action chrome with the title visible. For domain-specific actions
/// (save a search, batch selection actions, view options) whose glyph alone
/// does not communicate the verb — an unlabeled icon there reads as a mystery
/// button. Universally-understood glyphs (+, share) keep
/// ``WorkspaceHeaderActionStyle``'s icon-only form with a tooltip.
struct WorkspaceHeaderLabeledActionStyle: ViewModifier {
  func body(content: Content) -> some View {
    content
      .buttonStyle(.lorvexNeutral)
      .labelStyle(.titleAndIcon)
  }
}

extension View {
  func workspaceHeaderActionStyle() -> some View {
    modifier(WorkspaceHeaderActionStyle())
  }

  func workspaceHeaderLabeledActionStyle() -> some View {
    modifier(WorkspaceHeaderLabeledActionStyle())
  }
}

/// Shared reading measure for task-review lists.
///
/// Browse surfaces should not stretch a task row across an arbitrarily wide
/// window; doing so pushes due badges and hover targets away from the title and
/// makes Today, Tasks, Lists, and Calendar feel like different
/// products. The reading lane grows with the window but caps at
/// ``WorkspaceReviewLaneMetrics/maxWidth`` so task rows stay near a readable
/// desktop document width while still leaving room for bilingual titles, tags,
/// and due signals. Tables and time grids can use wider lanes because they are
/// audit/geometry surfaces rather than reading lists.
struct WorkspaceTaskColumn<Content: View>: View {
  @ViewBuilder let content: () -> Content

  var body: some View {
    WorkspaceReviewLane {
      content()
    }
  }
}

/// Shared scroll/list skeleton for task-review result surfaces.
///
/// Today, Tasks, Calendar's list mode, and list details
/// all read as task review queues even when their section content differs. Keep
/// the scroll view, reading lane, row stack, and bottom breathing room here so
/// those surfaces cannot drift into slightly different geometry over time.
///
/// Passing `taskNavigation` additionally layers arrow-key row traversal onto
/// the list (see ``WorkspaceTaskArrowKeyNavigation``) — every real task-review
/// call site builds one from its `AppStore`'s active-workspace selection API;
/// `nil` (the default) leaves the list inert to arrow keys, e.g. the
/// initial-loading placeholder, which has no rows to traverse.
struct WorkspaceReviewList<Content: View>: View {
  var bottomPadding: CGFloat = LorvexDesign.Spacing.l
  var taskNavigation: WorkspaceTaskArrowKeyNavigation? = nil
  @ViewBuilder let content: () -> Content

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        WorkspaceTaskColumn {
          LazyVStack(alignment: .leading, spacing: 0) {
            content()
          }
          .padding(.bottom, bottomPadding)
        }
      }
      .modifier(WorkspaceTaskArrowKeyNavigationModifier(navigation: taskNavigation, proxy: proxy))
    }
  }
}

// MARK: - Arrow-key row traversal

/// A step ``WorkspaceReviewList``'s arrow-key layer can move by. The vertical
/// arrow directions collapse to `.previous`/`.next` (SwiftUI's
/// `.onMoveCommand` gives left/right no meaning on a vertical list), and
/// Home/End map to `.first`/`.last`.
enum WorkspaceTaskArrowKeyStep {
  case previous
  case next
  case first
  case last
}

/// Pure row-traversal math for ``WorkspaceReviewList``'s arrow-key layer,
/// factored out of the view so it is unit-testable without SwiftUI.
enum WorkspaceTaskArrowKeyMovement {
  /// The row a `step` should move to from `anchor`, or `nil` when there's
  /// nowhere to go: `orderedIDs` is empty, or `.previous`/`.next` is already
  /// at that edge (movement never wraps, matching Finder/Mail list
  /// navigation).
  ///
  /// `.previous`/`.next` with no anchor, or an anchor no longer present in
  /// `orderedIDs` (e.g. filtered out since it was set), starts from the first
  /// row rather than failing — an arrow press should always land somewhere
  /// while rows exist.
  static func target(
    for step: WorkspaceTaskArrowKeyStep,
    anchor: LorvexTask.ID?,
    orderedIDs: [LorvexTask.ID]
  ) -> LorvexTask.ID? {
    guard !orderedIDs.isEmpty else { return nil }
    switch step {
    case .first:
      return orderedIDs.first
    case .last:
      return orderedIDs.last
    case .previous:
      guard let anchor, let index = orderedIDs.firstIndex(of: anchor) else { return orderedIDs.first }
      guard index > 0 else { return nil }
      return orderedIDs[index - 1]
    case .next:
      guard let anchor, let index = orderedIDs.firstIndex(of: anchor) else { return orderedIDs.first }
      guard index < orderedIDs.count - 1 else { return nil }
      return orderedIDs[index + 1]
    }
  }
}

/// Wires arrow-key row traversal onto a ``WorkspaceReviewList``.
///
/// `orderedTaskIDs` is the surface's rows in display order — the same basis
/// shift-click range-selection uses (`AppStore.orderedTaskIDs(on:)`)
/// — and `selectedTaskID` is the current anchor
/// (`AppStore.selectedTaskID`). `selectOnly` mirrors a plain click (replace
/// the selection with one row and open its detail —
/// `AppStore.selectOnlyTask(_:on:)`); `extendSelection` mirrors a shift-click
/// (grow the range from the anchor — `AppStore.extendTaskSelection(on:to:)`).
struct WorkspaceTaskArrowKeyNavigation {
  let orderedTaskIDs: [LorvexTask.ID]
  let selectedTaskID: LorvexTask.ID?
  let selectOnly: (LorvexTask.ID) -> Void
  let extendSelection: (LorvexTask.ID) -> Void
}

/// Layers arrow-key traversal onto a scrollable task list.
///
/// ↑/↓ move `navigation.selectedTaskID` to the adjacent row (a plain click);
/// Home/End jump to the first/last row. Holding Shift extends the selection
/// from the anchor instead (a shift-click). SwiftUI's `.onMoveCommand`
/// collapses the Shift-modified AppKit selectors (`moveUpAndModifySelection:`)
/// into the same `MoveCommandDirection` as the plain ones and doesn't surface
/// modifiers on `KeyPress` either for `.onKeyPress`'s zero-argument overload,
/// so Shift is read directly off `NSEvent.modifierFlags` at the moment the
/// command fires — the same trick ``WorkspaceSelectableTaskRow`` already uses
/// for its click modifiers, since SwiftUI's gesture/command APIs don't
/// otherwise surface them.
///
/// `keyboardEdge` tracks the far end of an in-progress Shift sequence:
/// `extendSelection` intentionally leaves the anchor (`selectedTaskID`) fixed
/// so repeated Shift-clicks/arrows keep growing the same range from it, so the
/// *next* target must be computed from where the last arrow press landed, not
/// from the anchor. It resyncs to `selectedTaskID` whenever that changes for
/// any other reason (a click, Tab+Return elsewhere), so a stale edge from a
/// previous Shift sequence can't leak into a new one.
private struct WorkspaceTaskArrowKeyNavigationModifier: ViewModifier {
  let navigation: WorkspaceTaskArrowKeyNavigation?
  let proxy: ScrollViewProxy

  @State private var keyboardEdge: LorvexTask.ID?

  func body(content: Content) -> some View {
    content
      .onMoveCommand { direction in
        guard let navigation else { return }
        let step: WorkspaceTaskArrowKeyStep
        switch direction {
        case .up: step = .previous
        case .down: step = .next
        default: return
        }
        move(to: step, navigation: navigation, extending: NSEvent.modifierFlags.contains(.shift))
      }
      .onKeyPress(.home) {
        guard let navigation else { return .ignored }
        move(to: .first, navigation: navigation, extending: NSEvent.modifierFlags.contains(.shift))
        return .handled
      }
      .onKeyPress(.end) {
        guard let navigation else { return .ignored }
        move(to: .last, navigation: navigation, extending: NSEvent.modifierFlags.contains(.shift))
        return .handled
      }
      .onChange(of: navigation?.selectedTaskID) { _, newValue in
        keyboardEdge = newValue
      }
  }

  private func move(
    to step: WorkspaceTaskArrowKeyStep, navigation: WorkspaceTaskArrowKeyNavigation, extending: Bool
  ) {
    guard
      let target = WorkspaceTaskArrowKeyMovement.target(
        for: step,
        anchor: keyboardEdge ?? navigation.selectedTaskID,
        orderedIDs: navigation.orderedTaskIDs)
    else { return }
    keyboardEdge = target
    if extending {
      navigation.extendSelection(target)
    } else {
      navigation.selectOnly(target)
    }
    lorvexAnimated(.snappy(duration: 0.16)) {
      proxy.scrollTo(target, anchor: nil)
    }
  }
}

/// Shared card measure for dashboard-like surfaces.
///
/// This is wider than the task review lane because cards, split summaries, and
/// heatmaps need more horizontal air than text rows, but it still prevents
/// reflective surfaces from stretching cards across an entire desktop window.
struct WorkspaceDashboardLane<Content: View>: View {
  var alignment: Alignment = .leading
  @ViewBuilder let content: () -> Content

  var body: some View {
    content()
      .frame(maxWidth: WorkspaceDashboardLaneMetrics.maxWidth, alignment: alignment)
      .frame(maxWidth: .infinity, alignment: .center)
  }
}

/// Shared chrome for dashboard-like workspace headers.
///
/// Use this when a header should align with dashboard cards, heatmaps, or split
/// insight canvases instead of the narrower task-review reading lane.
struct WorkspaceDashboardHeaderChrome<Content: View>: View {
  @ViewBuilder let content: () -> Content

  var body: some View {
    WorkspaceDashboardLane {
      content()
    }
    .padding(.horizontal, LorvexDesign.Spacing.l)
    .padding(.vertical, LorvexDesign.Spacing.m)
    .background(.bar)
  }
}

/// Shared wide measure for audit surfaces such as sortable tables.
///
/// Audit views need more width than review rows because columns must be
/// comparable, but they still should not become an unbounded full-window sheet
/// on large desktop displays. Use this for table-like surfaces that need calm
/// framing without adopting the narrower task reading measure.
struct WorkspaceAuditLane<Content: View>: View {
  var alignment: Alignment = .leading
  @ViewBuilder let content: () -> Content

  var body: some View {
    content()
      .frame(maxWidth: WorkspaceAuditLaneMetrics.maxWidth, alignment: alignment)
      .frame(maxWidth: .infinity, alignment: .center)
  }
}

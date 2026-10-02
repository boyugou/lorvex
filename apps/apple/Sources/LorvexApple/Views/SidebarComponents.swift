import SwiftUI
import LorvexCore

enum SidebarMetrics {
    static let iconWidth: CGFloat = 22
    static let rowHeight: CGFloat = 44
    static let compactRowHeight: CGFloat = 42
    static let rowLeadingPadding: CGFloat = 8
    static let rowTrailingPadding: CGFloat = 8
    static let horizontalInset: CGFloat = 12
    static let rowSpacing: CGFloat = 2
    /// The sole source of truth for the sidebar column's width range;
    /// `ContentView` passes these straight to `navigationSplitViewColumnWidth`.
    ///
    /// The ideal fits a list name of roughly "NeoCognition" length beside the
    /// icon and the open-count badge without truncating — the name is the row's
    /// primary identifier, so it must not be the first thing sacrificed. The max
    /// leaves drag room for longer names.
    static let columnMinWidth: CGFloat = 180
    static let columnIdealWidth: CGFloat = 232
    static let columnMaxWidth: CGFloat = 340

    /// Content insets applied to every `List` row so the icon column rides near
    /// the source-list leading edge instead of the default sidebar indent, which
    /// would push the fixed 22pt icon column out of alignment.
    static let rowInsets = EdgeInsets(
        top: rowSpacing,
        leading: rowLeadingPadding,
        bottom: rowSpacing,
        trailing: rowTrailingPadding
    )
}

enum SidebarTypography {
    static let section = LorvexDesign.Typography.primaryText.weight(.semibold)
    static let title = LorvexDesign.Typography.primaryEmphasis
}

/// A `List` `Section` header for the source list. Rendered inside the section's
/// `header:` slot, so it carries only text styling — the `List` owns the
/// header's position, inset, and section spacing.
struct SidebarSectionHeader: View {
    let title: LocalizedStringResource

    var body: some View {
        Text(title)
            .font(SidebarTypography.section)
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }
}

struct SidebarListIcon: View {
    let icon: String?
    let tint: Color

    var body: some View {
        LorvexListIconView(
            icon: icon,
            tint: tint,
            size: SidebarMetrics.iconWidth,
            font: LorvexDesign.Typography.primaryText.weight(.medium)
        )
    }
}

/// A source-list row rendered inside `List(selection:)`. It draws only content —
/// icon column, a one-line title, and an optional trailing count badge in the
/// locale's digits — and
/// leaves the selection highlight, hover, focus ring, and inactive-window
/// desaturation to the native `.sidebar` list. Titles and the bare-symbol icon
/// use hierarchical styles (`.primary` / `.secondary`) so the list inverts them
/// against the selection fill; a colored `SidebarListIcon` keeps its own tint.
struct SidebarListRow<Icon: View, Title: View>: View {
    let count: Int?
    let icon: Icon
    let title: Title

    init(
        count: Int? = nil,
        @ViewBuilder icon: () -> Icon,
        @ViewBuilder title: () -> Title
    ) {
        self.count = count
        self.icon = icon()
        self.title = title()
    }

    var body: some View {
        HStack(spacing: LorvexDesign.Spacing.s) {
            icon
                .frame(width: SidebarMetrics.iconWidth, alignment: .center)
                .foregroundStyle(.secondary)
            title
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let count {
                Text(count, format: .number)
                    .font(LorvexDesign.Typography.tertiaryText.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, LorvexDesign.Spacing.sm)
                    .padding(.vertical, 1)
                    .background(.quaternary.opacity(0.75), in: Capsule())
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .font(SidebarTypography.title)
        .frame(maxWidth: .infinity, minHeight: SidebarMetrics.rowHeight, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// A pinned row below the scrolling source list (Memory, Settings). It lives
/// outside the `List`, so it draws its own hover pill and, for a destination,
/// its own selection (the `List` can't), while matching the row metrics and
/// icon column of the list rows above it.
struct SidebarFooterRow<Icon: View, Title: View>: View {
    let isSelected: Bool
    let icon: Icon
    let title: Title
    @State private var isHovering = false

    init(
        isSelected: Bool = false,
        @ViewBuilder icon: () -> Icon,
        @ViewBuilder title: () -> Title
    ) {
        self.isSelected = isSelected
        self.icon = icon()
        self.title = title()
    }

    var body: some View {
        HStack(spacing: LorvexDesign.Spacing.s) {
            icon
                .frame(width: SidebarMetrics.iconWidth, alignment: .center)
                .foregroundStyle(.secondary)
            title
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .font(SidebarTypography.title)
        .padding(.leading, SidebarMetrics.rowLeadingPadding)
        .padding(.trailing, SidebarMetrics.rowTrailingPadding)
        .frame(maxWidth: .infinity, minHeight: SidebarMetrics.compactRowHeight, alignment: .leading)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: LorvexDesign.Radius.s)
                    .fill(LorvexDesign.Palette.sidebarSelectionFill)
                    .padding(.vertical, LorvexDesign.Spacing.xxs)
            } else if isHovering {
                RoundedRectangle(cornerRadius: LorvexDesign.Radius.s)
                    .fill(LorvexDesign.Palette.hoverFill)
                    .padding(.vertical, LorvexDesign.Spacing.xxs)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: LorvexDesign.Radius.s))
        .onHover { isHovering = $0 }
    }
}

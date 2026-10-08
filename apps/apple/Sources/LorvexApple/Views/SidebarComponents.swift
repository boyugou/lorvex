import SwiftUI
import LorvexCore

enum SidebarMetrics {
    static let iconWidth: CGFloat = 22
    static let rowHeight: CGFloat = 44
    static let compactRowHeight: CGFloat = 42
    static let rowLeadingPadding: CGFloat = 8
    static let rowTrailingPadding: CGFloat = 8
    /// How far the native sidebar list insets a row's selection capsule from the
    /// column edge. The pinned footer draws its own capsule at the same inset.
    static let capsuleInset: CGFloat = 10
    /// How far the native sidebar list pads a row's content inside its selection
    /// capsule, on top of the row's own `rowInsets`. The footer adds it to
    /// `rowLeadingPadding` and `rowTrailingPadding` so its icon column and
    /// titles line up with the list rows above it.
    static let capsuleContentPadding: CGFloat = 6
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

    /// How far a row's content sits inside the system's selection capsule: the
    /// row's own insets plus the padding the native list adds. A task drop
    /// highlight extends by this much so its outline lies on the capsule.
    static let capsuleOutset = EdgeInsets(
        top: rowSpacing,
        leading: rowLeadingPadding + capsuleContentPadding,
        bottom: rowSpacing,
        trailing: rowTrailingPadding + capsuleContentPadding
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
///
/// The icon is decoration and is hidden from VoiceOver. A row with a count
/// passes `spokenLabel`, which makes the whole row one element that reads it
/// (a bare number beside a name says nothing about what it counts); a row
/// without one reads its title.
struct SidebarListRow<Icon: View, Title: View>: View {
    let count: Int?
    let spokenLabel: String?
    let icon: Icon
    let title: Title

    init(
        count: Int? = nil,
        spokenLabel: String? = nil,
        @ViewBuilder icon: () -> Icon,
        @ViewBuilder title: () -> Title
    ) {
        self.count = count
        self.spokenLabel = spokenLabel
        self.icon = icon()
        self.title = title()
    }

    var body: some View {
        HStack(spacing: LorvexDesign.Spacing.s) {
            icon
                .frame(width: SidebarMetrics.iconWidth, alignment: .center)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
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
        .sidebarSpokenLabel(spokenLabel)
    }
}

private extension View {
    /// One accessibility element that reads `label`, or the view unchanged
    /// without one.
    @ViewBuilder
    func sidebarSpokenLabel(_ label: String?) -> some View {
        if let label {
            accessibilityElement(children: .ignore).accessibilityLabel(label)
        } else {
            self
        }
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
                .accessibilityHidden(true)
            title
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .font(SidebarTypography.title)
        .padding(.leading, SidebarMetrics.rowLeadingPadding + SidebarMetrics.capsuleContentPadding)
        .padding(.trailing, SidebarMetrics.rowTrailingPadding + SidebarMetrics.capsuleContentPadding)
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

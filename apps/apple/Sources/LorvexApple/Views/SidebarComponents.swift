import SwiftUI
import LorvexCore

enum SidebarMetrics {
    static let iconWidth: CGFloat = 22
    static let rowHeight: CGFloat = 44
    static let scopeRowHeight: CGFloat = 50
    static let compactRowHeight: CGFloat = 42
    static let rowLeadingPadding: CGFloat = 8
    static let rowTrailingPadding: CGFloat = 8
    static let horizontalInset: CGFloat = 12
    static let rowSpacing: CGFloat = 2
    static let columnMinWidth: CGFloat = 148
    static let columnIdealWidth: CGFloat = 164
    static let columnMaxWidth: CGFloat = 184

    /// Content insets applied to every `List` row so the icon column rides near
    /// the source-list leading edge instead of the default sidebar indent, which
    /// would push the fixed 22pt icon column out of alignment in the narrow
    /// (148–184pt) column. Locked by `macOSSidebarRowsKeepIconColumnInsideNarrowSourceList`.
    static let rowInsets = EdgeInsets(
        top: rowSpacing,
        leading: rowLeadingPadding,
        bottom: rowSpacing,
        trailing: rowTrailingPadding
    )
}

enum SidebarTypography {
    static let section = LorvexDesign.Typography.primaryText.weight(.semibold)
    static let destinationTitle = LorvexDesign.Typography.primaryEmphasis
    static let compactTitle = LorvexDesign.Typography.primaryEmphasis
    static let destinationDetail = LorvexDesign.Typography.secondaryText
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
/// icon column, title, optional secondary detail line, optional trailing count
/// badge — and leaves the selection highlight, hover, focus ring, and
/// inactive-window desaturation to the native `.sidebar` list. Titles and the
/// bare-symbol icon use hierarchical styles (`.primary` / `.secondary`) so the
/// list inverts them against the selection fill; a colored `SidebarListIcon`
/// keeps its own tint.
struct SidebarListRow<Icon: View, Title: View>: View {
    let minHeight: CGFloat
    let detail: String?
    let badge: String?
    let icon: Icon
    let title: Title

    init(
        minHeight: CGFloat = SidebarMetrics.rowHeight,
        detail: String? = nil,
        badge: String? = nil,
        @ViewBuilder icon: () -> Icon,
        @ViewBuilder title: () -> Title
    ) {
        self.minHeight = minHeight
        self.detail = detail
        self.badge = badge
        self.icon = icon()
        self.title = title()
    }

    var body: some View {
        HStack(spacing: LorvexDesign.Spacing.s) {
            icon
                .frame(width: SidebarMetrics.iconWidth, alignment: .center)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                title
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                if let detail {
                    Text(detail)
                        .font(SidebarTypography.destinationDetail)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let badge {
                Text(badge)
                    .font(LorvexDesign.Typography.tertiaryText.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.quaternary.opacity(0.75), in: Capsule())
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .font(detail == nil ? SidebarTypography.compactTitle : SidebarTypography.destinationTitle)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// The pinned Settings row below the scrolling source list. It lives outside the
/// `List`, so it draws its own hover pill (the `List` can't) while matching the
/// row metrics and icon column of the list rows above it.
struct SidebarFooterRow<Icon: View, Title: View>: View {
    let icon: Icon
    let title: Title
    @State private var isHovering = false

    init(@ViewBuilder icon: () -> Icon, @ViewBuilder title: () -> Title) {
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
        .font(SidebarTypography.compactTitle)
        .padding(.leading, SidebarMetrics.rowLeadingPadding)
        .padding(.trailing, SidebarMetrics.rowTrailingPadding)
        .frame(maxWidth: .infinity, minHeight: SidebarMetrics.compactRowHeight, alignment: .leading)
        .background {
            if isHovering {
                RoundedRectangle(cornerRadius: LorvexDesign.Radius.s)
                    .fill(.quaternary.opacity(0.75))
                    .padding(.vertical, 3)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: LorvexDesign.Radius.s))
        .onHover { isHovering = $0 }
    }
}

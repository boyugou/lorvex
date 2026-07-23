import LorvexCore
import SwiftUI

struct MobileSkeletonRows: View {
  var count = 4
  var showsTrailingDetail = false

  var body: some View {
    ForEach(0..<count, id: \.self) { index in
      MobileSkeletonRow(
        titleWidth: index.isMultiple(of: 2) ? 0.66 : 0.48,
        detailWidth: index.isMultiple(of: 2) ? 0.46 : 0.58,
        showsTrailingDetail: showsTrailingDetail
      )
    }
    .redacted(reason: .placeholder)
    .mobileSkeletonShimmer()
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

struct MobileSkeletonRow: View {
  let titleWidth: CGFloat
  let detailWidth: CGFloat
  var showsTrailingDetail = false

  var body: some View {
    HStack(spacing: 12) {
      Circle()
        .fill(.secondary.opacity(0.24))
        .frame(width: 22, height: 22)

      VStack(alignment: .leading, spacing: 6) {
        Capsule()
          .fill(.secondary.opacity(0.24))
          .frame(maxWidth: .infinity)
          .frame(height: 14)
          .containerRelativeFrame(.horizontal) { width, _ in width * titleWidth }
        Capsule()
          .fill(.secondary.opacity(0.18))
          .frame(maxWidth: .infinity)
          .frame(height: 10)
          .containerRelativeFrame(.horizontal) { width, _ in width * detailWidth }
      }

      Spacer(minLength: 8)

      if showsTrailingDetail {
        Circle()
          .fill(.secondary.opacity(0.18))
          .frame(width: 26, height: 26)
      }
    }
    .padding(.vertical, LorvexDesign.Spacing.s)
  }
}

struct MobileListDetailSkeleton: View {
  var body: some View {
    Section {
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
        Capsule()
          .fill(.secondary.opacity(0.24))
          .frame(width: 180, height: 18)
        Capsule()
          .fill(.secondary.opacity(0.18))
          .frame(width: 240, height: 12)
        Capsule()
          .fill(.secondary.opacity(0.18))
          .frame(width: 140, height: 12)
      }
      .padding(.vertical, LorvexDesign.Spacing.s)
    }
    .redacted(reason: .placeholder)
    .mobileSkeletonShimmer()
    .allowsHitTesting(false)
    .accessibilityHidden(true)

    Section(String(localized: "list_detail.section.tasks", defaultValue: "Tasks", table: "Localizable", bundle: MobileL10n.bundle)) {
      MobileSkeletonRows(count: 4)
    }
  }
}

struct MobileInitialWorkspaceSkeleton: View {
  var body: some View {
    List {
      Section {
        VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
          Capsule()
            .fill(.secondary.opacity(0.24))
            .frame(width: 220, height: 18)
          Capsule()
            .fill(.secondary.opacity(0.18))
            .frame(width: 280, height: 12)
          HStack(spacing: LorvexDesign.Spacing.s) {
            ForEach(0..<3, id: \.self) { _ in
              Capsule()
                .fill(.secondary.opacity(0.16))
                .frame(width: 72, height: 18)
            }
          }
        }
        .padding(.vertical, LorvexDesign.Spacing.s)
      }

      Section(String(localized: "today.section.next", defaultValue: "Next", table: "Localizable", bundle: MobileL10n.bundle)) {
        MobileSkeletonRows(count: 1, showsTrailingDetail: true)
      }

      Section(String(localized: "today.section.today", defaultValue: "Today", table: "Localizable", bundle: MobileL10n.bundle)) {
        MobileSkeletonRows(count: 3)
      }
    }
    .redacted(reason: .placeholder)
    .mobileSkeletonShimmer()
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

private struct MobileSkeletonShimmer: ViewModifier {
  @State private var isAnimating = false

  func body(content: Content) -> some View {
    content
      .overlay {
        shimmer
          .mask(content)
          .allowsHitTesting(false)
      }
      .onAppear {
        withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
          isAnimating = true
        }
      }
  }

  private var shimmer: some View {
    GeometryReader { proxy in
      LinearGradient(
        colors: [
          .clear,
          .white.opacity(0.32),
          .clear,
        ],
        startPoint: .top,
        endPoint: .bottom
      )
      .frame(width: max(proxy.size.width * 0.35, 80))
      .rotationEffect(.degrees(18))
      .offset(x: isAnimating ? proxy.size.width * 1.2 : -proxy.size.width * 0.6)
    }
  }
}

private extension View {
  func mobileSkeletonShimmer() -> some View {
    modifier(MobileSkeletonShimmer())
  }
}

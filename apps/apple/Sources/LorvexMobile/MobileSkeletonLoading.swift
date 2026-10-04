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

/// The loading placeholder for a pushed detail screen (a habit, a memory
/// note): a header block of a title and two lines, over a section of rows.
struct MobileDetailSkeleton: View {
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

    Section {
      MobileSkeletonRows(count: 4)
    }
  }
}

/// The first-load placeholder, shaped like Today: the page's date and facts
/// line over the background, then one untitled section of task rows, until the
/// snapshot arrives. It covers the whole page, date included, so it draws the
/// header's shape itself.
struct MobileInitialWorkspaceSkeleton: View {
  var body: some View {
    List {
      Section {
        VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
          Capsule()
            .fill(.secondary.opacity(0.24))
            .frame(width: 230, height: 26)
          Capsule()
            .fill(.secondary.opacity(0.18))
            .frame(width: 180, height: 12)
        }
        .padding(.vertical, LorvexDesign.Spacing.xs)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(
          EdgeInsets(
            top: LorvexDesign.Spacing.xs, leading: 0, bottom: LorvexDesign.Spacing.xs, trailing: 0))
      }

      Section {
        MobileSkeletonRows(count: 4)
      }
    }
    .contentMargins(.top, LorvexDesign.Spacing.s, for: .scrollContent)
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
      .onAppear { isAnimating = true }
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
      // Scoped to the band's own offset: a `withAnimation` around the state
      // change would carry the forever-repeating animation to every other
      // change in the update the skeleton appears in, such as the surrounding
      // screen's first real layout, which then never settles.
      .reduceMotionAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false), value: isAnimating)
    }
  }
}

private extension View {
  func mobileSkeletonShimmer() -> some View {
    modifier(MobileSkeletonShimmer())
  }
}

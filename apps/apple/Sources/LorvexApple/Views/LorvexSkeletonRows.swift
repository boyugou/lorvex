import LorvexCore
import SwiftUI

/// A redacted-placeholder skeleton for a content list's first paint, used in
/// place of a bare spinner so the surface previews its own shape while data
/// loads. Rows are non-interactive and hidden from assistive tech; a slow
/// shimmer signals "loading" without the churn of an indeterminate spinner.
struct LorvexSkeletonRows: View {
  var count = 3

  var body: some View {
    VStack(spacing: LorvexDesign.Spacing.s) {
      ForEach(0..<count, id: \.self) { index in
        LorvexSkeletonRow(titleWidth: index.isMultiple(of: 2) ? 0.5 : 0.36)
      }
    }
    .redacted(reason: .placeholder)
    .lorvexSkeletonShimmer()
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

private struct LorvexSkeletonRow: View {
  let titleWidth: CGFloat

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
      Capsule()
        .fill(.secondary.opacity(0.22))
        .frame(height: 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerRelativeFrame(.horizontal) { width, _ in width * titleWidth }
      Capsule()
        .fill(.secondary.opacity(0.16))
        .frame(height: 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(LorvexDesign.Spacing.m)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      .quaternary.opacity(0.18),
      in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.m, style: .continuous))
  }
}

private struct LorvexSkeletonShimmer: ViewModifier {
  @State private var isAnimating = false

  func body(content: Content) -> some View {
    content
      .overlay {
        GeometryReader { proxy in
          LinearGradient(
            colors: [.clear, .white.opacity(0.28), .clear],
            startPoint: .top,
            endPoint: .bottom
          )
          .frame(width: max(proxy.size.width * 0.35, 80))
          .rotationEffect(.degrees(18))
          .offset(x: isAnimating ? proxy.size.width * 1.2 : -proxy.size.width * 0.6)
        }
        .mask(content)
        .allowsHitTesting(false)
      }
      .onAppear {
        withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
          isAnimating = true
        }
      }
  }
}

extension View {
  fileprivate func lorvexSkeletonShimmer() -> some View {
    modifier(LorvexSkeletonShimmer())
  }
}

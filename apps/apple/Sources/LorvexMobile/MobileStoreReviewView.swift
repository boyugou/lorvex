import Foundation
import LorvexCore
import SwiftUI

enum MobileReviewMode: String, CaseIterable, Identifiable {
  case daily
  case weekly

  var id: String { rawValue }

  var title: String {
    switch self {
    case .daily:
      String(
        localized: "review.mode.daily", defaultValue: "Day", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .weekly:
      String(
        localized: "review.mode.weekly", defaultValue: "Week", table: "Localizable",
        bundle: MobileL10n.bundle)
    }
  }
}

extension View {
  /// Opens a review page at its top, except in DEBUG builds launched with
  /// `-lorvexScrollReviewToEnd`, which open it at its end for a screenshot of
  /// the sections below the fold. Offset only: a page shorter than the screen
  /// still starts at the top.
  func mobileReviewScrollAnchor() -> some View {
    #if DEBUG
      defaultScrollAnchor(MobileStore.debugScrollReviewToEnd ? .bottom : nil, for: .initialOffset)
    #else
      self
    #endif
  }
}

public struct MobileStoreReviewView: View {
  @Bindable private var store: MobileStore
  @State private var mode: MobileReviewMode = .daily

  public init(store: MobileStore) {
    self.store = store
  }


  public var body: some View {
    Group {
      switch mode {
      case .daily:
        MobileStoreReviewDayPage(store: store)
      case .weekly:
        MobileStoreReviewWeekPage(store: store) { date in
          Task {
            await store.selectReviewDay(date)
            mode = .daily
          }
        }
      }
    }
    .navigationTitle(MobileTab.review.title)
    .task {
      await store.loadDailyReviewDraft()
      await store.loadWeekReviewDigest(weekOf: store.weeklyReviewAnchor)
    }
    .task(id: mode) {
      if mode == .weekly {
        await store.loadWeekReviewDigest(weekOf: store.weeklyReviewAnchor)
      }
    }
    #if DEBUG
      .onAppear {
        if let initial = MobileReviewDebugState.takeInitialMode() {
          mode = initial
        }
      }
    #endif
    #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
    #endif
    .toolbar {
      // The Day / Week switch stands in for the title, as on Plan; the tab
      // bar already names the surface.
      ToolbarItem(placement: .principal) {
        Picker(
          String(
            localized: "review.mode.picker", defaultValue: "Review Mode", table: "Localizable",
            bundle: MobileL10n.bundle), selection: $mode
        ) {
          ForEach(MobileReviewMode.allCases) { mode in
            Text(mode.title).tag(mode)
          }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 280)
        .accessibilityIdentifier("review.mode.picker")
      }
      if mode == .daily, let review = store.dailyReview {
        ToolbarItem(placement: .automatic) {
          ShareLink(item: MobileShareText.dailyReview(review)) {
            Label(
              String(
                localized: "review.share_daily", defaultValue: "Share Daily", table: "Localizable",
                bundle: MobileL10n.bundle),
              systemImage: "square.and.arrow.up"
            )
          }
          .accessibilityLabel(
            String(
              localized: "review.share_daily.a11y", defaultValue: "Share daily review",
              table: "Localizable", bundle: MobileL10n.bundle)
          )
          .lorvexToolbarHoverEffect()
          .accessibilityIdentifier("review.toolbar.shareDaily")
        }
      }
      if mode == .weekly, let review = store.snapshot.weeklyReview {
        ToolbarItem(placement: .automatic) {
          ShareLink(item: MobileShareText.weeklyReview(review)) {
            Label(
              String(
                localized: "review.share_weekly", defaultValue: "Share Weekly",
                table: "Localizable", bundle: MobileL10n.bundle),
              systemImage: "calendar.badge.clock"
            )
          }
          .accessibilityLabel(
            String(
              localized: "review.share_weekly.a11y", defaultValue: "Share weekly review",
              table: "Localizable", bundle: MobileL10n.bundle)
          )
          .lorvexToolbarHoverEffect()
          .accessibilityIdentifier("review.toolbar.shareWeekly")
        }
      }
    }
  }
}

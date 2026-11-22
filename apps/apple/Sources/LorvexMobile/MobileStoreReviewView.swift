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
  @State private var searchText = ""
  @State private var searchPresented = false
  @FocusState private var searchFocused: Bool

  private var searchPrompt: String {
    String(localized: "review.journal.search", defaultValue: "Search Journal",
      table: "Localizable", bundle: MobileL10n.bundle)
  }

  private var phrase: String {
    searchText.split(whereSeparator: \.isWhitespace).joined(separator: " ")
  }

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
    .accessibilityHidden(!phrase.isEmpty)
    .allowsHitTesting(phrase.isEmpty)
    .overlay {
      if !phrase.isEmpty {
        MobileReviewJournalResults(store: store, phrase: phrase) { day in
          await store.selectReviewDay(day, forEditing: true)
          guard store.selectedReviewDate == day, store.reviewDraftDate == day,
            store.selectedReviewDayIsEditable else { return }
          searchPresented = false
          searchText = ""
          mode = .daily
        }
        .id(phrase)
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
        if searchPresented {
          journalSearchField
        } else {
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
      }
      ToolbarItem(placement: .automatic) {
        if searchPresented {
          Button {
            searchFocused = false
            searchText = ""
            searchPresented = false
          } label: {
            Label(String(localized: "common.done", defaultValue: "Done",
              table: "Localizable", bundle: MobileL10n.bundle), systemImage: "xmark")
          }
          .accessibilityIdentifier("review.search.close")
        } else {
          Button { searchPresented = true } label: {
            Label(searchPrompt, systemImage: "magnifyingglass")
          }
          .keyboardShortcut("f", modifiers: .command)
          .accessibilityIdentifier("review.search.open")
        }
      }
      if !searchPresented, mode == .daily, let review = store.dailyReview, review.date == store.selectedReviewDate {
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
      if !searchPresented, mode == .weekly, let review = store.snapshot.weeklyReview {
        ToolbarItem(placement: .automatic) {
          ShareLink(item: MobileShareText.weeklyReview(review)) {
            Label(
              String(
                localized: "review.share_weekly", defaultValue: "Share Weekly",
                table: "Localizable", bundle: MobileL10n.bundle),
              systemImage: "square.and.arrow.up"
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

  private var journalSearchField: some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
      TextField(searchPrompt, text: $searchText)
        .textFieldStyle(.plain)
        .autocorrectionDisabled()
        #if os(iOS)
          .textInputAutocapitalization(.never)
        #endif
        .focused($searchFocused)
        .submitLabel(.search)
        .onSubmit { searchFocused = false }
        .accessibilityAddTraits(.isSearchField)
        .accessibilityIdentifier("review.search.field")
      if !searchText.isEmpty {
        Button {
          searchText = ""
          searchFocused = true
        } label: {
          Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            .frame(minWidth: 36, minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "common.clear_search", defaultValue: "Clear Search",
          table: "Localizable", bundle: MobileL10n.bundle))
        .accessibilityIdentifier("review.search.clear")
      }
    }
    .padding(.leading, LorvexDesign.Spacing.m)
    .padding(.trailing, LorvexDesign.Spacing.xs)
    .frame(minWidth: 160, idealWidth: 340, maxWidth: 480, minHeight: 44)
    .background(.quaternary, in: Capsule())
    .onAppear { searchFocused = true }
  }
}
